module bar.keyboard;
import bar.bindings.xkb;
import bar.errors : Error, Result;
import bar.status;
import core.stdc.stdlib : malloc, getenv;
import core.sys.posix.stdlib : setenv, unsetenv;
import core.stdc.string : strlen, memcpy;

@nogc nothrow:
struct Context {
	void* display;
}

Error init(ref Context ctx) {
	close(ctx);
	ctx.display = openDisplay(null);
	return ctx.display is null ? Error.unavailable : Error.none;
}

void close(ref Context ctx) {
	if (ctx.display is null)
		return;
	cast(void) closeDisplay(ctx.display);
	ctx.display = null;
}

private const(char)[] label(const(char)[] name) {
	if (name.length >= 7 && name[0 .. 7] == "English")
		return "EN";
	if (name.length >= 7 && name[0 .. 7] == "Russian")
		return "RU";
	return name;
}

Result!Block block(ref Context ctx) {
	State state;
	if (ctx.display is null || getState(ctx.display, 256, &state) != 0 || state.group >= 4)
		return Result!Block(Block.init, Error.unavailable);
	auto keyboard = getMap(ctx.display, 0, 256);
	if (keyboard is null)
		return Result!Block(Block.init, Error.unavailable);
	scope (exit)
		freeKeyboard(keyboard, 0x7f, 1);
	if (getNames(ctx.display, 1 << 12, keyboard) != 0 || keyboard.names is null
			|| keyboard.names.groups[state.group] == 0)
		return Result!Block(Block.init, Error.unavailable);
	auto name = getAtomName(ctx.display, keyboard.names.groups[state.group]);
	if (name is null)
		return Result!Block(Block.init, Error.unavailable);
	scope (exit)
		cast(void) freeX(name);
	auto text = label(name[0 .. strlen(name)]);
	auto owned = cast(char*) malloc(text.length ? text.length : 1);
	if (owned is null)
		return Result!Block(Block.init, Error.outOfMemory);
	memcpy(owned, text.ptr, text.length);
	return Result!Block(Block(owned[0 .. text.length], null, owned), Error.none);
}

unittest {
	assert(label("English (US)") == "EN");
	assert(label("Russian") == "RU");
	assert(label("German") == "German");
	Context ctx;
	foreach (_; 0 .. 1000)
		assert(block(ctx).error == Error.unavailable);
	close(ctx);
	if (getenv("MY_BAR_KEYBOARD_TEST") !is null) {
		assert(init(ctx) == Error.none);
		foreach (_; 0 .. 1000) {
			foreach (group; 0 .. 5) {
				char[2] value = [cast(char)('0' + group), '\0'];
				assert(setenv("MY_BAR_KEYBOARD_GROUP", value.ptr, 1) == 0);
				auto result = block(ctx);
				if (group < 3) {
					assert(result.error == Error.none);
					const(char)[][3] names = ["EN", "RU", "German"];
					assert(result.value.text == names[group]);
					bar.status.close(result.value);
				} else
					assert(result.error == Error.unavailable);
			}
		}
		close(ctx);
		close(ctx);
		assert(setenv("MY_BAR_KEYBOARD_MISSING", "1", 1) == 0);
		assert(init(ctx) == Error.unavailable);
		assert(unsetenv("MY_BAR_KEYBOARD_MISSING") == 0);
	}
}
