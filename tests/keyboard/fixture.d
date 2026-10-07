module tests.keyboard.fixture;
import bar.bindings.xkb : State, Keyboard, Names;
import core.stdc.stdlib : calloc, malloc, free, abort, getenv;
import core.stdc.string : memcpy;

@nogc nothrow:
private __gshared int connection, allocations;
extern (C) export {
	pragma(mangle, "XOpenDisplay") void* openDisplay(const(char)*) {
		return getenv("MY_BAR_KEYBOARD_MISSING") is null ? &connection : null;
	}

	pragma(mangle, "XCloseDisplay") int closeDisplay(void*) {
		if (allocations)
			abort();
		return 0;
	}

	pragma(mangle, "XkbGetState") int getState(void*, uint, State* state) {
		auto value = getenv("MY_BAR_KEYBOARD_GROUP");
		state.group = cast(ubyte)(value is null ? 0 : value[0] - '0');
		return 0;
	}

	pragma(mangle, "XkbGetMap") Keyboard* getMap(void*, uint, uint) {
		auto keyboard = cast(Keyboard*) calloc(1, Keyboard.sizeof);
		if (keyboard !is null)
			allocations++;
		return keyboard;
	}

	pragma(mangle, "XkbGetNames") int getNames(void*, uint, Keyboard* keyboard) {
		keyboard.names = cast(Names*) calloc(1, Names.sizeof);
		if (keyboard.names is null)
			return 1;
		allocations++;
		keyboard.names.groups = [1, 2, 3, 0];
		return 0;
	}

	pragma(mangle, "XGetAtomName") char* getAtomName(void*, ulong atom) {
		const(char)[][4] names = ["", "English (US)", "Russian", "German"];
		if (atom >= names.length)
			return null;
		auto name = names[atom];
		auto value = cast(char*) malloc(name.length + 1);
		if (value is null)
			return null;
		allocations++;
		memcpy(value, name.ptr, name.length);
		value[name.length] = '\0';
		return value;
	}

	pragma(mangle, "XkbFreeKeyboard") void freeKeyboard(Keyboard* keyboard, uint, int) {
		if (keyboard.names !is null)
			allocations--;
		allocations--;
		free(keyboard.names);
		free(keyboard);
	}

	pragma(mangle, "XFree") int freeX(void* data) {
		if (data !is null)
			allocations--;
		free(data);
		return 0;
	}
}
