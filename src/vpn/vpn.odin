package vpn

import bus "../bindings"
import "../errors"
import "../status"
import "core:c"
import "core:c/libc"
import "core:mem"
import "core:strings"
import "core:sys/posix"

Context :: struct {
	bus: ^bus.Bus,
}

SERVICE :: cstring("org.freedesktop.NetworkManager")
ACTIVE_INTERFACE :: cstring("org.freedesktop.NetworkManager.Connection.Active")
UNAVAILABLE :: status.Block {
	text  = "VPN: unavailable",
	color = "#888888",
}

@(require_results)
bus_error :: proc(result: c.int) -> errors.Error {
	if result == -posix.ENOMEM {
		return .Out_Of_Memory
	}
	return .Unavailable
}

@(require_results)
init :: proc(ctx: ^Context) -> errors.Error {
	close(ctx)
	if result := bus.open_system(&ctx.bus); result < 0 {
		ctx.bus = nil
		return bus_error(result)
	}
	if result := bus.set_method_call_timeout(ctx.bus, 100_000); result < 0 {
		ctx.bus = bus.unref(ctx.bus)
		return bus_error(result)
	}
	return .None
}

close :: proc(ctx: ^Context) {
	ctx.bus = bus.flush_close_unref(ctx.bus)
}

@(require_results)
connection_name :: proc(ctx: ^Context, path: cstring) -> (cstring, errors.Error) {
	type: cstring
	if result := bus.get_property_string(
		ctx.bus,
		SERVICE,
		path,
		ACTIVE_INTERFACE,
		"Type",
		nil,
		&type,
	); result < 0 {
		return nil, bus_error(result)
	}
	defer libc.free(rawptr(type))
	if type == nil {
		return nil, .Unavailable
	}
	kind := string(type)
	if kind != "vpn" && kind != "wireguard" && kind != "tun" {
		return nil, .None
	}
	state: u32
	if result := bus.get_property_trivial(
		ctx.bus,
		SERVICE,
		path,
		ACTIVE_INTERFACE,
		"State",
		nil,
		'u',
		&state,
	); result < 0 {
		return nil, bus_error(result)
	}
	if state != 2 {
		return nil, .None
	}
	name: cstring
	if result := bus.get_property_string(
		ctx.bus,
		SERVICE,
		path,
		ACTIVE_INTERFACE,
		"Id",
		nil,
		&name,
	); result < 0 {
		return nil, bus_error(result)
	}
	if name == nil {
		return nil, .Unavailable
	}
	return name, .None
}

@(require_results)
block :: proc(ctx: ^Context, allocator: mem.Allocator) -> (status.Block, errors.Error) {
	if ctx.bus == nil {
		if err := init(ctx); err != .None {
			return UNAVAILABLE, err
		}
	}
	defer {
		if bus.is_open(ctx.bus) <= 0 {
			ctx.bus = bus.unref(ctx.bus)
		}
	}
	connections: ^bus.Message
	if result := bus.get_property(
		ctx.bus,
		SERVICE,
		"/org/freedesktop/NetworkManager",
		SERVICE,
		"ActiveConnections",
		nil,
		&connections,
		"ao",
	); result < 0 {
		return UNAVAILABLE, bus_error(result)
	}
	defer bus.message_unref(connections)
	if result := bus.message_enter_container(connections, 'a', "o"); result < 0 {
		return UNAVAILABLE, bus_error(result)
	}
	text := make([dynamic]byte, allocator)
	defer delete(text)
	if _, err := append(&text, "VPN: "); err != nil {
		return UNAVAILABLE, .Out_Of_Memory
	}
	active := false
	for {
		path: cstring
		result := bus.message_read_basic(connections, 'o', &path)
		if result < 0 {
			return UNAVAILABLE, bus_error(result)
		}
		if result == 0 {
			break
		}
		name, err := connection_name(ctx, path)
		if err != .None {
			return UNAVAILABLE, err
		}
		if name == nil {
			continue
		}
		defer libc.free(rawptr(name))
		if active {
			if _, allocation_error := append(&text, ", "); allocation_error != nil {
				return UNAVAILABLE, .Out_Of_Memory
			}
		}
		if _, allocation_error := append(&text, string(name)); allocation_error != nil {
			return UNAVAILABLE, .Out_Of_Memory
		}
		active = true
	}
	color := "#00cc66"
	if !active {
		color = "#888888"
		if _, err := append(&text, "off"); err != nil {
			return UNAVAILABLE, .Out_Of_Memory
		}
	}
	value, err := strings.clone(string(text[:]), allocator)
	if err != nil {
		return UNAVAILABLE, .Out_Of_Memory
	}
	return {text = value, color = color}, .None
}
