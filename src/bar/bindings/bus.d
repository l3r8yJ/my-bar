module bar.bindings.bus;
@nogc nothrow extern (C):
int sd_bus_open_system(void** bus);
int sd_bus_set_method_call_timeout(void* bus, ulong timeout);
void* sd_bus_unref(void* bus);
void* sd_bus_flush_close_unref(void* bus);
int sd_bus_is_open(void* bus);
int sd_bus_get_property(void* bus, const(char)* service, const(char)* path, const(char)* iface,
		const(char)* member, void* error, void** reply, const(char)* signature);
int sd_bus_get_property_string(void* bus, const(char)* service, const(char)* path,
		const(char)* iface, const(char)* member, void* error, char** value);
int sd_bus_get_property_trivial(void* bus, const(char)* service, const(char)* path,
		const(char)* iface, const(char)* member, void* error, char type, void* value);
int sd_bus_message_enter_container(void* message, char type, const(char)* contents);
int sd_bus_message_read_basic(void* message, char type, void* value);
void* sd_bus_message_unref(void* message);
