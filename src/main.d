module bar.main;

import bar.errors : Error, Result;
import bar.status : Block;
import status = bar.status;
import stream = bar.stream;
import keyboard = bar.keyboard;
import vpn = bar.vpn;
import metrics = bar.metrics;
import core.stdc.errno : errno, EINTR;
import core.stdc.stdlib : free, realloc;
import core.stdc.string : memcpy, strcmp;
import core.sys.posix.unistd : pipe, fork, dup2, execvp, read, write, close, _exit;
import core.sys.posix.signal : sigaction_t, sigaction, sigemptyset, SIGTERM, SIGINT, SIGPIPE, SIG_IGN, kill;
import core.sys.posix.sys.wait : waitpid;
import core.sys.posix.poll : pollfd, poll, POLLIN;
import core.volatile : volatileLoad, volatileStore;

@nogc nothrow:

private uint stopping;

private struct Reader {
	int fd = -1;
	int child = -1;
	char[4096] buffer;
	size_t position;
	size_t available;
	char* line;
	size_t length;
	size_t capacity;
}

private extern (C) void stop(int signal) {
	volatileStore(&stopping, cast(uint) signal);
}

private bool stopped() {
	return volatileLoad(&stopping) != 0;
}

private Error configureSignals() {
	sigaction_t action;
	if (sigemptyset(&action.sa_mask) != 0)
		return Error.io;
	action.sa_handler = &stop;
	if (sigaction(SIGTERM, &action, null) != 0 || sigaction(SIGINT, &action, null) != 0)
		return Error.io;
	action.sa_handler = SIG_IGN;
	if (sigaction(SIGPIPE, &action, null) != 0)
		return Error.io;
	return Error.none;
}

private Error writeAll(int fd, const(char)[] data) {
	while (data.length != 0) {
		auto written = write(fd, data.ptr, data.length);
		if (written < 0 && errno == EINTR && !stopped())
			continue;
		if (written <= 0)
			return Error.io;
		data = data[written .. $];
	}
	return Error.none;
}

private void executeI3status(int[2] descriptors) {
	if (close(descriptors[0]) != 0 || dup2(descriptors[1], 1) < 0)
		_exit(127);
	if (descriptors[1] != 1 && close(descriptors[1]) != 0)
		_exit(127);
	const(char)*[2] arguments = ["i3status".ptr, null];
	execvp(arguments[0], arguments.ptr);
	_exit(127);
}

private void closeReader(ref Reader reader) {
	free(reader.line);
	if (reader.child > 0) {
		kill(reader.child, SIGTERM);
		while (waitpid(reader.child, null, 0) < 0 && errno == EINTR) {
		}
	}
	if (reader.fd >= 0)
		close(reader.fd);
}

private Error startI3status(ref Reader reader) {
	int[2] descriptors;
	if (pipe(descriptors) != 0)
		return Error.io;
	auto child = fork();
	if (child == 0)
		executeI3status(descriptors);
	const bool writeClosed = close(descriptors[1]) == 0;
	if (child < 0) {
		close(descriptors[0]);
		return Error.io;
	}
	reader.fd = descriptors[0];
	reader.child = child;
	return writeClosed ? Error.none : Error.io;
}

private Error appendLine(ref Reader reader, const(char)[] data) {
	if (data.length > size_t.max - reader.length)
		return Error.outOfMemory;
	auto length = reader.length + data.length;
	if (length > reader.capacity) {
		auto capacity = length <= size_t.max / 2 ? length * 2 : length;
		auto line = cast(char*) realloc(reader.line, capacity);
		if (line is null)
			return Error.outOfMemory;
		reader.line = line;
		reader.capacity = capacity;
	}
	if (data.length)
		memcpy(reader.line + reader.length, data.ptr, data.length);
	reader.length = length;
	return Error.none;
}

