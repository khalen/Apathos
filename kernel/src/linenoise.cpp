/* linenoise.c -- guerrilla line editing library against the idea that a
 * line editing lib needs to be 20,000 lines of C code.
 *
 * You can find the latest source code at:
 *
 *   http://github.com/antirez/linenoise
 *
 * Does a number of crazy assumptions that happen to be true in 99.9999% of
 * the 2010 UNIX computers around.
 *
 * ------------------------------------------------------------------------
 *
 * Copyright (c) 2010-2023, Salvatore Sanfilippo <antirez at gmail dot com>
 * Copyright (c) 2010-2013, Pieter Noordhuis <pcnoordhuis at gmail dot com>
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *  *  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *
 *  *  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * ------------------------------------------------------------------------
 *
 * References:
 * - http://invisible-island.net/xterm/ctlseqs/ctlseqs.html
 * - http://www.3waylabs.com/nw/WWW/products/wizcon/vt220.html
 *
 * JLD note - hacked this to hell and back to get it to work in my toy
 * Forth OS. Removed a lot of unused features and TTY assumptions.
 * Next step: Port to Forth!
 *
 * List of escape sequences used by this program, we do everything just
 * with three sequences. In order to be so cheap we may have some
 * flickering effect with some slow terminal, but the lesser sequences
 * the more compatible.
 *
 * EL (Erase Line)
 *    Sequence: ESC [ n K
 *    Effect: if n is 0 or missing, clear from cursor to end of line
 *    Effect: if n is 1, clear from beginning of line to cursor
 *    Effect: if n is 2, clear entire line
 *
 * CUF (CUrsor Forward)
 *    Sequence: ESC [ n C
 *    Effect: moves cursor forward n chars
 *
 * CUB (CUrsor Backward)
 *    Sequence: ESC [ n D
 *    Effect: moves cursor backward n chars
 *
 * The following is used to get the terminal width if getting
 * the width with the TIOCGWINSZ ioctl fails
 *
 * DSR (Device Status Report)
 *    Sequence: ESC [ 6 n
 *    Effect: reports the current cusor position as ESC [ n ; m R
 *            where n is the row and m is the column
 *
 * When linenoiseClearScreen() is called, two additional escape sequences
 * are used in order to clear the screen and position the cursor at home
 * position.
 *
 * CUP (Cursor position)
 *    Sequence: ESC [ H
 *    Effect: moves the cursor to upper left corner
 *
 * ED (Erase display)
 *    Sequence: ESC [ 2 J
 *    Effect: clear the whole screen
 *
 */

#include "base_defs.h"
#include "linenoise.h"
#include "printf.h"
#include "mini_uart.h"
#include "mem.h"

#define printf      printf_
#define snprintf    snprintf_

#define LINENOISE_DEFAULT_HISTORY_MAX_LEN 100
#define LINENOISE_MAX_LINE 4096

static linenoiseHintsCallback *hintsCallback = 0;
static void refreshLineWithFlags(struct linenoiseState *l, int flags);

static int maskmode = 0; /* Show "***" instead of input. For passwords. */
static int mlmode = 0;  /* Multi line mode. Default is single line. */
static int history_len = 0;

enum KEY_ACTION{
	KEY_NULL = 0,	    /* NULL */
	CTRL_A = 1,         /* Ctrl+a */
	CTRL_B = 2,         /* Ctrl-b */
	CTRL_C = 3,         /* Ctrl-c */
	CTRL_D = 4,         /* Ctrl-d */
	CTRL_E = 5,         /* Ctrl-e */
	CTRL_F = 6,         /* Ctrl-f */
	CTRL_H = 8,         /* Ctrl-h */
	TAB = 9,            /* Tab */
	CTRL_K = 11,        /* Ctrl+k */
	CTRL_L = 12,        /* Ctrl+l */
	ENTER = 13,         /* Enter */
	CTRL_N = 14,        /* Ctrl-n */
	CTRL_P = 16,        /* Ctrl-p */
	CTRL_T = 20,        /* Ctrl-t */
	CTRL_U = 21,        /* Ctrl+u */
	CTRL_W = 23,        /* Ctrl+w */
	ESC = 27,           /* Escape */
	BACKSPACE =  127    /* Backspace */
};

