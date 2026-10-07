package fixture

import "core:c"
import "core:c/libc"
Display :: struct {}
State :: struct {
	group: u8,
}
Keyboard :: struct {
	display:                            rawptr,
	flags, device_spec:                 u16,
	min_key_code, max_key_code:         u8,
	ctrls, server, key_map, indicators: rawptr,
	names:                              ^Names,
}
Names :: struct {
	keycodes, geometry, symbols, types, compat: c.ulong,
	vmods:                                      [16]c.ulong,
	indicators:                                 [32]c.ulong,
	groups:                                     [4]c.ulong,
}

connection: c.int
allocations: c.int

@(export)
XOpenDisplay :: proc "c" (_: cstring) -> ^Display {
	missing := libc.getenv("MY_BAR_KEYBOARD_MISSING")
	if missing != nil {
		return nil
	}
	return cast(^Display)&connection
}

@(export)
XCloseDisplay :: proc "c" (_: ^Display) -> c.int {
	if allocations != 0 {
		libc.abort()
	}
	return 0
}

@(export)
XkbGetState :: proc "c" (_: ^Display, _: c.uint, state: ^State) -> c.int {
	value := libc.getenv("MY_BAR_KEYBOARD_GROUP")
	state.group = 0
	if value != nil {
		state.group = (cast([^]u8)value)[0] - '0'
	}
	return 0
}

@(export)
XkbGetMap :: proc "c" (_: ^Display, _: c.uint, _: c.uint) -> ^Keyboard {
	keyboard := cast(^Keyboard)libc.calloc(1, size_of(Keyboard))
	if keyboard != nil {
		allocations += 1
	}
	return keyboard
}

@(export)
XkbGetNames :: proc "c" (_: ^Display, _: c.uint, keyboard: ^Keyboard) -> c.int {
	keyboard.names = cast(^Names)libc.calloc(1, size_of(Names))
	if keyboard.names == nil {
		return 1
	}
	allocations += 1
	keyboard.names.groups = {1, 2, 3, 0}
	return 0
}

@(export)
XGetAtomName :: proc "c" (_: ^Display, atom: c.ulong) -> cstring {
	names := [4]string{"", "English (US)", "Russian", "German"}
	if atom >= 4 {
		return nil
	}
	name := names[atom]
	data := cast([^]byte)libc.malloc(uint(len(name) + 1))
	if data == nil {
		return nil
	}
	for index in 0 ..< len(name) {
		data[index] = name[index]
	}
	allocations += 1
	data[len(name)] = 0
	return cast(cstring)data
}

@(export)
XkbFreeKeyboard :: proc "c" (keyboard: ^Keyboard, _: c.uint, _: c.int) {
	if keyboard.names != nil {
		allocations -= 1
	}
	allocations -= 1
	libc.free(keyboard.names)
	libc.free(keyboard)
}

@(export)
XFree :: proc "c" (data: rawptr) -> c.int {
	allocations -= 1
	libc.free(data)
	return 0
}
