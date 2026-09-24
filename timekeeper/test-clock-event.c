#define CLOCK_EVENT_TEST
#include "clock-event.c"
#include <assert.h>
int main(void)
{
    const char *id = "01234567-89ab-cdef-0123-456789abcdef";
    struct clock_event e = {"01234567-89ab-cdef-0123-456789abcdef", "NITZ", 1790230000, 250000000, 100, 250000000};
    assert(valid_event(&e, id, 1790230010.25, 110.25));
    strcpy(e.source, "SNTP");
    assert(valid_event(&e, id, 1790230010.25, 110.25));
    assert(!valid_event(&e, "different-boot", 1790230010.25, 110.25));
    assert(!valid_event(&e, id, 1790230200.25, 300.25));
    assert(!valid_event(&e, id, 1790230000.25, 99.25));
    assert(!valid_event(&e, id, 1790230011.25, 110.25));
    assert(!valid_event(&e, id, 1790230009.25, 110.25));
    strcpy(e.source, "other");
    assert(!valid_event(&e, id, 1790230010.25, 110.25));
    strcpy(e.source, "NITZ");
    e.nsec = 1000000000;
    assert(!valid_event(&e, id, 1790230010.25, 110.25));
    e.nsec = 0; e.epoch = 0;
    assert(!valid_event(&e, id, 10, 110.25));
    puts("clock-event: fresh NITZ/SNTP accepted; stale, replayed, overwritten, manual and invalid events rejected");
    return 0;
}