int linenoiseHistoryAdd(const char *line);
#define REFRESH_CLEAN (1<<0)    // Clean the old prompt from the screen
#define REFRESH_WRITE (1<<1)    // Rewrite the prompt on the screen.
#define REFRESH_ALL (REFRESH_CLEAN|REFRESH_WRITE) // Do both.
static void refreshLine(struct linenoiseState *l);

/* Debugging macro. */
#if 0
FILE *lndebug_fp = NULL;
#define lndebug(...) \
    do { \
        if (lndebug_fp == NULL) { \
            lndebug_fp = fopen("/tmp/lndebug.txt","a"); \
            fprintf(lndebug_fp, \
            "[%d %d %d] p: %d, rows: %d, rpos: %d, max: %d, oldmax: %d\n", \
            (int)l->len,(int)l->pos,(int)l->oldpos,plen,rows,rpos, \
            (int)l->oldrows,old_rows); \
        } \
        fprintf(lndebug_fp, ", " __VA_ARGS__); \
        fflush(lndebug_fp); \
    } while (0)
#else
#define lndebug(fmt, ...)
#endif

static void parseNum(const char* str, int* num)
{
    int curNum = 0;
    for (; *str != 0; str++)
    {
        int c = *str - '0';
        curNum = curNum * 10 + c;
    }

    *num = curNum;
}

static void parseCoord(char *str, size_t max, int *rows, int *cols)
{
    const char *na = str, *nb;
    size_t c = 0;

    *rows = 0; *cols = 0;
    for (c = 0; c < max; c++)
    {
        if (str[c] == ';')
        {
            str[c] = 0;
            nb = &str[++c];

            parseNum(na, rows);
            parseNum(nb, cols);
            return;
        }
        if (str[c] == 0)
            break;
    }
    return;
}

/* Use the ESC [6n escape sequence to query the horizontal cursor position
 * and return it. On error -1 is returned, on success the position of the
 * cursor. */
static int getCursorPosition(int ifd, int ofd) {
    char buf[32];
    int cols, rows;
    unsigned int i = 0;

    /* Report cursor location */
    uart_write("\x1b[6n", 4);

    /* Read the response: ESC [ rows ; cols R */
    while (i < sizeof(buf)-1) {
        if (uart_read(buf+i,1) != 1) break;
        if (buf[i] == 'R') break;
        i++;
    }
    buf[i] = '\0';

    /* Parse it. */
    if (buf[0] != ESC || buf[1] != '[') return -1;
    parseCoord(buf + 2, 30, &rows, &cols);

    return cols;
}

/* Try to get the number of columns in the current terminal, or assume 80
 * if it fails. */
static int getColumns(int ifd, int ofd) {
    int start, cols;

    /* Get the initial position so we can restore it later. */
    start = getCursorPosition(ifd,ofd);

    /* Go to right margin and get position. */
    uart_write("\x1b[999C",6);

    cols = getCursorPosition(ifd,ofd);

    /* Restore position. */
    if (cols > start) {
        char seq[32];
        snprintf(seq,32,"\x1b[%dD",cols-start);
        uart_write(seq, strlen(seq));
    }

    return cols;
}

/* Clear the screen. Used to handle ctrl+l */
void linenoiseClearScreen(void) {
    uart_write("\x1b[H\x1b[2J", 7);
}

/* =========================== Line editing ================================= */
static char appendBuf[1024];

/* We define a very simple "append buffer" structure, that is an heap
 * allocated string where we can append to. This is useful in order to
 * write all the escape sequences in a buffer and flush them to the standard
 * output in a single call, to avoid flickering effects. */
struct abuf {
    char *b;
    int len;
};