private Result!bool readLine(ref Reader reader) {
	reader.length = 0;
	while (!stopped()) {
		if (reader.position == reader.available) {
			pollfd descriptor = pollfd(reader.fd, POLLIN, 0);
			const auto ready = poll(&descriptor, 1, 250);
			if (ready == 0 || (ready < 0 && errno == EINTR))
				continue;
			if (ready < 0)
				return Result!bool(false, Error.io);
			const auto count = read(reader.fd, reader.buffer.ptr, reader.buffer.length);
			if (count < 0 && errno == EINTR)
				continue;
			if (count < 0)
				return Result!bool(false, Error.io);
			if (count == 0)
				return Result!bool(reader.length != 0, Error.none);
			reader.position = 0;
			reader.available = cast(size_t) count;
		}
		auto start = reader.position;
		while (reader.position < reader.available && reader.buffer[reader.position] != '\n')
			reader.position++;
		auto error = appendLine(reader, reader.buffer[start .. reader.position]);
		if (error != Error.none)
			return Result!bool(false, error);
		if (reader.position < reader.available) {
			reader.position++;
			return Result!bool(true, Error.none);
		}
	}
	return Result!bool(false, Error.none);
}

private Result!(char[]) renderFrame(const(char)[] line, ref keyboard.Context keyboardState, ref vpn.Context vpnState) {
	Block[3] blocks;
	scope (exit)
		foreach (ref block; blocks)
			status.close(block);
	auto keyboardBlock = keyboard.block(keyboardState);
	blocks[0] = keyboardBlock.value;
	if (keyboardBlock.error != Error.none && keyboardBlock.error != Error.unavailable)
		return Result!(char[])(null, keyboardBlock.error);
	if (keyboardBlock.error == Error.unavailable)
		blocks[0] = Block("?");
	auto vpnBlock = vpn.block(vpnState);
	blocks[1] = vpnBlock.value;
	if (vpnBlock.error != Error.none && vpnBlock.error != Error.unavailable)
		return Result!(char[])(null, vpnBlock.error);
	if (vpnBlock.error == Error.unavailable)
		blocks[1] = Block("VPN: unavailable", "#888888");
	auto metricsBlock = metrics.block();
	blocks[2] = metricsBlock.value;
	if (metricsBlock.error != Error.none)
		return Result!(char[])(null, metricsBlock.error);
	return stream.render(line, blocks);
}

private const(char)[] statusLine(const(char)[] line) {
	while (line.length != 0 && (line[0] == ' ' || line[0] == '\t' || line[0] == '\r' || line[0] == '\n' || line[0] == ','))
		line = line[1 .. $];
	return line;
}

private Error writeFrames(ref Reader reader, ref keyboard.Context keyboardState, ref vpn.Context vpnState, bool once) {
	size_t frames;
	while (!stopped()) {
		auto available = readLine(reader);
		if (stopped())
			return Error.none;
		if (available.error != Error.none)
			return available.error;
		if (!available.value)
			return Error.io;
		auto line = statusLine(reader.line[0 .. reader.length]);
		if (!line.length || line == "[" || line[0] == '{')
			continue;
		auto output = renderFrame(line, keyboardState, vpnState);
		scope (exit)
			free(output.value.ptr);
		if (output.error != Error.none) {
			cast(void) writeAll(2, "my-bar: invalid status frame\n");
			return output.error;
		}
		if (frames > 0 && !once && writeAll(1, ",\n") != Error.none)
			return Error.io;
		if (writeAll(1, output.value) != Error.none || writeAll(1, "\n") != Error.none)
			return Error.io;
		frames++;
		if (once)
			return Error.none;
	}
	return Error.none;
}

private Error run(bool once) {
	auto error = configureSignals();
	if (error != Error.none)
		return error;
	keyboard.Context keyboardState;
	scope (exit)
		keyboard.close(keyboardState);
	error = keyboard.init(keyboardState);
	if (error != Error.none && error != Error.unavailable)
		return error;
	vpn.Context vpnState;
	scope (exit)
		vpn.close(vpnState);
	error = vpn.init(vpnState);
	if (error != Error.none && error != Error.unavailable)
		return error;
	Reader reader;
	scope (exit)
		closeReader(reader);
	error = startI3status(reader);
	if (error != Error.none)
		return error;
	if (!once && writeAll(1, "{\"version\":1}\n[\n") != Error.none)
		return Error.io;
	return writeFrames(reader, keyboardState, vpnState, once);
}

extern (C) int main(int argc, char** argv) {
	const bool once = argc == 2 && strcmp(argv[1], "--once") == 0;
	if (argc != 1 && !once) {
		cast(void) writeAll(2, "Usage: my-bar [--once]\n");
		return 2;
	}
	return run(once) == Error.none ? 0 : 1;
}
