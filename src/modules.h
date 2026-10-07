#ifndef MY_BAR_MODULES_H
#define MY_BAR_MODULES_H

#include <json-c/json.h>

void keyboard_init(void);
json_object *keyboard_block(void);
void keyboard_close(void);
void vpn_init(void);
json_object *vpn_block(void);
void vpn_close(void);
json_object *metrics_block(void);
unsigned long long metrics_memory_value(const char *line, const char *key);

#endif