static void abInit(struct abuf *ab) {
    ab->b = appendBuf;
    ab->len = 0;
}

static void abAppend(struct abuf *ab, const char *s, int len) {
    if (ab->len + len >= 1024)
        return;

    memcpy(ab->b + ab->len,s,len);
    ab->len += len;
}

static void abFree(struct abuf *ab) {
    abInit(ab);
}

/* Single line low level line refresh.
 *
 * Rewrite the currently edited line accordingly to the buffer content,
 * cursor position, and number of columns of the terminal.
 *
 * Flags is REFRESH_* macros. The function can just remove the old
 * prompt, just write it, or both. */
static void refreshSingleLine(struct linenoiseState *l, int flags) {
    char seq[64];
    size_t plen = strlen(l->prompt);
    char *buf = l->buf;
    size_t len = l->len;
    size_t pos = l->pos;
    struct abuf ab;

    while((plen+pos) >= l->cols) {
        buf++;
        len--;
        pos--;
    }
    while (plen+len > l->cols) {
        len--;
    }

    abInit(&ab);
    /* Cursor to left edge */
    snprintf(seq,sizeof(seq),"\r");
    abAppend(&ab,seq,strlen(seq));

    if (flags & REFRESH_WRITE) {
        /* Write the prompt and the current buffer content */
        abAppend(&ab,l->prompt,strlen(l->prompt));
        if (maskmode == 1) {
            while (len--) abAppend(&ab,"*",1);
        } else {
            abAppend(&ab,buf,len);
        }
    }

    /* Erase to right */
    snprintf(seq,sizeof(seq),"\x1b[0K");
    abAppend(&ab,seq,strlen(seq));

    if (flags & REFRESH_WRITE) {
        /* Move cursor to original position. */
        snprintf(seq,sizeof(seq),"\r\x1b[%dC", (int)(pos+plen));
        abAppend(&ab,seq,strlen(seq));
    }

    uart_write(ab.b,ab.len);
    abFree(&ab);
}

/* Calls the two low level functions refreshSingleLine() or
 * refreshMultiLine() according to the selected mode. */
static void refreshLineWithFlags(struct linenoiseState *l, int flags) {
    refreshSingleLine(l,flags);
}

/* Utility function to avoid specifying REFRESH_ALL all the times. */
static void refreshLine(struct linenoiseState *l) {
    refreshLineWithFlags(l,REFRESH_ALL);
}

/* Hide the current line, when using the multiplexing API. */
void linenoiseHide(struct linenoiseState *l) {
    refreshSingleLine(l,REFRESH_CLEAN);
}

/* Show the current line, when using the multiplexing API. */
void linenoiseShow(struct linenoiseState *l) {
    refreshLineWithFlags(l,REFRESH_WRITE);
}

/* Insert the character 'c' at cursor current position.
 *
 * On error writing to the terminal -1 is returned, otherwise 0. */
int linenoiseEditInsert(struct linenoiseState *l, char c) {
    if (l->len < l->buflen) {
        if (l->len == l->pos) {
            l->buf[l->pos] = c;
            l->pos++;
            l->len++;
            l->buf[l->len] = '\0';
            if ((!mlmode && l->plen+l->len < l->cols && !hintsCallback)) {
                /* Avoid a full update of the line in the
                 * trivial case. */
                char d = (maskmode==1) ? '*' : c;
                uart_write(&d,1);
            } else {
                refreshLine(l);
            }
        } else {
            memmove(l->buf+l->pos+1,l->buf+l->pos,l->len-l->pos);
            l->buf[l->pos] = c;
            l->len++;
            l->pos++;
            l->buf[l->len] = '\0';
            refreshLine(l);
        }
    }
    return 0;
}

/* Move cursor on the left. */
void linenoiseEditMoveLeft(struct linenoiseState *l) {
    if (l->pos > 0) {
        l->pos--;
        refreshLine(l);
    }
}

