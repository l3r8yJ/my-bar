package main

import "base:intrinsics"
import "core:c"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "errors"
import "keyboard"
import "metrics"
import "status"
import "stream"
import "vpn"

stopping: c.int

stop :: proc "c" (_: posix.Signal) {
	intrinsics.volatile_store(&stopping, 1)
}

@(require_results)
write_all :: proc(fd: posix.FD, data: string) -> errors.Error {
	remaining := data
	for len(remaining) > 0 {
		written := posix.write(fd, raw_data(remaining), c.size_t(len(remaining)))
		if written < 0 && posix.errno() == .EINTR {
			if intrinsics.volatile_load(&stopping) != 0 {
				return .Io
			}
			continue
		}
		if written <= 0 {
			return .Io
		}
		remaining = remaining[int(written):]
	}
	return .None
}

Reader :: struct {
	fd:                  posix.FD,
	buffer:              [4096]byte,
	position, available: int,
	line:                [dynamic]byte,
}

@(require_results)
read_line :: proc(reader: ^Reader) -> (string, bool, errors.Error) {
	clear(&reader.line)
	for intrinsics.volatile_load(&stopping) == 0 {
		if reader.position == reader.available {
			pollfd := posix.pollfd {
				fd     = reader.fd,
				events = {.IN},
			}
			ready := posix.poll(&pollfd, 1, 250)
			if ready < 0 {
				if posix.errno() == .EINTR {
					continue
				}
				return "", false, .Io
			}
			if ready == 0 {
				continue
			}
			count := posix.read(reader.fd, raw_data(reader.buffer[:]), len(reader.buffer))
			if count < 0 {
				if posix.errno() == .EINTR {
					continue
				}
				return "", false, .Io
			}
			if count == 0 {
				return string(reader.line[:]), len(reader.line) > 0, .None
			}
			reader.position, reader.available = 0, int(count)
		}
		start := reader.position
		for reader.position < reader.available && reader.buffer[reader.position] != '\n' {
			reader.position += 1
		}
		if _, err := append(&reader.line, ..reader.buffer[start:reader.position]); err != nil {
			return "", false, .Out_Of_Memory
		}
		if reader.position < reader.available {
			reader.position += 1
			return string(reader.line[:]), true, .None
		}
	}
	return "", false, .None
}

@(require_results)
frame :: proc(
	line: string,
	keyboard_context: ^keyboard.Context,
	vpn_context: ^vpn.Context,
	allocator: mem.Allocator,
) -> (
	[]byte,
	errors.Error,
) {
	blocks: [3]status.Block
	block_err: errors.Error
	blocks[0], block_err = keyboard.block(keyboard_context, allocator)
	if block_err != .None && block_err != .Unavailable {
		return nil, block_err
	}
	blocks[1], block_err = vpn.block(vpn_context, allocator)
	if block_err != .None && block_err != .Unavailable {
		return nil, block_err
	}
	blocks[2], block_err = metrics.block(allocator)
	if block_err != .None && block_err != .Unavailable {
		return nil, block_err
	}
	return stream.render(line, blocks, allocator)
}

@(require_results)
run :: proc() -> (result: int) {
	once := len(os.args) == 2 && os.args[1] == "--once"
	if len(os.args) > 1 && !once {
		_ = write_all(2, string("Usage: my-bar [--once]\n"))
		return 2
	}
	action := posix.sigaction_t{}
	if posix.sigemptyset(&action.sa_mask) != 0 {
		return 1
	}
	action.sa_handler = stop
	if posix.sigaction(.SIGTERM, &action, nil) != nil ||
	   posix.sigaction(.SIGINT, &action, nil) != nil {
		return 1
	}
	action.sa_handler = auto_cast posix.SIG_IGN
	if posix.sigaction(.SIGPIPE, &action, nil) != nil {
		return 1
	}
	keyboard_context: keyboard.Context
	keyboard_err := keyboard.init(&keyboard_context)
	defer keyboard.close(&keyboard_context)
	if keyboard_err != .None && keyboard_err != .Unavailable {
		return 1
	}
	vpn_context: vpn.Context
	vpn_err := vpn.init(&vpn_context)
	defer vpn.close(&vpn_context)
	if vpn_err != .None && vpn_err != .Unavailable {
		return 1
	}
	descriptors: [2]posix.FD
	if posix.pipe(&descriptors) != nil {
		return 1
	}
	defer if posix.close(descriptors[0]) != nil {
		result = 1
	}
	child := posix.fork()
	if child == 0 {
		if posix.close(descriptors[0]) != nil || posix.dup2(descriptors[1], 1) < 0 {
			posix._exit(127)
		}
		if descriptors[1] != 1 && posix.close(descriptors[1]) != nil {
			posix._exit(127)
		}
		arguments := [2]cstring{"i3status", nil}
		_ = posix.execvp("i3status", raw_data(arguments[:]))
		posix._exit(127)
	}
	write_close_failed := posix.close(descriptors[1]) != nil
	if child < 0 {
		return 1
	}
	defer {
		if posix.kill(child, .SIGTERM) != nil && posix.errno() != .ESRCH {
			result = 1
		}
		for posix.waitpid(child, nil, {}) < 0 {
			if posix.errno() != .EINTR {
				result = 1
				break
			}
		}
	}
	if write_close_failed {
		return 1
	}
	if !once && write_all(1, string("{\"version\":1}\n[\n")) != .None {
		return 1
	}
	reader := Reader {
		fd = descriptors[0],
	}
	defer delete(reader.line)
	frames := 0
	for intrinsics.volatile_load(&stopping) == 0 {
		line, available, read_err := read_line(&reader)
		if read_err != .None {
			return 1
		}
		if !available {
			break
		}
		line = strings.trim_left(line, ", \t")
		if strings.has_prefix(line, "{") || line == "[" {
			continue
		}
		arena: vmem.Arena
		if vmem.arena_init_growing(&arena) != nil {
			return 1
		}
		defer vmem.arena_destroy(&arena)
		encoded, frame_err := frame(
			line,
			&keyboard_context,
			&vpn_context,
			vmem.arena_allocator(&arena),
		)
		if frame_err != .None {
			_ = write_all(2, string("my-bar: invalid or unavailable i3status frame\n"))
			return 1
		}
		if frames > 0 && !once && write_all(1, string(",")) != .None {
			return 1
		}
		if write_all(1, string(encoded)) != .None || write_all(1, string("\n")) != .None {
			return 1
		}
		frames += 1
		if once {
			return 0
		}
	}
	return 0 if intrinsics.volatile_load(&stopping) != 0 else 1
}

main :: proc() {
	os.exit(run())
}
