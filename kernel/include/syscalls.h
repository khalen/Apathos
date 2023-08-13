#ifndef SYSCALLS_H_
#define SYSCALLS_H_

// This is a selection of macos syscalls

#include "base_defs.h"
#define	SYS_exit           1		// 0
#define	SYS_read           3		// 3
#define	SYS_write          4		// 3
#define	SYS_open           5		// 3
#define	SYS_close          6		// 1
#define	SYS_unlink         10		// 1
#define	SYS_chdir          12		// 1
#define	SYS_chmod          15		// 2
#define	SYS_ioctl          54		// n
#define	SYS_reboot         55		// 0
#define	SYS_mkdir	       136		// 2
#define	SYS_mmap	       197		// 6
#define	SYS_lseek          199		// 3
#define SYS_format		   201		// 1

#define SYSCALL_MAX		   256

#define O_RDONLY         00
#define O_WRONLY         01
#define O_RDWR           02

#define O_CREAT        0100
#define O_TRUNC       01000
#define O_APPEND      02000
#define O_NONBLOCK    04000
#define O_BINARY    0100000
#define O_DIRECTORY 0200000

#define O_PATH    010000000

#define SEEK_SET	0
#define SEEK_CUR	1
#define SEEK_END	2

struct timespec
{
	i32	tv_sec;
	i32	tv_nsec;
};

 struct stat
 { /* when _DARWIN_FEATURE_64_BIT_INODE is defined */
		 i32             st_dev;           /* ID of device containing file */
		 u32             st_mode;          /* Mode of file (see below) */
		 struct timespec st_mtimespec;     /* time of last data modification */
		 i64             st_size;          /* file size, in bytes */
		 u32             st_ino;           /* File serial number */
		 u32             st_pad;
};

extern void syscalls_init();

#endif // SYSCALLS_H_
