module bar;
import bar::errors, bar::status, bar::stream, bar::keyboard, bar::vpn, bar::metrics;
import libc, std::os::posix;

extern fn int fork();
extern fn int dup2(int old_fd, int new_fd);
extern fn int execvp(ZString file, ZString* args);
extern fn int poll(PollFd* descriptors, ulong count, int timeout);

struct PollFd
{
	int fd;
	short events;
	short returned;
}
struct Reader
{
	int fd;
	char[4096] buffer;
	sz position;
	sz available;
	DString line;
}
int stopping;

fn void stop(int signal)
{
	mem::@volatile_store(stopping, signal);
}

fn void? write_all(int fd, String data)
{
	while (data.len)
	{
		sz written = libc::write(fd, data.ptr, (usz)data.len);
		if (written < 0 && libc::errno() == EINTR && !mem::@volatile_load(stopping)) continue;
		if (written <= 0) return errors::IO_FAILURE~;
		data = data[written..];
	}
}

fn bool? read_line(Reader* reader)
{
	reader.line.clear();
	while (!mem::@volatile_load(stopping))
	{
		if (reader.position == reader.available)
		{
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
		if (reader.position < reader.available)
		{
			reader.position++;
			return true;
		}
	}
	return false;
}

fn String? render(String line, keyboard::Context* keyboard_context, vpn::Context* vpn_context)
{
	Block[3] blocks;
	Block? keyboard_block = keyboard::block(keyboard_context);
	if (catch err = keyboard_block)
	{
		if (err != errors::UNAVAILABLE) return err~;
		blocks[0] = { "?", "" };
	}
	else
	{
		blocks[0] = keyboard_block;
	}
	Block? vpn_block = vpn::block(vpn_context);
	if (catch err = vpn_block)
	{
		if (err != errors::UNAVAILABLE) return err~;
		blocks[1] = { "VPN: unavailable", "#888888" };
	}
	else
	{
		blocks[1] = vpn_block;
	}
	blocks[2] = metrics::block()!;
	return stream::render(line, blocks);
}

fn int main(String[] args)
{
	bool once = args.len == 2 && args[1] == "--once";
	if (args.len != 1 && !once)
	{
		(void)write_all(2, "Usage: my-bar [--once]\n");
		return 2;
	}
	Sigaction action;
	if (libc::sigemptyset(&action.sa_mask) != 0) return 1;
	action.sa_handler = &stop;
	if (libc::sigaction(
		libc::SIGTERM,
		&action,
		null
	) != 0 || libc::sigaction(libc::SIGINT, &action, null) != 0) return 1;
	action.sa_handler = (SignalFunction)(uptr)1;
	if (libc::sigaction(libc::SIGPIPE, &action, null) != 0) return 1;
	keyboard::Context keyboard_context;
	defer keyboard::close(&keyboard_context);
	if (catch err = keyboard::init(&keyboard_context)) if (err != errors::UNAVAILABLE) return 1;
	vpn::Context vpn_context;
	defer vpn::close(&vpn_context);
	if (catch err = vpn::init(&vpn_context)) if (err != errors::UNAVAILABLE) return 1;
	int[2] descriptors;
	if (posix::pipe(&descriptors) != 0) return 1;
	defer (void)libc::close(descriptors[0]);
	int child = fork();
	if (child == 0)
	{
		if (libc::close(descriptors[0]) != 0 || dup2(descriptors[1], 1) < 0) libc::_exit(127);
		if (descriptors[1] != 1 && libc::close(descriptors[1]) != 0) libc::_exit(127);
		ZString[2] arguments = { "i3status", null };
		(void)execvp("i3status", &arguments[0]);
		libc::_exit(127);
	}
	bool close_failed = libc::close(descriptors[1]) != 0;
	if (child < 0) return 1;
	defer
	{
		(void)posix::kill(child, libc::SIGTERM);
		while (posix::waitpid(child, null, 0) < 0 && libc::errno() == EINTR)
		{
		}
	}
	if (close_failed) return 1;
	if (!once) if (catch write_all(1, "{\"version\":1}\n[\n")) return 1;
	Reader reader = { .fd = descriptors[0], .line = dstring::new(mem) };
	defer reader.line.free();
	usz frames;
	while (!mem::@volatile_load(stopping))
	{
		bool available = read_line(&reader) ?? false;
		if (!available) return mem::@volatile_load(stopping) ? 0 : 1;
		String line = reader.line.str_view().trim_left(" \t\r\n,");
		if (!line.len || line == "[" || line.starts_with("{")) continue;
		@pool()
		{
			String? output = render(line, &keyboard_context, &vpn_context);
			if (catch output)
			{
				(void)write_all(2, "my-bar: invalid status frame\n");
				return 1;
			}
			if (frames > 0 && !once) if (catch write_all(1, ",\n")) return 1;
			if (catch write_all(1, output)) return 1;
			if (catch write_all(1, "\n")) return 1;
		};
		frames++;
		if (once) return 0;
	}
	return 0;
}