module vpn_fixture;

import std::io;
import std::core::mem;
import libc;

struct Bus {
	char unused;
}
struct Message {
	char unused;
}
struct Slot {
	char unused;
}
alias Callback = fn CInt(Message*, void*, void*);
extern fn CInt sd_bus_open_user(Bus** bus);
extern fn Bus* sd_bus_unref(Bus* bus);
extern fn Slot* sd_bus_slot_unref(Slot* slot);
extern fn CInt sd_bus_add_filter(Bus* bus, Slot** slot, Callback callback, void* userdata);
extern fn CInt sd_bus_request_name(Bus* bus, ZString name, ulong flags);
extern fn CInt sd_bus_process(Bus* bus, Message** message);
extern fn CInt sd_bus_wait(Bus* bus, ulong timeout);
extern fn CInt sd_bus_message_is_method_call(Message* message, ZString interface_name, ZString member);
extern fn ZString sd_bus_message_get_path(Message* message);
extern fn CInt sd_bus_message_read(Message* message, ZString signature, ...);
extern fn CInt sd_bus_message_new_method_return(Message* call, Message** reply);
extern fn Message* sd_bus_message_unref(Message* message);
extern fn CInt sd_bus_message_open_container(Message* message, CChar kind, ZString signature);
extern fn CInt sd_bus_message_close_container(Message* message);
extern fn CInt sd_bus_message_append(Message* message, ZString signature, ...);
extern fn CInt sd_bus_send(Bus* bus, Message* message, ulong* cookie);
extern fn CInt sd_bus_reply_method_errorf(Message* call, ZString name, ZString format, ...);

struct Fixture {
	ZString path;
	ZString name;
	ZString kind;
	uint state;
}
Fixture[6] fixtures = {
	{ "/active/one", "office \"quoted\"", "vpn", 2 },
	{ "/active/two", "wg", "wireguard", 2 },
	{ "/active/three", "tun", "tun", 2 },
	{ "/active/four", "ethernet", "802-3-ethernet", 2 },
	{ "/active/five", "connecting", "vpn", 1 },
	{ "/active/six", "disconnected", "vpn", 4 },
};
char mode;
CInt stopping;
char[8192] long_name;

fn void stop(CInt signal) {
	mem::@volatile_store(stopping, 1);
}

fn CInt reply_property(Message* message, Message* reply, String property) {
	if (property == "ActiveConnections") {
		if (sd_bus_message_open_container(
			reply,
			'v',
			"ao"
		) < 0 || sd_bus_message_open_container(reply, 'a', "o") < 0) return -1;
		if (mode != '1') {
			foreach (fixture : fixtures) {
				if (sd_bus_message_append(reply, "o", fixture.path) < 0) return -1;
				if (mode == '3') break;
			}
		}
		if (sd_bus_message_close_container(reply) < 0) return -1;
		return sd_bus_message_close_container(reply);
	}
	String path = sd_bus_message_get_path(message).str_view();
	foreach (fixture : fixtures) {
		if (path != fixture.path.str_view()) continue;
		switch (property) {
			case "Type": return sd_bus_message_append(reply, "v", (ZString)"s", fixture.kind);
			case "State": return sd_bus_message_append(reply, "v", (ZString)"u", fixture.state);
			case "Id":
				ZString name = mode == '3' ? (ZString)&long_name : fixture.name;
				return sd_bus_message_append(reply, "v", (ZString)"s", name);
		}
	}
	return -2;
}

fn CInt property_call(Message* message, void* userdata, void* error) {
	if (sd_bus_message_is_method_call(message, "org.freedesktop.DBus.Properties", "Get") <= 0) return 0;
	ZString interface_name, property;
	if (sd_bus_message_read(message, "ss", &interface_name, &property) < 0) return -1;
	if (mode == '2' && property.str_view() != "ActiveConnections") {
		return sd_bus_reply_method_errorf(
			message,
			"org.freedesktop.DBus.Error.UnknownProperty",
			"missing fixture property"
		);
	}
	if (mode == '4' && property.str_view() != "ActiveConnections") return 1;
	Message* reply;
	if (sd_bus_message_new_method_return(message, &reply) < 0) return -1;
	defer sd_bus_message_unref(reply);
	CInt result = reply_property(message, reply, property.str_view());
	if (result < 0) return result;
	return sd_bus_send(null, reply, null);
}

fn int main(String[] args) {
	if (args.len != 2 || args[1].len != 1 || args[1][0] < '0' || args[1][0] > '4') return 2;
	mode = args[1][0];
	for (usz i = 0; i < long_name.len - 1; i++) long_name[i] = 'x';
	libc::Sigaction action;
	action.sa_handler = &stop;
	if (libc::sigemptyset(
		&action.sa_mask
	) != 0 || libc::sigaction(
		libc::SIGTERM,
		&action,
		null
	) != 0 || libc::sigaction(libc::SIGINT, &action, null) != 0) return 1;
	Bus* bus;
	if (sd_bus_open_user(&bus) < 0) return 1;
	defer sd_bus_unref(bus);
	Slot* slot;
	if (sd_bus_add_filter(bus, &slot, &property_call, null) < 0) return 1;
	defer sd_bus_slot_unref(slot);
	if (sd_bus_request_name(bus, "org.freedesktop.NetworkManager", 0) < 0) return 1;
	io::printn("ready");
	while (mem::@volatile_load(stopping) == 0) {
		CInt result = sd_bus_process(bus, null);
		if (result < 0 && result != -4) return 1;
		if (result <= 0) {
			CInt waited = sd_bus_wait(bus, 100000);
			if (waited < 0 && waited != -4) return 1;
		}
	}
	return 0;
}
