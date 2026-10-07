package keyboard

import "../bindings"
import "../errors"
import "../status"
import "core:mem"
import "core:strings"
import "vendor:x11/xlib"

Context :: struct {
	display: ^xlib.Display,
}

@(require_results)
init :: proc(ctx: ^Context) -> errors.Error {
	close(ctx)
	ctx.display = xlib.OpenDisplay(nil)
	if ctx.display == nil {
		return .Unavailable
	}
	return .None
}

close :: proc(ctx: ^Context) {
	if ctx.display != nil {
		xlib.CloseDisplay(ctx.display)
		ctx.display = nil
	}
}

label :: proc(name: string) -> string {
	if strings.has_prefix(name, "English") {
		return "EN"
	}
	if strings.has_prefix(name, "Russian") {
		return "RU"
	}
	return name
}

@(require_results)
block :: proc(ctx: ^Context, allocator: mem.Allocator) -> (status.Block, errors.Error) {
	fallback := status.Block {
		text = "?",
	}
	state: xlib.XkbStateRec
	if ctx.display == nil ||
	   xlib.XkbGetState(ctx.display, xlib.XkbUseCoreKbd, &state) != nil ||
	   state.group >= xlib.XkbNumKbdGroups {
		return fallback, .Unavailable
	}
	keyboard := xlib.XkbGetMap(ctx.display, {}, xlib.XkbUseCoreKbd)
	if keyboard == nil {
		return fallback, .Unavailable
	}
	defer bindings.XkbFreeKeyboard(keyboard, bindings.XKB_ALL_COMPONENTS, 1)
	if bindings.XkbGetNames(ctx.display, bindings.XKB_GROUP_NAMES, keyboard) != nil ||
	   keyboard.names == nil ||
	   keyboard.names.groups[state.group] == 0 {
		return fallback, .Unavailable
	}
	name := xlib.GetAtomName(ctx.display, keyboard.names.groups[state.group])
	if name == nil {
		return fallback, .Unavailable
	}
	defer xlib.Free(rawptr(name))
	text, err := strings.clone(label(string(name)), allocator)
	if err != nil {
		return fallback, .Out_Of_Memory
	}
	return {text = text}, .None
}
