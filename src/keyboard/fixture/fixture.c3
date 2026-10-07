module bar::fixture;
import libc, bar::xkb;
int connection;
int allocations;
fn void* open_display(ZString name) @export @cname("XOpenDisplay")
{
	(void)name;
	if (libc::getenv("MY_BAR_KEYBOARD_MISSING")) return null;
	return &connection;
}
fn int close_display(void* display) @export @cname("XCloseDisplay")
{
	(void)display;
	if (allocations != 0) libc::abort();
	return 0;
}
fn int get_state(void* display, uint device, State* state) @export @cname("XkbGetState")
{
	(void)display;
	(void)device;
	ZString value = libc::getenv("MY_BAR_KEYBOARD_GROUP");
	state.group = value ? value[0] - '0' : 0;
	return 0;
}
fn Keyboard* get_map(void* display, uint which, uint device) @export @cname("XkbGetMap")
{
	(void)display;
	(void)which;
	(void)device;
	Keyboard* keyboard = libc::calloc(1, Keyboard::size);
	if (keyboard) allocations++;
	return keyboard;
}
fn int get_names(void* display, uint which, Keyboard* keyboard) @export @cname("XkbGetNames")
{
	(void)display;
	(void)which;
	keyboard.names = libc::calloc(1, Names::size);
	if (!keyboard.names) return 1;
	allocations++;
	keyboard.names.groups = { 1, 2, 3, 0 };
	return 0;
}
fn ZString atom_name(void* display, ulong atom) @export @cname("XGetAtomName")
{
	(void)display;
	String[4] names = { "", "English (US)", "Russian", "German" };
	if (atom >= names.len) return null;
	String name  = names[atom];
	char* buffer = libc::malloc(name.len + 1);
	if (!buffer) return null;
	allocations++;
	for (usz i; i < name.len; i++) buffer[i] = name[i];
	buffer[name.len] = 0;
	return (ZString)buffer;
}
fn void free_keyboard(Keyboard* keyboard, uint which, int all) @export @cname("XkbFreeKeyboard")
{
	(void)which;
	(void)all;
	if (keyboard.names) allocations--;
	allocations--;
	libc::free(keyboard.names);
	libc::free(keyboard);
}
fn int free(void* data) @export @cname("XFree")
{
	if (data) allocations--;
	libc::free(data);
	return 0;
}