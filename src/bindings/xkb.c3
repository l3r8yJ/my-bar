module bar::xkb;
struct State {
	char group;
	char locked_group;
	ushort base_group;
	ushort latched_group;
	char mods;
	char base_mods;
	char latched_mods;
	char locked_mods;
	char compat_state;
	char grab_mods;
	char compat_grab_mods;
	char lookup_mods;
	char compat_lookup_mods;
	ushort ptr_buttons;
}
struct Names {
	ulong keycodes;
	ulong geometry;
	ulong symbols;
	ulong types;
	ulong compat;
	ulong[16] vmods;
	ulong[32] indicators;
	ulong[4] groups;
	void* keys;
	void* key_aliases;
	void* radio_groups;
	ulong phys_symbols;
	char num_keys;
	char num_key_aliases;
	ushort num_rg;
}
struct Keyboard {
	void* display;
	ushort flags;
	ushort device_spec;
	char min_key_code;
	char max_key_code;
	void* controls;
	void* server;
	void* map;
	void* indicators;
	Names* names;
	void* compat;
	void* geometry;
}
extern fn void* open_display(ZString name) @cname("XOpenDisplay");
extern fn int close_display(void* display) @cname("XCloseDisplay");
extern fn int get_state(void* display, uint device, State* state) @cname("XkbGetState");
extern fn Keyboard* get_map(void* display, uint which, uint device) @cname("XkbGetMap");
extern fn int get_names(void* display, uint which, Keyboard* keyboard) @cname("XkbGetNames");
extern fn ZString atom_name(void* display, ulong atom) @cname("XGetAtomName");
extern fn void free_keyboard(Keyboard* keyboard, uint which, int all) @cname("XkbFreeKeyboard");
extern fn int free(void* data) @cname("XFree");
