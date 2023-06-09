#include <ctime>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <sys/fcntl.h>
#include <sys/stat.h>
#include <sys/termios.h>
#include <sys/types.h>
#include <system_error>
#include <termios.h>
#include <unistd.h>

#define DEFAULT_TTY	   "/dev/tty.usbserial-0001"
#define DEFAULT_KERNEL "images/kernel8.img"
#define PROGRESS_WIDTH 75
#define BAUD		   921600

const static ssize_t kMaxXferSize = 0x2000000;
const static int32_t kBufSize	  = 0xFFFF;
const static float	 kTimeout	  = 5000.0f; // Timeout for (mostly) transfer writes in milliseconds

static struct Globals
{
	volatile bool  quitNow;
	struct termios oldTio;
	bool		   needStdinTioRestore;
	int32_t		   serialFd;
	int32_t		   sendFd;

	int32_t maxFd = STDIN_FILENO;
	fd_set	rdFds, wrFds, erFds;
	char	kernelFileName[PATH_MAX];
	char	ttyFileName[PATH_MAX];

	int32_t breakCount;
	int32_t exitCode;
	bool	gotCtrlT;

	uint8_t xferBuf[kBufSize];

	uint32_t baudRate;

	Globals()
		: quitNow(false), needStdinTioRestore(false), serialFd(-1), sendFd(-1), maxFd(STDIN_FILENO), breakCount(0),
		  exitCode(0), gotCtrlT(false), baudRate(BAUD)
	{
		FD_ZERO(&rdFds);
		FD_ZERO(&wrFds);
		FD_ZERO(&erFds);
	}
} g;

class Timer
{
  private:
	float startTimeMs;
	float targetMs;

  public:
	static float GetCurTimeMs()
	{
		struct timespec ts;
		clock_gettime(CLOCK_MONOTONIC, &ts);
		return ts.tv_sec * 1000.0f + ts.tv_nsec / 1.0e6;
	}

	Timer(const float target = kTimeout)
	{
		Reset(target);
	}

	void Reset(const float target = kTimeout)
	{
		startTimeMs = GetCurTimeMs();
		targetMs	= target;
	}

	bool IsElapsed()
	{
		return (GetCurTimeMs() - startTimeMs) > targetMs;
	}
};

void quitRunning(int)
{
	g.quitNow = true;
}

void usage()
{
	printf("Usage: conman [args] [tty]\n");
	printf("Args:\n");
	printf("\t-k <kernelFileName> : Use <kernelFileName> as the file to upload when a transfer is initiated\n");
	printf("\t<tty> : Use <tty> as the serial port to communicate on with the target\n");
}

void cleanUpOnExit()
{
	if (g.needStdinTioRestore)
	{
		tcsetattr(STDIN_FILENO, TCSANOW, &g.oldTio);
	}
	if (g.serialFd != -1)
	{
		close(g.serialFd);
	}
	if (g.sendFd != -1)
	{
		close(g.sendFd);
	}
}

void barGraph(int32_t percentage)
{
	fprintf(stderr, "\r[");
	int32_t barCount   = PROGRESS_WIDTH * percentage / 100;
	int32_t spaceCount = PROGRESS_WIDTH - barCount;
	for (int i = 0; i < barCount; i++)
	{
		fprintf(stderr, "=");
	}
	for (int i = 0; i < spaceCount; i++)
	{
		fprintf(stderr, " ");
	}
	fprintf(stderr, "]");
	fflush(stdout);
}

