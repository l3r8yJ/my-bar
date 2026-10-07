module bar.vpn;
import bar.bindings.bus;
import bar.errors : Error, Result;
import bar.status;
import core.stdc.stdlib : free, malloc, realloc, getenv, atoi;
import core.stdc.string : strlen, memcpy;

@nogc nothrow:
private enum service = "org.freedesktop.NetworkManager";
private enum activeInterface = "org.freedesktop.NetworkManager.Connection.Active";
struct Context {
	void* bus;
}

private Error check(int result) {
	if (result == -12)
		return Error.outOfMemory;
	return result < 0 ? Error.unavailable : Error.none;
}

Error init(ref Context ctx) {
	close(ctx);
	auto error = check(sd_bus_open_system(&ctx.bus));
	if (error != Error.none)
		return error;
	error = check(sd_bus_set_method_call_timeout(ctx.bus, 100_000));
	if (error != Error.none)
		close(ctx);
	return error;
}

void close(ref Context ctx) {
	ctx.bus = sd_bus_flush_close_unref(ctx.bus);
}

private Result!(char*) connectionName(ref Context ctx, const(char)* path) {
	char* type;
	auto error = check(sd_bus_get_property_string(ctx.bus, service, path, activeInterface, "Type", null, &type));
	scope (exit)
		free(type);
	if (error != Error.none)
		return Result!(char*)(null, error);
	if (type is null)
		return Result!(char*)(null, Error.unavailable);
	const kind = type[0 .. strlen(type)];
	if (kind != "vpn" && kind != "wireguard" && kind != "tun")
		return Result!(char*)(null, Error.none);
	uint state;
	error = check(sd_bus_get_property_trivial(ctx.bus, service, path, activeInterface, "State", null, 'u', &state));
	if (error != Error.none)
		return Result!(char*)(null, error);
	if (state != 2)
		return Result!(char*)(null, Error.none);
	char* name;
	error = check(sd_bus_get_property_string(ctx.bus, service, path, activeInterface, "Id", null, &name));
	if (error != Error.none) {
		free(name);
		return Result!(char*)(null, error);
	}
	if (name is null)
		return Result!(char*)(null, Error.unavailable);
	return Result!(char*)(name, Error.none);
}

Result!Block block(ref Context ctx) {
	if (ctx.bus is null) {
		auto error = init(ctx);
		if (error != Error.none)
			return Result!Block(Block.init, error);
	}
	scope (exit) {
		if (sd_bus_is_open(ctx.bus) <= 0)
			ctx.bus = sd_bus_unref(ctx.bus);
	}
	void* connections;
	auto error = check(sd_bus_get_property(ctx.bus, service, "/org/freedesktop/NetworkManager",
			service, "ActiveConnections", null, &connections, "ao"));
	scope (exit)
		cast(void) sd_bus_message_unref(connections);
	if (error != Error.none)
		return Result!Block(Block.init, error);
	error = check(sd_bus_message_enter_container(connections, 'a', "o"));
	if (error != Error.none)
		return Result!Block(Block.init, error);
	char* text;
	size_t length;
	scope (exit)
		free(text);
	while (true) {
		const(char)* path;
		auto result = sd_bus_message_read_basic(connections, 'o', &path);
		if (!result)
			break;
		error = check(result);
		if (error != Error.none)
			return Result!Block(Block.init, error);
		auto name = connectionName(ctx, path);
		scope (exit)
			free(name.value);
		if (name.error != Error.none)
			return Result!Block(Block.init, name.error);
		if (name.value is null)
			continue;
		const(char)[] prefix = length ? ", " : "VPN: ";
		auto nameLength = strlen(name.value);
		if (length > size_t.max - prefix.length || nameLength > size_t.max - length - prefix.length)
			return Result!Block(Block.init, Error.outOfMemory);
		auto newLength = length + prefix.length + nameLength;
		auto grown = cast(char*) realloc(text, newLength);
		if (grown is null)
			return Result!Block(Block.init, Error.outOfMemory);
		text = grown;
		memcpy(text + length, prefix.ptr, prefix.length);
		memcpy(text + length + prefix.length, name.value, nameLength);
		length = newLength;
	}
	if (!length)
		return Result!Block(Block("VPN: off", "#888888", null), Error.none);
	auto value = Block(text[0 .. length], "#00cc66", text);
	text = null;
	return Result!Block(value, Error.none);
}
// @todo #9:60min Add coverage control for production D code exercised by tests.
// Generate line and branch coverage through just and CI, publish the report,
// and establish a documented baseline with explicit exclusions. Make CI fail
// below agreed thresholds and demonstrate the gate with a failing fixture.

// @todo #9:60min Select an appropriate testing technique for this native D bar.
// Compare the existing assert-based tests with lightweight native test frameworks
// and choose where unit, integration, and end-to-end tests provide value.
// Apply the chosen approach to one representative behavior, expose it through
// just and CI, and document the decision without adding runtime dependencies.

// @todo #9:60min Add quality control for the test codebase itself. Evaluate
// test-specific checks for meaningful assertions, deterministic execution,
// isolation, and reliable resource cleanup beyond the existing strict compiler,
// formatter, analyzers, and sanitizers. Integrate the selected checks with just
// and CI, fix findings, and prove that a representative violation fails CI.

// @todo #9:60min Introduce mutation testing for a bounded production D module.
// Evaluate compatible tooling and run representative mutations through the
// behavioral tests. Report killed, surviving, and timed-out mutants separately,
// document equivalent-mutant exclusions, and strengthen tests for real survivors.
// Add a just command and a bounded CI job with an agreed mutation-score gate.

unittest {
	auto expected = getenv("MY_BAR_VPN_EXPECT");
	if (expected !is null) {
		auto color = getenv("MY_BAR_VPN_COLOR");
		assert(color !is null);
		int iterations = 20;
		auto count = getenv("MY_BAR_VPN_ITERATIONS");
		if (count !is null)
			iterations = atoi(count);
		assert(iterations > 0);
		Context ctx;
		scope (exit)
			close(ctx);
		foreach (i; 0 .. iterations) {
			if (i % 5 == 0) {
				close(ctx);
				close(ctx);
			}
			auto result = block(ctx);
			scope (exit)
				bar.status.close(result.value);
			if (expected[0 .. strlen(expected)] == "VPN: unavailable")
				assert(result.error == Error.unavailable);
			else {
				assert(result.error == Error.none);
				assert(result.value.text == expected[0 .. strlen(expected)]);
				assert(result.value.color == color[0 .. strlen(color)]);
			}
		}
	}
}
