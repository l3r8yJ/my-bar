package bindings

import "core:c"

Bus :: struct {}
Message :: struct {}

@(extra_linker_flags = "-Wl,--as-needed")
foreign import systemd "system:systemd"
@(default_calling_convention = "c", link_prefix = "sd_bus_")
foreign systemd {
	open_system :: proc(bus: ^^Bus) -> c.int ---
	set_method_call_timeout :: proc(bus: ^Bus, timeout: u64) -> c.int ---
	unref :: proc(bus: ^Bus) -> ^Bus ---
	flush_close_unref :: proc(bus: ^Bus) -> ^Bus ---
	is_open :: proc(bus: ^Bus) -> c.int ---
	get_property :: proc(bus: ^Bus, service, path, interface, member: cstring, error: rawptr, reply: ^^Message, signature: cstring) -> c.int ---
	get_property_string :: proc(bus: ^Bus, service, path, interface, member: cstring, error: rawptr, value: ^cstring) -> c.int ---
	get_property_trivial :: proc(bus: ^Bus, service, path, interface, member: cstring, error: rawptr, type: u8, value: rawptr) -> c.int ---
	message_enter_container :: proc(message: ^Message, type: u8, contents: cstring) -> c.int ---
	message_read_basic :: proc(message: ^Message, type: u8, value: rawptr) -> c.int ---
	message_unref :: proc(message: ^Message) -> ^Message ---
}