/* Move cursor on the right. */
void linenoiseEditMoveRight(struct linenoiseState *l) {
    if (l->pos != l->len) {
        l->pos++;
        refreshLine(l);
    }
}

/* Move cursor to the start of the line. */
void linenoiseEditMoveHome(struct linenoiseState *l) {
    if (l->pos != 0) {
        l->pos = 0;
        refreshLine(l);
    }
}

/* Move cursor to the end of the line. */
void linenoiseEditMoveEnd(struct linenoiseState *l) {
    if (l->pos != l->len) {
        l->pos = l->len;
        refreshLine(l);
    }
}

/* Substitute the currently edited line with the next or previous history
 * entry as specified by 'dir'. */
#define LINENOISE_HISTORY_NEXT 0
#define LINENOISE_HISTORY_PREV 1
void linenoiseEditHistoryNext(struct linenoiseState *l, int dir) {
    #if 0
    if (history_len > 1) {
        /* Update the current history entry before to
         * overwrite it with the next one. */
        free(history[history_len - 1 - l->history_index]);
        history[history_len - 1 - l->history_index] = strdup(l->buf);
        /* Show the new entry */
        l->history_index += (dir == LINENOISE_HISTORY_PREV) ? 1 : -1;
        if (l->history_index < 0) {
            l->history_index = 0;
            return;
        } else if (l->history_index >= history_len) {
            l->history_index = history_len-1;
            return;
        }
        strncpy(l->buf,history[history_len - 1 - l->history_index],l->buflen);
        l->buf[l->buflen-1] = '\0';
        l->len = l->pos = strlen(l->buf);
        refreshLine(l);
    }
    #endif
}

/* Delete the character at the right of the cursor without altering the cursor
 * position. Basically this is what happens with the "Delete" keyboard key. */
void linenoiseEditDelete(struct linenoiseState *l) {
    if (l->len > 0 && l->pos < l->len) {
        memmove(l->buf+l->pos,l->buf+l->pos+1,l->len-l->pos-1);
        l->len--;
        l->buf[l->len] = '\0';
        refreshLine(l);
    }
}

/* Backspace implementation. */
void linenoiseEditBackspace(struct linenoiseState *l) {
    if (l->pos > 0 && l->len > 0) {
        memmove(l->buf+l->pos-1,l->buf+l->pos,l->len-l->pos);
        l->pos--;
        l->len--;
        l->buf[l->len] = '\0';
        refreshLine(l);
    }
}

/* Delete the previosu word, maintaining the cursor at the start of the
 * current word. */
void linenoiseEditDeletePrevWord(struct linenoiseState *l) {
    size_t old_pos = l->pos;
    size_t diff;

    while (l->pos > 0 && l->buf[l->pos-1] == ' ')
        l->pos--;
    while (l->pos > 0 && l->buf[l->pos-1] != ' ')
        l->pos--;
    diff = old_pos - l->pos;
    memmove(l->buf+l->pos,l->buf+old_pos,l->len-old_pos+1);
    l->len -= diff;
    refreshLine(l);
}

/* This function is part of the multiplexed API of Linenoise, that is used
 * in order to implement the blocking variant of the API but can also be
 * called by the user directly in an event driven program. It will:
 *
 * 1. Initialize the linenoise state passed by the user.
 * 2. Put the terminal in RAW mode.
 * 3. Show the prompt.
 * 4. Return control to the user, that will have to call linenoiseEditFeed()
 *    each time there is some data arriving in the standard input.
 *
 * The user can also call linenoiseEditHide() and linenoiseEditShow() if it
 * is required to show some input arriving asyncronously, without mixing
 * it with the currently edited line.
 *
 * When linenoiseEditFeed() returns non-NULL, the user finished with the
 * line editing session (pressed enter CTRL-D/C): in this case the caller
 * needs to call linenoiseEditStop() to put back the terminal in normal
 * mode. This will not destroy the buffer, as long as the linenoiseState
 * is still valid in the context of the caller.
 *
 * The function returns 0 on success, or -1 if writing to standard output
 * fails. If stdin_fd or stdout_fd are set to -1, the default is to use
 * STDIN_FILENO and STDOUT_FILENO.
 */
