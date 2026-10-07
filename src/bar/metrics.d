module bar.metrics;
import bar.errors : Error, Result;
import bar.status;
import core.stdc.stdio : fopen, fclose, fgets, snprintf;
import core.stdc.stdlib : malloc;
import core.stdc.string : strlen, memcpy;
import core.sys.posix.sys.statvfs : statvfs_t, statvfs;

@nogc nothrow:
private Result!ulong memoryValue(const(char)[] line, const(char)[] key) {
	if (line.length < key.length + 5 || line[0 .. key.length] != key || line[$ - 4 .. $] != " kB\n")
		return Result!ulong(0, Error.invalidInput);
	auto digits = line[key.length .. $ - 4];
	while (digits.length && (digits[0] == ' ' || digits[0] == '\t'))
		digits = digits[1 .. $];
	if (!digits.length)
		return Result!ulong(0, Error.invalidInput);
	ulong result;
	foreach (digit; digits) {
		if (digit < '0' || digit > '9')
			return Result!ulong(0, Error.invalidInput);
		auto value = cast(ulong)(digit - '0');
		if (result > (ulong.max - value) / 10)
			return Result!ulong(0, Error.invalidInput);
		result = result * 10 + value;
	}
	return Result!ulong(result, Error.none);
}

Result!Block block() {
	enum gib = 1024.0 * 1024.0 * 1024.0;
	char[128] disk, ram;
	snprintf(disk.ptr, disk.length, "SSD: ?");
	snprintf(ram.ptr, ram.length, "RAM: ?");
	statvfs_t fs;
	if (statvfs("/", &fs) == 0)
		snprintf(disk.ptr, disk.length, "SSD: %.1f/%.1f GiB",
				cast(double)(fs.f_blocks - fs.f_bfree) * fs.f_frsize / gib, cast(double) fs.f_blocks * fs.f_frsize / gib);
	auto file = fopen("/proc/meminfo", "r");
	if (file !is null) {
		scope (exit)
			fclose(file);
		char[1024] buffer;
		Result!ulong total = Result!ulong(0, Error.unavailable);
		Result!ulong available = Result!ulong(0, Error.unavailable);
		while (fgets(buffer.ptr, cast(int) buffer.length, file) !is null) {
			auto line = buffer[0 .. strlen(buffer.ptr)];
			auto value = memoryValue(line, "MemTotal:");
			if (value.error == Error.none)
				total = value;
			value = memoryValue(line, "MemAvailable:");
			if (value.error == Error.none)
				available = value;
		}
		if (total.error == Error.none && available.error == Error.none && total.value > 0
				&& available.value <= total.value)
			snprintf(ram.ptr, ram.length, "RAM: %.1f/%.1f GiB",
					cast(double)(total.value - available.value) * 1024.0 / gib, cast(double) total.value * 1024.0 / gib);
	}
	auto size = strlen(disk.ptr) + strlen(ram.ptr) + 3;
	auto owned = cast(char*) malloc(size + 1);
	if (owned is null)
		return Result!Block(Block.init, Error.outOfMemory);
	snprintf(owned, size + 1, "%s | %s", disk.ptr, ram.ptr);
	return Result!Block(Block(owned[0 .. size], null, owned), Error.none);
}

unittest {
	assert(memoryValue("MemTotal: 12345 kB\n", "MemTotal:").value == 12_345);
	assert(memoryValue("MemAvailable: 0 kB\n", "MemAvailable:").error == Error.none);
	foreach (line; [
		"MemTotal: -1 kB\n", "MemTotal: kB\n", "MemTotal: 123 GB\n",
		"MemTotal: 9999999999999999999999 kB\n", "MemAvailable: 1 kB\n"
	])
		assert(memoryValue(line, "MemTotal:").error == Error.invalidInput);
}
