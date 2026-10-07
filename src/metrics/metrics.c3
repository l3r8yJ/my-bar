module bar::metrics;
import bar::errors, bar::status;
import libc;
struct Statvfs
{
	ulong bsize;
	ulong frsize;
	ulong blocks;
	ulong bfree;
	ulong bavail;
	ulong files;
	ulong ffree;
	ulong favail;
	ulong fsid;
	ulong flag;
	ulong namemax;
	int[6] spare;
}
extern fn int statvfs(ZString path, Statvfs* info);
fn ulong? memory_value(String line, String key)
{
	if (line.len < key.len + 5 || !line.starts_with(key) || !line.ends_with(" kB\n")) return errors::INVALID_INPUT~;
	String digits = line[key.len:line.len - key.len - 4].trim_left(" \t");
	if (!digits.len) return errors::INVALID_INPUT~;
	ulong result;
	foreach (digit : digits)
	{
		if (digit < '0' || digit > '9') return errors::INVALID_INPUT~;
		ulong value = (ulong)(digit - '0');
		if (result > (ulong::max - value) / 10) return errors::INVALID_INPUT~;
		result = result * 10 + value;
	}
	return result;
}
fn Block? block()
{
	const double GIB = 1024.0 * 1024.0 * 1024.0;
	String disk      = "SSD: ?";
	String ram       = "RAM: ?";
	Statvfs fs;
	if (statvfs(
		"/",
		&fs
	) == 0) disk = string::tformat(
		"SSD: %.1f/%.1f GiB",
		(double)(fs.blocks - fs.bfree) * (double)fs.frsize / GIB,
		(double)fs.blocks * (double)fs.frsize / GIB
	);
	libc::CFile file = libc::fopen("/proc/meminfo", "r");
	if (file)
	{
		defer libc::fclose(file);
		char[1024] buffer;
		ulong total;
		ulong available;
		bool has_total;
		bool has_available;
		while (libc::fgets(&buffer, (int)buffer.len, file))
		{
			String line = ((ZString)&buffer).str_view();
			if (try value = memory_value(line, "MemTotal:"))
			{
				total = value;
				has_total = true;
			}
			if (try value = memory_value(line, "MemAvailable:"))
			{
				available = value;
				has_available = true;
			}
		}
		if (has_total && has_available && total > 0 && available <= total) ram = string::tformat(
			"RAM: %.1f/%.1f GiB",
			(double)(total - available) * 1024.0 / GIB,
			(double)total * 1024.0 / GIB
		);
	}
	return { .text = string::tformat("%s | %s", disk, ram) };
}