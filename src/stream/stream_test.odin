#+test
package stream

import "../status"
import "core:encoding/json"
import "core:mem"
import "core:testing"

@(test)
preserves_source_fields_and_orders_blocks :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	blocks := [3]status.Block{{text = "⌨ us"}, {text = "VPN: on"}, {text = "SSD: 1 GiB"}}
	encoded, err := render(
		`[{"full_text":"  network  ","color":"#abcdef","urgent":true},{"full_text":"clock"}]`,
		blocks,
		allocator,
	)
	testing.expect_value(t, err, .None)
	value, parse_err := json.parse(encoded, allocator = allocator)
	testing.expect_value(t, parse_err, .None)
	array := value.(json.Array)
	testing.expect_value(t, len(array), 5)
	expected := [5]string{" ⌨ us ", " VPN: on ", " network ", " SSD: 1 GiB ", " clock "}
	for item, i in array {
		object := item.(json.Object)
		testing.expect_value(t, string(object["full_text"].(json.String)), expected[i])
		testing.expect_value(t, object["separator_block_width"].(json.Float), 1)
	}
	testing.expect_value(t, array[2].(json.Object)["urgent"].(json.Boolean), true)
	testing.expect_value(t, string(array[2].(json.Object)["color"].(json.String)), "#abcdef")
}

@(test)
rejects_invalid_frames_and_handles_empty_source :: proc(t: ^testing.T) {
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	allocator := mem.dynamic_arena_allocator(&arena)
	blocks := [3]status.Block{{text = "us"}, {text = "VPN: off"}, {text = "SSD"}}
	inputs := []string {
		"not-json",
		`{}`,
		`[1]`,
		`[{"full_text":3}]`,
		`[{"other":"text"}]`,
		`[{"full_text":"unterminated}]`,
	}
	for input in inputs {
		_, err := render(input, blocks, allocator)
		testing.expect_value(t, err, .Invalid_Input)
	}
	encoded, err := render("[]", blocks, allocator)
	testing.expect_value(t, err, .None)
	value, parse_err := json.parse(encoded, allocator = allocator)
	testing.expect_value(t, parse_err, .None)
	testing.expect_value(t, len(value.(json.Array)), 3)
}

@(test)
reports_frame_allocation_failure :: proc(t: ^testing.T) {
	arena: mem.Arena
	buffer: [1]byte
	mem.arena_init(&arena, buffer[:])
	_, err := render("[]", {}, mem.arena_allocator(&arena))
	testing.expect_value(t, err, .Out_Of_Memory)
}
