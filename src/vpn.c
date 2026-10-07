#include "modules.h"
#include <NetworkManager.h>
#include <string.h>

static NMClient *client;

void vpn_init(void)
{
    GError *error = NULL;
    client = nm_client_new(NULL, &error);
    if (error) {
        g_printerr("my-bar: NetworkManager: %s\n", error->message);
        g_error_free(error);
    }
}

json_object *vpn_block(void)
{
    while (g_main_context_pending(NULL))
        g_main_context_iteration(NULL, FALSE);
    GString *text = g_string_new("VPN: ");
    const GPtrArray *connections = client ? nm_client_get_active_connections(client) : NULL;
    unsigned active = 0;
    for (guint i = 0; connections && i < connections->len; ++i) {
        NMActiveConnection *connection = g_ptr_array_index(connections, i);
        const char *type = nm_active_connection_get_connection_type(connection);
        if (type &&
            (strcmp(type, "vpn") == 0 || strcmp(type, "wireguard") == 0 ||
             strcmp(type, "tun") == 0) &&
            nm_active_connection_get_state(connection) == NM_ACTIVE_CONNECTION_STATE_ACTIVATED) {
            if (active++)
                g_string_append(text, ", ");
            g_string_append(text, nm_active_connection_get_id(connection));
        }
    }
    if (!active)
        g_string_append(text, client && nm_client_get_nm_running(client) ? "off" : "unavailable");
    json_object *block = json_object_new_object();
    json_object_object_add(block, "full_text", json_object_new_string(text->str));
    json_object_object_add(block, "color", json_object_new_string(active ? "#00cc66" : "#888888"));
    g_string_free(text, TRUE);
    return block;
}

void vpn_close(void) { g_clear_object(&client); }
