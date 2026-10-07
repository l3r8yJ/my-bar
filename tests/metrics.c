#include "../src/modules.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>

int main(void)
{
    assert(metrics_memory_value("MemTotal:   12345 kB\n", "MemTotal:") == 12345);
    assert(metrics_memory_value("MemAvailable: 0 kB\n", "MemAvailable:") == 0);
    assert(metrics_memory_value("MemTotal: -1 kB\n", "MemTotal:") == ULLONG_MAX);
    assert(metrics_memory_value("MemTotal: nope kB\n", "MemTotal:") == ULLONG_MAX);
    assert(metrics_memory_value("MemTotal: 123 GB\n", "MemTotal:") == ULLONG_MAX);
    assert(metrics_memory_value("MemTotal: 9999999999999999999999 kB\n", "MemTotal:") ==
           ULLONG_MAX);
    assert(metrics_memory_value("MemAvailable: 1 kB\n", "MemTotal:") == ULLONG_MAX);
    (void)puts("PASS: memory parsing, zero available, malformed units, negative values, overflow");
    return 0;
}
