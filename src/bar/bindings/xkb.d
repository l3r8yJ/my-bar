module bar.bindings.xkb;
@nogc nothrow:
struct State {
	ubyte group, lockedGroup;
	ushort baseGroup, latchedGroup;
	ubyte mods, baseMods, latchedMods, lockedMods, compatState, grabMods, compatGrabMods,
		lookupMods, compatLookupMods;
	ushort ptrButtons;
}

struct Names {
	ulong keycodes, geometry, symbols, types, compat;
	ulong[16] vmods;
	ulong[32] indicators;
	ulong[4] groups;
	void* keys;
	void* keyAliases;
	void* radioGroups;
	ulong physSymbols;
	ubyte numKeys, numKeyAliases;
	ushort numRg;
}

struct Keyboard {
	void* display;
	ushort flags, deviceSpec;
	ubyte minKeyCode, maxKeyCode;
	void* controls;
	void* server;
	void* map;
	void* indicators;
	Names* names;
	void* compat;
	void* geometry;
}

extern (C) {
	pragma(mangle, "XOpenDisplay") void* openDisplay(const(char)* name);
	pragma(mangle, "XCloseDisplay") int closeDisplay(void* display);
	pragma(mangle, "XkbGetState") int getState(void* display, uint device, State* state);
	pragma(mangle, "XkbGetMap") Keyboard* getMap(void* display, uint which, uint device);
	pragma(mangle, "XkbGetNames") int getNames(void* display, uint which, Keyboard* keyboard);
	pragma(mangle, "XGetAtomName") char* getAtomName(void* display, ulong atom);
	pragma(mangle, "XkbFreeKeyboard") void freeKeyboard(Keyboard* keyboard, uint which, int all);
	pragma(mangle, "XFree") int freeX(void* data);
}
