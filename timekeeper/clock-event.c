#define _GNU_SOURCE
#include "clock-event.h"
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* Keep validation pure so stale/replayed/overwritten clock cases can be tested. */
static int valid_event(const struct clock_event *e, const char *boot_id,
                       double now, double uptime)
{
    double age = uptime - ((double)e->uptime + e->uptime_nsec / 1e9);
    double predicted = (double)e->epoch + e->nsec / 1e9 + age;
    return (!strcmp(e->source, "NITZ") || !strcmp(e->source, "SNTP")) &&
        !strcmp(e->boot_id, boot_id) && e->epoch >= 1767225600 && e->epoch <= 4102444800 &&
        e->nsec >= 0 && e->nsec < 1000000000 && e->uptime >= 0 &&
        e->uptime_nsec >= 0 && e->uptime_nsec < 1000000000 &&
        age >= 0 && age <= EVENT_MAX_AGE && fabs(now - predicted) <= 0.25;
}
#ifndef CLOCK_EVENT_TEST
int main(int argc, char **argv)
{
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "epoch"))) return 2;
    char text[256] = {0}, boot_id[38] = {0}, extra;
    struct clock_event e = {0};
    struct stat st;
    struct timespec now, boot;
    long long epoch, uptime;
    int fd = open(EVENT_FILE, O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if (fd < 0) return 1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 0077) ||
        st.st_size <= 0 || st.st_size >= (off_t)sizeof(text)) { close(fd); return 1; }
    ssize_t n = read(fd, text, sizeof(text)-1); close(fd);
    if (n != st.st_size || sscanf(text, "v1 %36s %7s %lld %ld %lld %ld %c", e.boot_id,
        e.source, &epoch, &e.nsec, &uptime, &e.uptime_nsec, &extra) != 6) return 1;
    e.epoch = epoch; e.uptime = uptime;
    fd = open("/proc/sys/kernel/random/boot_id", O_RDONLY|O_CLOEXEC);
    if (fd < 0) return 1;
    n = read(fd, boot_id, 36); close(fd);
    if (n != 36 || clock_gettime(CLOCK_REALTIME, &now) || clock_gettime(CLOCK_BOOTTIME, &boot)) return 1;
    if (!valid_event(&e, boot_id, now.tv_sec + now.tv_nsec / 1e9, boot.tv_sec + boot.tv_nsec / 1e9)) return 1;
    if (argc == 2) {
        double age = boot.tv_sec + boot.tv_nsec / 1e9 - (e.uptime + e.uptime_nsec / 1e9);
        printf("%lld\n", (long long)(e.epoch + e.nsec / 1e9 + age));
    } else {
        printf("%s:%lld:%ld\n", e.source, (long long)e.uptime, e.uptime_nsec);
    }
    return 0;
}
#endif