int linenoiseEditStart(struct linenoiseState *l, int stdin_fd, int stdout_fd, char *buf, size_t buflen, const char *prompt) {
    /* Populate the linenoise state that we pass to functions implementing
     * specific editing functionalities. */
    l->in_completion = 0;
    l->ifd = stdin_fd != -1 ? stdin_fd : 1;
    l->ofd = stdout_fd != -1 ? stdout_fd : 0;
    l->buf = buf;
    l->buflen = buflen;
    l->prompt = prompt;
    l->plen = strlen(prompt);
    l->oldpos = l->pos = 0;
    l->len = 0;
    l->cols = getColumns(stdin_fd, stdout_fd);
    l->oldrows = 0;
    l->history_index = 0;

    /* Buffer starts empty. */
    l->buf[0] = '\0';
    l->buflen--; /* Make sure there is always space for the nulterm */

    /* The latest history entry is always our current buffer, that
     * initially is just an empty string. */
    linenoiseHistoryAdd("");

    uart_write(prompt,l->plen);
    return 0;
}

static char moreMsg[] = "If you see this, you are misusing the API: when linenoiseEditFeed() is called, if it returns linenoiseEditMore the user is yet editing the line. See the README file for more information.";
char *linenoiseEditMore = moreMsg;

/* This function is part of the multiplexed API of linenoise, see the top
 * comment on linenoiseEditStart() for more information. Call this function
 * each time there is some data to read from the standard input file
 * descriptor. In the case of blocking operations, this function can just be
 * called in a loop, and block.
 *
 * The function returns linenoiseEditMore to signal that line editing is still
 * in progress, that is, the user didn't yet pressed enter / CTRL-D. Otherwise
 * the function returns the pointer to the heap-allocated buffer with the
 * edited line, that the user should free with linenoiseFree().
 *
 * On special conditions, NULL is returned and errno is populated:
 *
 * EAGAIN if the user pressed Ctrl-C
 * ENOENT if the user pressed Ctrl-D
 *
 * Some other errno: I/O error.
 */
