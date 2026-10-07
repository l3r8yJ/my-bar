#+test
package keyboard

import "core:os"
import "core:testing"

@(test)
labels_and_missing_display :: proc(t: ^testing.T) {
	testing.expect_value(t, label("English (US)"), "EN")
	testing.expect_value(t, label("Russian"), "RU")
	testing.expect_value(t, label("German"), "German")
	ctx: Context
	for _ in 0 ..< 1000 {
		value, err := block(&ctx, context.allocator)
		testing.expect_value(t, value.text, "?")
		testing.expect_value(t, err, .Unavailable)
		close(&ctx)
	}
}

@(test)
active_xkb_group_and_cleanup :: proc(t: ^testing.T) {
	mode, enabled := os.lookup_env("MY_BAR_KEYBOARD_TEST", context.allocator)
	defer delete(mode)
	if !enabled {
		return
	}
	ctx: Context
	testing.expect_value(t, init(&ctx), .None)
	defer close(&ctx)
	for _ in 0 ..< 1000 {
		for expected, group in ([5]string{"EN", "RU", "German", "?", "?"}) {
			group_name := [1]byte{u8('0' + group)}
			testing.expect_value(
				t,
				os.set_env("MY_BAR_KEYBOARD_GROUP", string(group_name[:])),
				nil,
			)
			value, err := block(&ctx, context.allocator)
			testing.expect_value(t, value.text, expected)
			if group < 3 {
				testing.expect_value(t, err, .None)
				delete(value.text)
			} else {
				testing.expect_value(t, err, .Unavailable)
			}
		}
	}
	testing.expect_value(t, os.set_env("MY_BAR_KEYBOARD_MISSING", "1"), nil)
	testing.expect_value(t, init(&ctx), .Unavailable)
	value, err := block(&ctx, context.allocator)
	testing.expect_value(t, value.text, "?")
	testing.expect_value(t, err, .Unavailable)
	testing.expect_value(t, os.unset_env("MY_BAR_KEYBOARD_MISSING"), true)
}