void sendFile(const char *fileName)
{
	fprintf(stderr, "### File transfer request for %s received...\r\n", g.kernelFileName);
	g.sendFd = open(fileName, O_RDONLY);
	if (g.sendFd < 0)
	{
		fprintf(stderr, "### %s failed to open: %s", g.kernelFileName, strerror(errno));
		g.quitNow = true;
		return;
	}

	ssize_t fileSize = lseek(g.sendFd, 0L, SEEK_END);
	if (fileSize > kMaxXferSize)
	{
		fprintf(stderr, "### %s is too large : %ld > %ld bytes\r\n", g.kernelFileName, fileSize, kMaxXferSize);
		g.quitNow = true;
		return;
	}
	fprintf(stderr, "### Sending %ld bytes...\r\n", fileSize);

	lseek(g.sendFd, 0L, SEEK_SET);

	// xmit size
	for (int i = 0; g.quitNow == false && i < 4; i++)
	{
		uint8_t c = (fileSize >> (8 * i)) & 0xFF;
		write(g.serialFd, &c, 1);
	}

	// Wait for OK
	char	buf[2];
	ssize_t bufLen = 0;
	while (!g.quitNow && bufLen < 2)
	{
		bufLen += read(g.serialFd + bufLen, buf, 2 - bufLen);
	}
	if (buf[0] != 'O' || buf[1] != 'K')
	{
		fprintf(stderr, "### Got unexpected response waiting for 'OK': %c%c\r\n", buf[0], buf[1]);
		g.quitNow = true;
		return;
	}

	barGraph(0);

	Timer barTimer(150.0);
	Timer writeTimer(kTimeout);

	ssize_t sentBytes = 0;
	float	pctSlope  = 100.0f / fileSize;
	while (!g.quitNow && fileSize > sentBytes)
	{
		int		bufSent = 0;
		ssize_t bufLen	= read(g.sendFd, g.xferBuf, sizeof(g.xferBuf));
		while (!g.quitNow && bufLen > 0)
		{
			if (barTimer.IsElapsed())
			{
				int32_t pctDone = lround(pctSlope * sentBytes);
				barGraph(pctDone);
				barTimer.Reset();
			}
			ssize_t curSent = write(g.serialFd, g.xferBuf + bufSent, bufLen);
			if (curSent <= 0)
			{
				// fprintf(stderr, "\r\ncurSent < 0: %s\r\n", strerror(errno));
				if (writeTimer.IsElapsed())
				{
					fprintf(stderr, "\r\n#### Timeout writing to the serial device at byte %ld of %ld\r\n", sentBytes,
							fileSize);
					sentBytes = fileSize;
					break;
				}
				continue;
			}
			writeTimer.Reset(kTimeout);
			// fprintf(stderr, "\r\nSent: 0x%lx  So far: 0x%lx  BufLen: 0x%lx  FileSize: 0x%lx\r\n", curSent, sentBytes,
			// bufLen, fileSize);
			bufLen	  -= curSent;
			bufSent	  += curSent;
			sentBytes += curSent;
		}
	}

	barGraph(100);

	fprintf(stderr, "\r\n### Done.\r\n");
}