char *linenoiseEditFeed(struct linenoiseState *l) {
    char c;
    int nread;
    char seq[3];

    nread = uart_read(&c,1);
    if (nread <= 0) return 0;

    switch(c) {
    case ENTER:    /* enter */
        history_len--;
        if (mlmode) linenoiseEditMoveEnd(l);
        return l->buf;
    case CTRL_C:     /* ctrl-c */
        return 0;
    case BACKSPACE:   /* backspace */
    case 8:     /* ctrl-h */
        linenoiseEditBackspace(l);
        break;
    case CTRL_D:     /* ctrl-d, remove char at right of cursor, or if the
                        line is empty, act as end-of-file. */
        if (l->len > 0) {
            linenoiseEditDelete(l);
        } else {
            history_len--;
            return 0;
        }
        break;
    case CTRL_T:    /* ctrl-t, swaps current character with previous. */
        if (l->pos > 0 && l->pos < l->len) {
            int aux = l->buf[l->pos-1];
            l->buf[l->pos-1] = l->buf[l->pos];
            l->buf[l->pos] = aux;
            if (l->pos != l->len-1) l->pos++;
            refreshLine(l);
        }
        break;
    case CTRL_B:     /* ctrl-b */
        linenoiseEditMoveLeft(l);
        break;
    case CTRL_F:     /* ctrl-f */
        linenoiseEditMoveRight(l);
        break;
    case CTRL_P:    /* ctrl-p */
        linenoiseEditHistoryNext(l, LINENOISE_HISTORY_PREV);
        break;
    case CTRL_N:    /* ctrl-n */
        linenoiseEditHistoryNext(l, LINENOISE_HISTORY_NEXT);
        break;
    case ESC:    /* escape sequence */
        /* Read the next two bytes representing the escape sequence.
         * Use two calls to handle slow terminals returning the two
         * chars at different times. */
        uart_read(seq,1);
        uart_read(seq+1,1);

        /* ESC [ sequences. */
        if (seq[0] == '[') {
            if (seq[1] >= '0' && seq[1] <= '9') {
                /* Extended escape, read additional byte. */
                uart_read(seq+2,1);
                if (seq[2] == '~') {
                    switch(seq[1]) {
                    case '3': /* Delete key. */
                        linenoiseEditDelete(l);
                        break;
                    }
                }
            } else {
                switch(seq[1]) {
                case 'A': /* Up */
                    linenoiseEditHistoryNext(l, LINENOISE_HISTORY_PREV);
                    break;
                case 'B': /* Down */
                    linenoiseEditHistoryNext(l, LINENOISE_HISTORY_NEXT);
                    break;
                case 'C': /* Right */
                    linenoiseEditMoveRight(l);
                    break;
                case 'D': /* Left */
                    linenoiseEditMoveLeft(l);
                    break;
                case 'H': /* Home */
                    linenoiseEditMoveHome(l);
                    break;
                case 'F': /* End*/
                    linenoiseEditMoveEnd(l);
                    break;
                }
            }
        }

        /* ESC O sequences. */
        else if (seq[0] == 'O') {
            switch(seq[1]) {
            case 'H': /* Home */
                linenoiseEditMoveHome(l);
                break;
            case 'F': /* End*/
                linenoiseEditMoveEnd(l);
                break;
            }
        }
        break;
    default:
        if (linenoiseEditInsert(l,c)) return 0;
        break;
    case CTRL_U: /* Ctrl+u, delete the whole line. */
        l->buf[0] = '\0';
        l->pos = l->len = 0;
        refreshLine(l);
        break;
    case CTRL_K: /* Ctrl+k, delete from current to end of line. */
        l->buf[l->pos] = '\0';
        l->len = l->pos;
        refreshLine(l);
        break;
    case CTRL_A: /* Ctrl+a, go to the start of the line */
        linenoiseEditMoveHome(l);
        break;
    case CTRL_E: /* ctrl+e, go to the end of the line */
        linenoiseEditMoveEnd(l);
        break;
    case CTRL_L: /* ctrl+l, clear screen */
        linenoiseClearScreen();
        refreshLine(l);
        break;
    case CTRL_W: /* ctrl+w, delete previous word */
        linenoiseEditDeletePrevWord(l);
        break;
    }
    return linenoiseEditMore;
}

/* This is part of the multiplexed linenoise API. See linenoiseEditStart()
 * for more information. This function is called when linenoiseEditFeed()
 * returns something different than NULL. At this point the user input
 * is in the buffer, and we can restore the terminal in normal mode. */
void linenoiseEditStop(struct linenoiseState *l) {
    printf("\n");
}

/* This just implements a blocking loop for the multiplexed API.
 * In many applications that are not event-drivern, we can just call
 * the blocking linenoise API, wait for the user to complete the editing
 * and return the buffer. */
static char *linenoiseBlockingEdit(int stdin_fd, int stdout_fd, char *buf, size_t buflen, const char *prompt)
{
    struct linenoiseState l;

    /* Editing without a buffer is invalid. */
    if (buflen == 0) {
        return 0;
    }

    linenoiseEditStart(&l,stdin_fd,stdout_fd,buf,buflen,prompt);
    char *res;
    while((res = linenoiseEditFeed(&l)) == linenoiseEditMore);
    linenoiseEditStop(&l);
    return res;
}

/* The high level function that is the main API of the linenoise library.
 * This function checks if the terminal has basic capabilities, just checking
 * for a blacklist of stupid terminals, and later either calls the line
 * editing function or uses dummy fgets() so that you will be able to type
 * something even in the most desperate of the conditions. */
char *linenoise(const char *prompt) {
    char buf[LINENOISE_MAX_LINE];

    char *retval = linenoiseBlockingEdit(1, 0,buf,LINENOISE_MAX_LINE,prompt);
    return retval;
}

