module bar;
import bar::errors, bar::status, bar::stream, bar::keyboard, bar::vpn, bar::metrics;
import libc, std::os::posix;
extern fn int fork();
extern fn int dup2(int old_fd, int new_fd);
extern fn int execvp(ZString file, ZString* args);
extern fn int poll(PollFd* descriptors, ulong count, int timeout);

struct PollFd {
	int fd;
	short events;
	short returned;
}

struct Reader {
	int fd;
	int child;
	char[4096] buffer;
	sz position;
	sz available;
	DString line;
}

int stopping;

fn void stop(int signal) {
	mem::@volatile_store(stopping, signal);
}

fn bool stopped() {
	return mem::@volatile_load(stopping) != 0;
}

fn void? configure_signals() {
	Sigaction action;
	if (libc::sigemptyset(&action.sa_mask) != 0) return errors::IO_FAILURE~;
	action.sa_handler = &stop;
	if (libc::sigaction(libc::SIGTERM, &action, null) != 0) return errors::IO_FAILURE~;
	if (libc::sigaction(libc::SIGINT, &action, null) != 0) return errors::IO_FAILURE~;
	action.sa_handler = (SignalFunction)(uptr)1;
	if (libc::sigaction(libc::SIGPIPE, &action, null) != 0) return errors::IO_FAILURE~;
}

fn void? write_all(int fd, String data) {
	while (data.len) {
		sz written = libc::write(fd, data.ptr, (usz)data.len);
		if (written < 0 && libc::errno() == EINTR && !stopped()) continue;
		if (written <= 0) return errors::IO_FAILURE~;
		data = data[written..];
	}
}

fn void execute_i3status(int[2] descriptors) {
	if (libc::close(descriptors[0]) != 0 || dup2(descriptors[1], 1) < 0) libc::_exit(127);
	if (descriptors[1] != 1 && libc::close(descriptors[1]) != 0) libc::_exit(127);
	ZString[2] arguments = { "i3status", null };
	(void)execvp("i3status", &arguments[0]);
	libc::_exit(127);
}

fn void close_reader(Reader* reader) {
	reader.line.free();
	(void)posix::kill(reader.child, libc::SIGTERM);
	while (posix::waitpid(reader.child, null, 0) < 0 && libc::errno() == EINTR) {
	}
	(void)libc::close(reader.fd);
}

fn Reader? start_i3status() {
	int[2] descriptors;
	if (posix::pipe(&descriptors) != 0) return errors::IO_FAILURE~;
	int child = fork();
	if (child == 0) execute_i3status(descriptors);
	bool close_failed = libc::close(descriptors[1]) != 0;
	if (child < 0) {
		(void)libc::close(descriptors[0]);
		return errors::IO_FAILURE~;
	}
	Reader reader = { .fd = descriptors[0], .child = child, .line = dstring::new(mem) };
	defer catch close_reader(&reader);
	if (close_failed) return errors::IO_FAILURE~;
	return reader;
}

fn bool? read_line(Reader* reader) {
	reader.line.clear();
	while (!stopped()) {
		if (reader.position == reader.available) {
			PollFd descriptor = { .fd = reader.fd, .events = 1 };
			int ready         = poll(&descriptor, 1, 250);
			if (ready < 0 && libc::errno() == EINTR) continue;
			if (ready < 0) return errors::IO_FAILURE~;
			if (!ready) continue;
			sz count = libc::read(reader.fd, &reader.buffer, reader.buffer.len);
			if (count < 0 && libc::errno() == EINTR) continue;
			if (count < 0) return errors::IO_FAILURE~;
			if (!count) return reader.line.len() > 0;
			reader.position = 0;
			reader.available = count;
		}
		sz start = reader.position;
		while (reader.position < reader.available && reader.buffer[reader.position] != '\n') reader.position++;
		reader.line.append(reader.buffer[start:reader.position - start]);
		if (reader.position < reader.available) {
			reader.position++;
			return true;
		}
	}
	return false;
}

fn String? render_frame(String line, keyboard::Context* keyboard_context, vpn::Context* vpn_context) {
	Block[3] blocks;
	Block? keyboard_block = keyboard::block(keyboard_context);
	if (catch err = keyboard_block) {
		if (err != errors::UNAVAILABLE) return err~;
		blocks[0] = { "?", "" };
	} else {
		blocks[0] = keyboard_block;
	}
	Block? vpn_block = vpn::block(vpn_context);
	if (catch err = vpn_block) {
		if (err != errors::UNAVAILABLE) return err~;
		blocks[1] = { "VPN: unavailable", "#888888" };
	} else {
		blocks[1] = vpn_block;
	}
	blocks[2] = metrics::block()!;
	return stream::render(line, blocks);
}

fn void? run(bool once) {
	configure_signals()!;
	keyboard::Context keyboard_context;
	defer keyboard::close(&keyboard_context);
	if (catch err = keyboard::init(&keyboard_context)) {
		if (err != errors::UNAVAILABLE) return err~;
	}
	vpn::Context vpn_context;
	defer vpn::close(&vpn_context);
	if (catch err = vpn::init(&vpn_context)) {
		if (err != errors::UNAVAILABLE) return err~;
	}
	Reader reader = start_i3status()!;
	defer close_reader(&reader);
	if (!once) write_all(1, "{\"version\":1}\n[\n")!;
	usz frames;
	while (!stopped()) {
		bool available = read_line(&reader) ?? false;
		if (!available) {
			if (stopped()) return;
			return errors::IO_FAILURE~;
		}
		String line = reader.line.str_view().trim_left(" \t\r\n,");
		if (!line.len || line == "[" || line.starts_with("{")) continue;
		@pool() {
			String? output = render_frame(line, &keyboard_context, &vpn_context);
			if (catch err = output) {
				(void)write_all(2, "my-bar: invalid status frame\n");
				return err~;
			}
			if (frames > 0 && !once) write_all(1, ",\n")!;
			write_all(1, output)!;
			write_all(1, "\n")!;
		};
		frames++;
		if (once) return;
	}
}

fn int main(String[] args) {
	bool once = args.len == 2 && args[1] == "--once";
	if (args.len != 1 && !once) {
		(void)write_all(2, "Usage: my-bar [--once]\n");
		return 2;
	}
	if (catch run(once)) return 1;
	return 0;
}
