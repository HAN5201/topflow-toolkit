#ifndef TOPFLOW_CLOCK_EVENT_H
#define TOPFLOW_CLOCK_EVENT_H
#include <stdint.h>
#define EVENT_DIR "/tmp/timekeeper-events"
#define EVENT_FILE EVENT_DIR "/latest"
#define EVENT_MAX_AGE 120
struct clock_event {
    char boot_id[37];
    char source[8];
    int64_t epoch;
    long nsec;
    int64_t uptime;
    long uptime_nsec;
};
#endif