/* This is just a wrapper the user may want to call in order to make sure
 * the linenoise returned buffer is freed with the same allocator it was
 * created with. Useful when the main program is using an alternative
 * allocator. */
void linenoiseFree(void *ptr) {
    if (ptr == linenoiseEditMore) return; // Protect from API misuse.
}

/* ================================ History ================================= */

/* This is the API call to add a new entry in the linenoise history.
 * It uses a fixed array of char pointers that are shifted (memmoved)
 * when the history max length is reached in order to remove the older
 * entry and make room for the new one, so it is not exactly suitable for huge
 * histories, but will work well for a few hundred of entries.
 *
 * Using a circular buffer is smarter, but a bit more complex to handle. */
int linenoiseHistoryAdd(const char *line) {
    #if 0
    char *linecopy;

    if (history_max_len == 0) return 0;

    /* Initialization on first call. */
    if (history == NULL) {
        history = malloc(sizeof(char*)*history_max_len);
        if (history == NULL) return 0;
        memset(history,0,(sizeof(char*)*history_max_len));
    }

    /* Don't add duplicated lines. */
    if (history_len && !strcmp(history[history_len-1], line)) return 0;

    /* Add an heap allocated copy of the line in the history.
     * If we reached the max length, remove the older line. */
    linecopy = strdup(line);
    if (!linecopy) return 0;
    if (history_len == history_max_len) {
        free(history[0]);
        memmove(history,history+1,sizeof(char*)*(history_max_len-1));
        history_len--;
    }
    history[history_len] = linecopy;
    history_len++;
    #endif
    return 1;
}

/* Set the maximum length for the history. This function can be called even
 * if there is already some history, the function will make sure to retain
 * just the latest 'len' elements if the new history length value is smaller
 * than the amount of items already inside the history. */
int linenoiseHistorySetMaxLen(int len) {
    #if 0
    char **new;

    if (len < 1) return 0;
    if (history) {
        int tocopy = history_len;

        new = malloc(sizeof(char*)*len);
        if (new == NULL) return 0;

        /* If we can't copy everything, free the elements we'll not use. */
        if (len < tocopy) {
            int j;

            for (j = 0; j < tocopy-len; j++) free(history[j]);
            tocopy = len;
        }
        memset(new,0,sizeof(char*)*len);
        memcpy(new,history+(history_len-tocopy), sizeof(char*)*tocopy);
        free(history);
        history = new;
    }
    history_max_len = len;
    if (history_len > history_max_len)
        history_len = history_max_len;
    #endif
    return 1;
}

/* Save the history in the specified file. On success 0 is returned
 * otherwise -1 is returned. */
int linenoiseHistorySave(const char *filename) {
    #if 0
    mode_t old_umask = umask(S_IXUSR|S_IRWXG|S_IRWXO);
    FILE *fp;
    int j;

    fp = fopen(filename,"w");
    umask(old_umask);
    if (fp == NULL) return -1;
    chmod(filename,S_IRUSR|S_IWUSR);
    for (j = 0; j < history_len; j++)
        fprintf(fp,"%s\n",history[j]);
    fclose(fp);
    #endif
    return 0;
}

/* Load the history from the specified file. If the file does not exist
 * zero is returned and no operation is performed.
 *
 * If the file exists and the operation succeeded 0 is returned, otherwise
 * on error -1 is returned. */
int linenoiseHistoryLoad(const char *filename) {
    #if 0
    FILE *fp = fopen(filename,"r");
    char buf[LINENOISE_MAX_LINE];

    if (fp == NULL) return -1;

    while (fgets(buf,LINENOISE_MAX_LINE,fp) != NULL) {
        char *p;

        p = strchr(buf,'\r');
        if (!p) p = strchr(buf,'\n');
        if (p) *p = '\0';
        linenoiseHistoryAdd(buf);
    }
    fclose(fp);
    #endif
    return 0;
}
