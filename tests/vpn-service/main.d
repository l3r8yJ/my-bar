module tests.vpn_service.main;
import core.stdc.stdio : puts, fflush, stdout;
import core.stdc.string : strlen;
import core.sys.posix.signal : sigaction_t, sigaction, sigemptyset, SIGTERM, SIGINT;
import core.volatile : volatileLoad, volatileStore;

@nogc nothrow:
alias Callback = extern (C) int function(void*, void*, void*) nothrow @nogc;
extern (C) {
	int sd_bus_open_user(void** bus);
	void* sd_bus_unref(void* bus);
	void* sd_bus_slot_unref(void* slot);
	int sd_bus_add_filter(void* bus, void** slot, Callback callback, void* userdata);
	int sd_bus_request_name(void* bus, const(char)* name, ulong flags);
	int sd_bus_process(void* bus, void** message);
	int sd_bus_wait(void* bus, ulong timeout);
	int sd_bus_message_is_method_call(void* message, const(char)* iface, const(char)* member);
	const(char)* sd_bus_message_get_path(void* message);
	int sd_bus_message_read(void* message, const(char)* signature, ...);
	int sd_bus_message_new_method_return(void* call, void** reply);
	void* sd_bus_message_unref(void* message);
	int sd_bus_message_open_container(void* message, char kind, const(char)* signature);
	int sd_bus_message_close_container(void* message);
	int sd_bus_message_append(void* message, const(char)* signature, ...);
	int sd_bus_send(void* bus, void* message, ulong* cookie);
	int sd_bus_reply_method_errorf(void* call, const(char)* name, const(char)* format, ...);
}
struct Fixture {
	const(char)* path;
	const(char)* name;
	const(char)* kind;
	uint state;
}

private immutable Fixture[6] fixtures = [
	Fixture("/active/one", "office \"quoted\"", "vpn", 2),
	Fixture("/active/two", "wg", "wireguard", 2), Fixture("/active/three", "tun", "tun", 2),
	Fixture("/active/four", "ethernet", "802-3-ethernet", 2),
	Fixture("/active/five", "connecting", "vpn", 1), Fixture("/active/six", "disconnected", "vpn", 4)
];
private __gshared char mode;
private __gshared uint stopping;
private __gshared char[8192] longName;
private extern (C) void stop(int) {
	volatileStore(&stopping, 1);
}

private int replyProperty(void* message, void* reply, const(char)[] property) {
	if (property == "ActiveConnections") {
		if (sd_bus_message_open_container(reply, 'v', "ao") < 0 || sd_bus_message_open_container(reply, 'a', "o") < 0)
			return -1;
		if (mode != '1') {
			foreach (fixture; fixtures) {
				if (sd_bus_message_append(reply, "o", fixture.path) < 0)
					return -1;
				if (mode == '3')
					break;
			}
		}
		if (sd_bus_message_close_container(reply) < 0)
			return -1;
		return sd_bus_message_close_container(reply);
	}
	auto path = sd_bus_message_get_path(message);
	if (path is null)
		return -2;
	foreach (fixture; fixtures) {
		if (path[0 .. strlen(path)] != fixture.path[0 .. strlen(fixture.path)])
			continue;
		switch (property) {
		case "Type":
			return sd_bus_message_append(reply, "v", "s".ptr, fixture.kind);
		case "State":
			return sd_bus_message_append(reply, "v", "u".ptr, fixture.state);
		case "Id":
			auto name = mode == '3' ? longName.ptr : fixture.name;
			return sd_bus_message_append(reply, "v", "s".ptr, name);
		default:
			return -2;
		}
	}
	return -2;
}

private extern (C) int propertyCall(void* message, void* userdata, void* error) {
	if (sd_bus_message_is_method_call(message, "org.freedesktop.DBus.Properties", "Get") <= 0)
		return 0;
	const(char)* iface, property;
	if (sd_bus_message_read(message, "ss", &iface, &property) < 0 || property is null)
		return -1;
	auto name = property[0 .. strlen(property)];
	if (mode == '2' && name != "ActiveConnections")
		return sd_bus_reply_method_errorf(message, "org.freedesktop.DBus.Error.UnknownProperty",
				"missing fixture property");
	if (mode == '4' && name != "ActiveConnections")
		return 1;
	void* reply;
	if (sd_bus_message_new_method_return(message, &reply) < 0)
		return -1;
	scope (exit)
		cast(void) sd_bus_message_unref(reply);
	auto result = replyProperty(message, reply, name);
	if (result < 0)
		return result;
	return sd_bus_send(null, reply, null);
}

extern (C) int main(int argc, char** argv) {
	if (argc != 2 || strlen(argv[1]) != 1 || argv[1][0] < '0' || argv[1][0] > '4')
		return 2;
	mode = argv[1][0];
	longName[0 .. $ - 1] = 'x';
	longName[$ - 1] = '\0';
	sigaction_t action;
	action.sa_handler = &stop;
	if (sigemptyset(&action.sa_mask) != 0 || sigaction(SIGTERM, &action, null) != 0
			|| sigaction(SIGINT, &action, null) != 0)
		return 1;
	void* bus;
	if (sd_bus_open_user(&bus) < 0)
		return 1;
	scope (exit)
		cast(void) sd_bus_unref(bus);
	void* slot;
	if (sd_bus_add_filter(bus, &slot, &propertyCall, null) < 0)
		return 1;
	scope (exit)
		cast(void) sd_bus_slot_unref(slot);
	if (sd_bus_request_name(bus, "org.freedesktop.NetworkManager", 0) < 0)
		return 1;
	if (puts("ready") < 0 || fflush(stdout) != 0)
		return 1;
	while (volatileLoad(&stopping) == 0) {
		const result = sd_bus_process(bus, null);
		if (result < 0 && result != -4)
			return 1;
		if (result == 0) {
			const waited = sd_bus_wait(bus, 100_000);
			if (waited < 0 && waited != -4)
				return 1;
		}
	}
	return 0;
}