int main(int argc, char *argv[])
{
	printf("Con Man version 15.62\r\n");

	for (int i = 1; i < argc; i++)
	{
		if (argv[i][0] == '-')
		{
			switch (argv[i][1])
			{
			case 'k':
				if (i >= argc)
				{
					usage();
				}
				strncpy(g.kernelFileName, argv[++i], PATH_MAX - 1);
				g.kernelFileName[PATH_MAX - 1] = 0;
				break;
			case 'b':
				if (i >= argc)
				{
					usage();
				}
				g.baudRate = atoi(argv[++i]);
				break;
			}
		}
		else
		{
			strncpy(g.ttyFileName, argv[i], PATH_MAX - 1);
			g.ttyFileName[PATH_MAX - 1] = 0;
		}
	}

	if (g.kernelFileName[0] == 0)
	{
		strcpy(g.kernelFileName, DEFAULT_KERNEL);
	}

	if (g.ttyFileName[0] == 0)
	{
		strcpy(g.ttyFileName, DEFAULT_TTY);
	}

	atexit(cleanUpOnExit);

	struct termios newTio;
	if (isatty(STDIN_FILENO))
	{
		g.needStdinTioRestore = true;
		tcgetattr(STDIN_FILENO, &g.oldTio);

		newTio			= g.oldTio;
		newTio.c_lflag &= ~ICANON;
		newTio.c_lflag &= ~ECHO;

		tcsetattr(STDIN_FILENO, TCSANOW, &newTio);
	}

	signal(SIGINT, quitRunning);
	signal(SIGTERM, quitRunning);

	bool printedMessage = false;
	while (!g.quitNow)
	{
		g.serialFd = open(g.ttyFileName, O_RDWR | O_NOCTTY | O_NONBLOCK);
		if (g.serialFd == -1)
		{
			if (errno == ENOENT || errno == ENODEV || errno == EACCES)
			{
				if (!printedMessage)
				{
					fprintf(stderr, "\r### Waiting to open %s...\n", g.ttyFileName);
					printedMessage = true;
				}

				sleep(1);
				continue;
			}
		}
		else if (!isatty(g.serialFd))
		{
			fprintf(stderr, "%s is not a tty\n", g.ttyFileName);
			g.quitNow = true;
			break;
		}

		struct termios tios;
		tcgetattr(g.serialFd, &tios);

		// Poll the tty and stdin
		tios.c_cc[VTIME] = 0;
		tios.c_cc[VMIN]	 = 0;

		// 8N1 no masks
		tios.c_iflag = 0;
		tios.c_iflag = 0;
		tios.c_cflag = CS8 | CREAD | CLOCAL;
		tios.c_lflag = 0;

		cfsetispeed(&tios, g.baudRate);
		cfsetospeed(&tios, g.baudRate);

		tcsetattr(g.serialFd, TCSAFLUSH, &tios);

		fprintf(stderr, "### Listening on %s. Ctrl-T q (or just Ctrl-C) to quit.\n", g.ttyFileName);

		if (g.serialFd > STDIN_FILENO)
		{
			g.maxFd = g.serialFd + 1;
		}
		else
		{
			g.maxFd = STDIN_FILENO + 1;
		}

		while (!g.quitNow)
		{
			FD_ZERO(&g.rdFds);
			FD_SET(STDIN_FILENO, &g.rdFds);
			FD_SET(g.serialFd, &g.rdFds);

			// Monitor stdin and serial for error
			FD_ZERO(&g.erFds);
			FD_SET(STDIN_FILENO, &g.erFds);
			FD_SET(g.serialFd, &g.erFds);

			FD_ZERO(&g.wrFds);

			// Wait for available input
			ssize_t numFds = select(g.maxFd, &g.rdFds, &g.wrFds, &g.erFds, nullptr);
			(void)numFds;

			if (FD_ISSET(STDIN_FILENO, &g.erFds))
			{
				fprintf(stderr, "### Select returned error on STDIN, exiting..\r\n");
				g.quitNow  = true;
				g.exitCode = 1;
				break;
			}
			if (FD_ISSET(g.serialFd, &g.erFds))
			{
				fprintf(stderr, "Select returned error on %s, exiting..\r\n", g.ttyFileName);
				g.quitNow  = true;
				g.exitCode = 1;
				break;
			}

			// Input from user?
			if (FD_ISSET(STDIN_FILENO, &g.rdFds))
			{
				uint8_t c;

				// Mirror to the tty
				ssize_t readLen = read(STDIN_FILENO, &c, 1);
				if (readLen == 0)
				{
					// Probably EOF
					g.quitNow = true;
					break;
				}

				if (g.gotCtrlT)
				{
					if (c == 'q')
					{
						fprintf(stdout, "### Quit requested.\r\n");
						g.exitCode = 0;
						g.quitNow  = true;

						break;
					}
					else
					{
						g.gotCtrlT = false;
					}
				}

				if (c == 20)
				{
					g.gotCtrlT = true;
				}

				ssize_t writeLen = write(g.serialFd, &c, 1);
				if (writeLen == 0)
				{
					break;
				}
			}

			// Input from tty?
			if (FD_ISSET(g.serialFd, &g.rdFds))
			{
				uint8_t c;

				ssize_t readLen = read(g.serialFd, &c, 1);
				if (readLen == 0)
				{
					break;
				}

				// Watch for triple break - \03\03\03. Any other input resets the count and will mirror any breaks
				// received < 3.
				if (c == '\x03')
				{
					++g.breakCount;

					if (g.breakCount == 3)
					{
						sendFile(g.kernelFileName);
						g.breakCount = 0;
					}
				}
				else
				{
					// Mirror any breaks we already got
					while (g.breakCount > 0)
					{
						ssize_t writeLen = write(STDOUT_FILENO, "\x03\x03\x03", g.breakCount);
						if (writeLen == 0)
						{
							g.quitNow = true;
							break;
						}
						g.breakCount -= writeLen;
					}
				}
				if (g.quitNow == false)
				{
					ssize_t writeLen = write(STDOUT_FILENO, &c, 1);
					if (writeLen != 1)
					{
						g.quitNow = true;
						break;
					}
				}
			}
		}
	}

	return g.exitCode;
}
