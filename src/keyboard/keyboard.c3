module bar::keyboard;
import bar::xkb, bar::errors, bar::status;
struct Context {
	void* display;
}
fn void? init(Context* ctx) {
	close(ctx);
	ctx.display = xkb::open_display(null);
	if (!ctx.display) return errors::UNAVAILABLE~;
}
fn void close(Context* ctx) {
	if (!ctx.display) return;
	xkb::close_display(ctx.display);
	ctx.display = null;
}
fn String label(String name) {
	if (name.starts_with("English")) return "EN";
	if (name.starts_with("Russian")) return "RU";
	return name;
}
fn Block? block(Context* ctx) {
	State state;
	if (!ctx.display || xkb::get_state(ctx.display, 256, &state) != 0 || state.group >= 4) return errors::UNAVAILABLE~;
	Keyboard* keyboard = xkb::get_map(ctx.display, 0, 256);
	if (!keyboard) return errors::UNAVAILABLE~;
	defer xkb::free_keyboard(keyboard, 0x7f, 1);
	if (xkb::get_names(
		ctx.display,
		1 << 12,
		keyboard
	) != 0 || !keyboard.names || !keyboard.names.groups[state.group]) return errors::UNAVAILABLE~;
	ZString name = xkb::atom_name(ctx.display, keyboard.names.groups[state.group]);
	if (!name) return errors::UNAVAILABLE~;
	defer xkb::free(name);
	return { .text = label(name.str_view()).tcopy() };
}
