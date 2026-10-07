#include "modules.h"
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/statvfs.h>

unsigned long long metrics_memory_value(const char *line, const char *key)
{
    size_t length = strlen(key);
    if (strncmp(line, key, length) != 0)
        return ULLONG_MAX;
    const char *value = line + length;
    while (isspace((unsigned char)*value))
        ++value;
    if (!isdigit((unsigned char)*value))
        return ULLONG_MAX;
    errno = 0;
    char *end = NULL;
    unsigned long long number = strtoull(value, &end, 10);
    if (errno || strcmp(end, " kB\n") != 0)
        return ULLONG_MAX;
    return number;
}

json_object *metrics_block(void)
{
    const double gib = 1024.0 * 1024.0 * 1024.0;
    char disk[96] = "SSD: ?", ram[96] = "RAM: ?", text[200];
    struct statvfs fs;
    if (statvfs("/", &fs) == 0)
        (void)snprintf(disk, sizeof(disk), "SSD: %.1f/%.1f GiB",
                       (double)(fs.f_blocks - fs.f_bfree) * (double)fs.f_frsize / gib,
                       (double)fs.f_blocks * (double)fs.f_frsize / gib);
    FILE *file = fopen("/proc/meminfo", "r");
    if (file) {
        char line[256];
        unsigned long long total = ULLONG_MAX, available = ULLONG_MAX;
        while (fgets(line, sizeof(line), file)) {
            unsigned long long value = metrics_memory_value(line, "MemTotal:");
            if (value != ULLONG_MAX)
                total = value;
            value = metrics_memory_value(line, "MemAvailable:");
            if (value != ULLONG_MAX)
                available = value;
        }
        int failed = ferror(file);
        if (fclose(file) != 0)
            failed = 1;
        if (!failed && total != ULLONG_MAX && available <= total && total)
            (void)snprintf(ram, sizeof(ram), "RAM: %.1f/%.1f GiB",
                           (double)(total - available) * 1024 / gib, (double)total * 1024 / gib);
    }
    (void)snprintf(text, sizeof(text), "%s | %s", disk, ram);
    json_object *block = json_object_new_object();
    json_object_object_add(block, "full_text", json_object_new_string(text));
    return block;
}
