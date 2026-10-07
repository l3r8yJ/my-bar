module bar::keyboard;
import bar::errors, bar::status;
import libc;
fn void labels_and_missing_display() @test {
	assert(label("English (US)") == "EN");
	assert(label("Russian") == "RU");
	assert(label("German") == "German");
	Context ctx;
	for (int i; i < 1000; i++) {
		if (catch err = block(&ctx)) {
			assert(err == errors::UNAVAILABLE);
		} else {
			assert(false);
		}
		close(&ctx);
	}
}
fn void active_xkb_group_and_cleanup() @test {
	if (!libc::getenv("MY_BAR_KEYBOARD_TEST")) return;
	Context ctx;
	init(&ctx)!!;
	defer close(&ctx);
	for (int i; i < 1000; i++) {
		@pool() {
			String[5] expected = { "EN", "RU", "German", "?", "?" };
			foreach (index, value : expected) {
				char[2] group = { (char)('0' + index), 0 };
				assert(libc::setenv("MY_BAR_KEYBOARD_GROUP", (ZString)&group, 1) == 0);
				if (index < 3) {
					assert(block(&ctx)!!.text == value);
				} else {
					if (catch err = block(&ctx)) {
						assert(err == errors::UNAVAILABLE);
					} else {
						assert(false);
					}
				}
			}
		};
	}
	assert(libc::setenv("MY_BAR_KEYBOARD_MISSING", "1", 1) == 0);
	defer libc::unsetenv("MY_BAR_KEYBOARD_MISSING");
	if (catch err = init(&ctx)) {
		assert(err == errors::UNAVAILABLE);
	} else {
		assert(false);
	}
	if (catch err = block(&ctx)) {
		assert(err == errors::UNAVAILABLE);
	} else {
		assert(false);
	}
	close(&ctx);
	close(&ctx);
}
