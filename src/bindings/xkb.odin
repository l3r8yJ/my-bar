package bindings

import "core:c"
import "vendor:x11/xlib"

XKB_ALL_COMPONENTS :: 0x7f
XKB_GROUP_NAMES :: 1 << 12

foreign import x11 "system:X11"
foreign x11 {
	XkbGetNames :: proc(display: ^xlib.Display, which: c.uint, keyboard: xlib.XkbDescPtr) -> xlib.Status ---
	XkbFreeKeyboard :: proc(keyboard: xlib.XkbDescPtr, which: c.uint, all: c.int) ---
}
