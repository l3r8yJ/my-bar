package stream

import "../errors"
import "../status"
import "core:encoding/json"
import "core:mem"
import "core:strings"

@(require_results)
render :: proc(
	input: string,
	blocks: [3]status.Block,
	allocator: mem.Allocator,
) -> (
	[]byte,
	errors.Error,
) {
	context.allocator = allocator
	value, parse_err := json.parse(input, .JSON, parse_integers = true, allocator = allocator)
	if parse_err != .None {
		return nil, .Out_Of_Memory if parse_err == .Out_Of_Memory else .Invalid_Input
	}
	source, ok := value.(json.Array)
	if !ok {
		return nil, .Invalid_Input
	}
	output, allocation_err := make(json.Array, len(source) + 3, allocator)
	if allocation_err != nil {
		return nil, .Out_Of_Memory
	}
	for block, i in blocks {
		object, err := make(json.Object, 3, allocator)
		if err != nil {
			return nil, .Out_Of_Memory
		}
		object["full_text"] = json.String(block.text)
		if block.color != "" {
			object["color"] = json.String(block.color)
		}
		index := i
		if i == 2 && len(source) > 0 {
			index = 3
		}
		output[index] = object
	}
	for block, i in source {
		object, is_object := block.(json.Object)
		if !is_object {
			return nil, .Invalid_Input
		}
		if _, is_string := object["full_text"].(json.String); !is_string {
			return nil, .Invalid_Input
		}
		index := i + 3
		if i == 0 {
			index = 2
		}
		output[index] = object
	}
	for block, i in output {
		object := block.(json.Object)
		text := strings.trim(string(object["full_text"].(json.String)), " ")
		padded, err := make([]byte, len(text) + 2, allocator)
		if err != nil {
			return nil, .Out_Of_Memory
		}
		padded[0], padded[len(padded) - 1] = ' ', ' '
		copy(padded[1:], text)
		if reserve_err := reserve(&object, len(object) + 1); reserve_err != nil {
			return nil, .Out_Of_Memory
		}
		object["full_text"] = json.String(string(padded))
		object["separator_block_width"] = json.Integer(1)
		output[i] = object
	}
	encoded, marshal_err := json.marshal(output, allocator = allocator)
	if marshal_err != nil {
		return nil, .Out_Of_Memory
	}
	return encoded, .None
}
