package metrics

import "../errors"
import "../status"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sys/posix"

@(require_results)
memory_value :: proc(line, key: string) -> (u64, errors.Error) {
	if len(line) < len(key) + 5 ||
	   !strings.has_prefix(line, key) ||
	   !strings.has_suffix(line, " kB\n") {
		return 0, .Invalid_Input
	}
	value := strings.trim_left(line[len(key):len(line) - 4], " \t\r\n\v\f")
	if len(value) == 0 {
		return 0, .Invalid_Input
	}
	number: u64
	for digit in value {
		if digit < '0' || digit > '9' {
			return 0, .Invalid_Input
		}
		next := u64(digit - '0')
		if number > (max(u64) - next) / 10 {
			return 0, .Invalid_Input
		}
		number = number * 10 + next
	}
	return number, .None
}

@(require_results)
block :: proc(allocator: mem.Allocator) -> (status.Block, errors.Error) {
	gib :: 1024.0 * 1024.0 * 1024.0
	disk, ram := "SSD: ?", "RAM: ?"
	disk_buffer, ram_buffer: [96]byte
	result: errors.Error
	fs: posix.statvfs_t
	if posix.statvfs("/", &fs) == nil {
		disk = fmt.bprintf(
			disk_buffer[:],
			"SSD: %.1f/%.1f GiB",
			f64(fs.f_blocks - fs.f_bfree) * f64(fs.f_frsize) / gib,
			f64(fs.f_blocks) * f64(fs.f_frsize) / gib,
		)
	} else {
		result = .Unavailable
	}
	data, read_error := os.read_entire_file("/proc/meminfo", allocator)
	defer delete(data, allocator)
	if read_error == nil {
		total, available: u64
		has_total, has_available := false, false
		remaining := string(data)
		for len(remaining) > 0 {
			end := strings.index_byte(remaining, '\n')
			if end < 0 {
				break
			}
			complete := remaining[:end + 1]
			remaining = remaining[end + 1:]
			if value, err := memory_value(complete, "MemTotal:"); err == .None {
				total, has_total = value, true
			}
			if value, err := memory_value(complete, "MemAvailable:"); err == .None {
				available, has_available = value, true
			}
		}
		if has_total && has_available && total > 0 && available <= total {
			ram = fmt.bprintf(
				ram_buffer[:],
				"RAM: %.1f/%.1f GiB",
				f64(total - available) * 1024 / gib,
				f64(total) * 1024 / gib,
			)
		} else {
			result = .Unavailable
		}
	} else {
		if _, allocation_failure := read_error.(mem.Allocator_Error); allocation_failure {
			return {}, .Out_Of_Memory
		}
		result = .Unavailable
	}
	text, allocation_error := strings.concatenate([]string{disk, " | ", ram}, allocator)
	if allocation_error != nil {
		return {}, .Out_Of_Memory
	}
	return {text = text}, result
}
