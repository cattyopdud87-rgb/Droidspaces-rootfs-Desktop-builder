/*
 * libdroidspaces-compat.c - Droidspaces Android/Linux 4.14 Compatibility Shim
 *
 * Problem:
 * Android kernels (notably 4.14 and 4.19 backports) define syscall 434 (pidfd_open)
 * so pidfd_open() succeeds and returns a valid process file descriptor.
 * However, Linux 4.14 kernel/exit.c:kernel_waitid() does NOT implement P_PIDFD (3),
 * returning -EINVAL on any waitid(P_PIDFD, pidfd, ...).
 *
 * Modern GLib (>= 2.74, including GLib 2.90 in Arch Linux ARM) tests if pidfd_open
 * succeeds. When it does, GLib assumes waitid(P_PIDFD) works. When waitid fails with
 * EINVAL, GLib emits a warning, leaves the child process un-reaped as a permanent
 * zombie, and leaks PIDs/resources.
 *
 * Solution:
 * Intercept pidfd_open() and syscall(__NR_pidfd_open) to return -1 with errno = ENOSYS.
 * This instructs GLib to cleanly fall back to POSIX SIGCHLD + waitpid(), which is
 * 100% reliable on Linux 4.14 and cleanly reaps all child processes with exit status 0.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <sys/syscall.h>

#ifndef __NR_pidfd_open
#if defined(__aarch64__)
#define __NR_pidfd_open 434
#elif defined(__arm__)
#define __NR_pidfd_open 434
#elif defined(__x86_64__)
#define __NR_pidfd_open 434
#elif defined(__i386__)
#define __NR_pidfd_open 434
#elif defined(__riscv)
#define __NR_pidfd_open 434
#endif
#endif

/* Exported pidfd_open glibc wrapper */
int pidfd_open(int pid, unsigned int flags) {
    (void)pid;
    (void)flags;
    errno = ENOSYS;
    return -1;
}

/* Exported syscall wrapper */
static long (*real_syscall)(long, long, long, long, long, long, long) = NULL;

long syscall(long number, ...) {
#ifdef __NR_pidfd_open
    if (number == __NR_pidfd_open) {
        errno = ENOSYS;
        return -1;
    }
#endif
    if (!real_syscall) {
        real_syscall = (long (*)(long, long, long, long, long, long, long))dlsym(RTLD_NEXT, "syscall");
    }

    va_list args;
    va_start(args, number);
    long a1 = va_arg(args, long);
    long a2 = va_arg(args, long);
    long a3 = va_arg(args, long);
    long a4 = va_arg(args, long);
    long a5 = va_arg(args, long);
    long a6 = va_arg(args, long);
    va_end(args);

    if (real_syscall) {
        return real_syscall(number, a1, a2, a3, a4, a5, a6);
    }

    errno = ENOSYS;
    return -1;
}
