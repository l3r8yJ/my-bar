module bar::vpn;
import bar::bus, bar::errors, bar::status;
import libc;
import std::core::dstring;
struct Context {
	void* bus;
}
const ZString SERVICE          = "org.freedesktop.NetworkManager";
const ZString ACTIVE_INTERFACE = "org.freedesktop.NetworkManager.Connection.Active";
fn void? check(int result) {
	if (result == -12) return errors::OUT_OF_MEMORY~;
	if (result < 0) return errors::UNAVAILABLE~;
}
fn void? init(Context* ctx) {
	close(ctx);
	check(bus::open_system(&ctx.bus))!;
	defer catch close(ctx);
	check(bus::set_method_call_timeout(ctx.bus, 100_000))!;
}
fn void close(Context* ctx) {
	ctx.bus = bus::flush_close_unref(ctx.bus);
}
fn ZString? connection_name(Context* ctx, ZString path) {
	ZString type;
	check(bus::get_property_string(ctx.bus, SERVICE, path, ACTIVE_INTERFACE, "Type", null, &type))!;
	defer libc::free(type);
	if (!type) return errors::UNAVAILABLE~;
	String kind = type.str_view();
	if (kind != "vpn" && kind != "wireguard" && kind != "tun") return null;
	uint state;
	check(bus::get_property_trivial(ctx.bus, SERVICE, path, ACTIVE_INTERFACE, "State", null, 'u', &state))!;
	if (state != 2) return null;
	ZString name;
	check(bus::get_property_string(ctx.bus, SERVICE, path, ACTIVE_INTERFACE, "Id", null, &name))!;
	if (!name) return errors::UNAVAILABLE~;
	return name;
}
fn Block? block(Context* ctx) {
	if (!ctx.bus) init(ctx)!;
	defer {
		if (bus::is_open(ctx.bus) <= 0) ctx.bus = bus::unref(ctx.bus);
	}
	void* connections;
	check(
		bus::get_property(
			ctx.bus,
			SERVICE,
			"/org/freedesktop/NetworkManager",
			SERVICE,
			"ActiveConnections",
			null,
			&connections,
			"ao"
		)
	)!;
	defer bus::message_unref(connections);
	check(bus::message_enter_container(connections, 'a', "o"))!;
	DString text;
	text.append_string("VPN: ");
	bool active;
	while (true) {
		ZString path;
		int result = bus::message_read_basic(connections, 'o', &path);
		if (!result) break;
		check(result)!;
		ZString name = connection_name(ctx, path)!;
		if (!name) continue;
		defer libc::free(name);
		if (active) text.append_string(", ");
		text.append_string(name.str_view());
		active = true;
	}
	if (!active) return { .text = "VPN: off", .color = "#888888" };
	return { .text = text.str_view(), .color = "#00cc66" };
}
