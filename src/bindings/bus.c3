module bar::bus;
extern fn int open_system(void** bus) @cname("sd_bus_open_system");
extern fn int set_method_call_timeout(void* bus, ulong timeout) @cname("sd_bus_set_method_call_timeout");
extern fn void* unref(void* bus) @cname("sd_bus_unref");
extern fn void* flush_close_unref(void* bus) @cname("sd_bus_flush_close_unref");
extern fn int is_open(void* bus) @cname("sd_bus_is_open");
extern fn int get_property(
	void* bus,
	ZString service,
	ZString path,
	ZString iface,
	ZString member,
	void* error,
	void** reply,
	ZString signature
) @cname("sd_bus_get_property");
extern fn int get_property_string(
	void* bus,
	ZString service,
	ZString path,
	ZString iface,
	ZString member,
	void* error,
	ZString* value
) @cname("sd_bus_get_property_string");
extern fn int get_property_trivial(
	void* bus,
	ZString service,
	ZString path,
	ZString iface,
	ZString member,
	void* error,
	char type,
	void* value
) @cname("sd_bus_get_property_trivial");
extern fn int message_enter_container(
	void* message,
	char type,
	ZString contents
) @cname("sd_bus_message_enter_container");
extern fn int message_read_basic(void* message, char type, void* value) @cname("sd_bus_message_read_basic");
extern fn void* message_unref(void* message) @cname("sd_bus_message_unref");
