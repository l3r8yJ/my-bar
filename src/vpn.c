#include "modules.h"
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <systemd/sd-bus.h>

static sd_bus *bus;
static const char service[] = "org.freedesktop.NetworkManager";
static const char active_interface[] = "org.freedesktop.NetworkManager.Connection.Active";

enum { CONNECTION_ACTIVATED = 2 };

void vpn_init(void)
{
    if (sd_bus_open_system(&bus) < 0)
        bus = NULL;
    if (bus && sd_bus_set_method_call_timeout(bus, 100000) < 0)
        bus = sd_bus_unref(bus);
}

static int append_connection(const char *path, FILE *text, int separator)
{
    char *type = NULL, *name = NULL;
    uint32_t state = 0;
    int result =
        sd_bus_get_property_string(bus, service, path, active_interface, "Type", NULL, &type);
    if (result >= 0 && strcmp(type, "vpn") != 0 && strcmp(type, "wireguard") != 0 &&
        strcmp(type, "tun") != 0) {
        result = 0;
        goto done;
    }
    if (result >= 0)
        result = sd_bus_get_property_trivial(bus, service, path, active_interface, "State", NULL,
                                             'u', &state);
    if (result >= 0 && state != CONNECTION_ACTIVATED) {
        result = 0;
        goto done;
    }
    if (result >= 0)
        result =
            sd_bus_get_property_string(bus, service, path, active_interface, "Id", NULL, &name);
    if (result >= 0)
        result = fprintf(text, "%s%s", separator ? ", " : "", name) < 0 ? -EIO : 1;
done:
    free(name);
    free(type);
    return result;
}

json_object *vpn_block(void)
{
    if (!bus)
        vpn_init();
    sd_bus_message *connections = NULL;
    char *text = NULL;
    size_t length = 0;
    FILE *stream = open_memstream(&text, &length);
    int result = -ENOTCONN, active = 0;
    if (bus && stream && fputs("VPN: ", stream) >= 0) {
        result = sd_bus_get_property(bus, service, "/org/freedesktop/NetworkManager", service,
                                     "ActiveConnections", NULL, &connections, "ao");
        if (result >= 0)
            result = sd_bus_message_enter_container(connections, 'a', "o");
        if (result > 0) {
            const char *path = NULL;
            while ((result = sd_bus_message_read(connections, "o", &path)) > 0) {
                result = append_connection(path, stream, active);
                if (result < 0)
                    break;
                active += result;
            }
        }
        if (result >= 0 && !active && fputs("off", stream) < 0)
            result = -EIO;
    }
    if (stream && fclose(stream) != 0)
        result = -EIO;
    sd_bus_message_unref(connections);
    json_object *block = json_object_new_object();
    json_object_object_add(block, "full_text",
                           json_object_new_string(result < 0 ? "VPN: unavailable" : text));
    json_object_object_add(block, "color",
                           json_object_new_string(result >= 0 && active ? "#00cc66" : "#888888"));
    free(text);
    if (bus && sd_bus_is_open(bus) <= 0)
        bus = sd_bus_unref(bus);
    return block;
}

void vpn_close(void) { bus = sd_bus_flush_close_unref(bus); }
