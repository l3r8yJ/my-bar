package main

import "base:intrinsics"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:sys/posix"

foreign import systemd "system:systemd"
Bus :: struct {}
Message :: struct {}
Slot :: struct {}
foreign systemd {
	sd_bus_open_user :: proc(bus: ^^Bus) -> c.int ---
	sd_bus_unref :: proc(bus: ^Bus) -> ^Bus ---
	sd_bus_slot_unref :: proc(slot: ^Slot) -> ^Slot ---
	sd_bus_add_filter :: proc(bus: ^Bus, slot: ^^Slot, callback: proc "c" (_: ^Message, _: rawptr, _: rawptr) -> c.int, userdata: rawptr) -> c.int ---
	sd_bus_request_name :: proc(bus: ^Bus, name: cstring, flags: u64) -> c.int ---
	sd_bus_process :: proc(bus: ^Bus, message: ^^Message) -> c.int ---
	sd_bus_wait :: proc(bus: ^Bus, timeout: u64) -> c.int ---
	sd_bus_message_is_method_call :: proc(message: ^Message, interface: cstring, member: cstring) -> c.int ---
	sd_bus_message_get_path :: proc(message: ^Message) -> cstring ---
	sd_bus_message_read :: proc(message: ^Message, signature: cstring, #c_vararg args: ..any) -> c.int ---
	sd_bus_message_new_method_return :: proc(call: ^Message, reply: ^^Message) -> c.int ---
	sd_bus_message_unref :: proc(message: ^Message) -> ^Message ---
	sd_bus_message_open_container :: proc(message: ^Message, kind: c.char, signature: cstring) -> c.int ---
	sd_bus_message_close_container :: proc(message: ^Message) -> c.int ---
	sd_bus_message_append :: proc(message: ^Message, signature: cstring, #c_vararg args: ..any) -> c.int ---
	sd_bus_send :: proc(bus: ^Bus, message: ^Message, cookie: ^u64) -> c.int ---
	sd_bus_reply_method_errorf :: proc(message: ^Message, name: cstring, format: cstring, #c_vararg args: ..any) -> c.int ---
}

Fixture :: struct {
	path:  cstring,
	kind:  cstring,
	name:  cstring,
	state: u32,
}
fixtures := [?]Fixture {
	{"/active/one", "vpn", "office \"quoted\"", 2},
	{"/active/two", "wireguard", "wg", 2},
	{"/active/three", "tun", "tun", 2},
	{"/active/four", "802-3-ethernet", "ethernet", 2},
	{"/active/five", "vpn", "connecting", 1},
	{"/active/six", "wireguard", "disconnected", 4},
}
mode: u8
stopping: c.int
long_name: [8192]u8

stop :: proc "c" (_: posix.Signal) {
	intrinsics.atomic_store(&stopping, 1)
}

reply_property :: proc(message: ^Message, reply: ^Message, property: string) -> c.int {
	if property == "ActiveConnections" {
		if sd_bus_message_open_container(reply, 'v', "ao") < 0 ||
		   sd_bus_message_open_container(reply, 'a', "o") < 0 {
			return -1
		}
		if mode != '1' {
			for fixture in fixtures {
				if sd_bus_message_append(reply, "o", fixture.path) < 0 {
					return -1
				}
				if mode == '3' {
					break
				}
			}
		}
		if sd_bus_message_close_container(reply) < 0 {
			return -1
		}
		return sd_bus_message_close_container(reply)
	}
	path := string(sd_bus_message_get_path(message))
	for fixture in fixtures {
		if path != string(fixture.path) {
			continue
		}
		switch property {
		case "Type":
			return sd_bus_message_append(reply, "v", cstring("s"), fixture.kind)
		case "State":
			return sd_bus_message_append(reply, "v", cstring("u"), fixture.state)
		case "Id":
			name := fixture.name
			if mode == '3' {
				name = cstring(raw_data(long_name[:]))
			}
			return sd_bus_message_append(reply, "v", cstring("s"), name)
		}
	}
	return -2
}

property_call :: proc "c" (message: ^Message, _: rawptr, _: rawptr) -> c.int {
	context = runtime.default_context()
	if sd_bus_message_is_method_call(message, "org.freedesktop.DBus.Properties", "Get") <= 0 {
		return 0
	}
	interface, property: cstring
	if sd_bus_message_read(message, "ss", &interface, &property) < 0 {
		return -1
	}
	if mode == '2' && string(property) != "ActiveConnections" {
		return sd_bus_reply_method_errorf(
			message,
			"org.freedesktop.DBus.Error.UnknownProperty",
			"missing fixture property",
		)
	}
	if mode == '4' && string(property) != "ActiveConnections" {
		return 1
	}
	reply: ^Message
	if sd_bus_message_new_method_return(message, &reply) < 0 {
		return -1
	}
	defer sd_bus_message_unref(reply)
	result := reply_property(message, reply, string(property))
	if result < 0 {
		return result
	}
	return sd_bus_send(nil, reply, nil)
}

run :: proc() -> int {
	if len(os.args) != 2 || len(os.args[1]) != 1 || os.args[1][0] < '0' || os.args[1][0] > '4' {
		return 2
	}
	mode = os.args[1][0]
	for &value in long_name[:len(long_name) - 1] {
		value = 'x'
	}
	action: posix.sigaction_t
	action.sa_handler = stop
	if posix.sigemptyset(&action.sa_mask) != 0 ||
	   posix.sigaction(.SIGTERM, &action, nil) != nil ||
	   posix.sigaction(.SIGINT, &action, nil) != nil {
		return 1
	}
	bus: ^Bus
	if sd_bus_open_user(&bus) < 0 {
		return 1
	}
	defer sd_bus_unref(bus)
	slot: ^Slot
	if sd_bus_add_filter(bus, &slot, property_call, nil) < 0 {
		return 1
	}
	defer sd_bus_slot_unref(slot)
	if sd_bus_request_name(bus, "org.freedesktop.NetworkManager", 0) < 0 {
		return 1
	}
	fmt.println("ready")
	for intrinsics.atomic_load(&stopping) == 0 {
		result := sd_bus_process(bus, nil)
		if result < 0 && result != -4 {
			return 1
		}
		if result == 0 {
			wait_result := sd_bus_wait(bus, 100000)
			if wait_result < 0 && wait_result != -4 {
				return 1
			}
		}
	}
	return 0
}

main :: proc() {
	os.exit(run())
}
