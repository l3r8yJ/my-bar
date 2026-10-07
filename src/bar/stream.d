module bar.stream;

import bar.errors : Error, Result;
import bar.status : Block;
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcpy;

@nogc nothrow:

private struct Json;
private struct Tokener;
private enum jsonObject = 4;
private enum jsonArray = 5;
private enum jsonString = 6;
private enum strictUtf8 = 0x01 | 0x10;
private extern (C) {
	Tokener* json_tokener_new();
	void json_tokener_free(Tokener*);
	void json_tokener_set_flags(Tokener*, int);
	Json* json_tokener_parse_ex(Tokener*, const(char)*, int);
	int json_tokener_get_error(Tokener*);
	size_t json_tokener_get_parse_end(Tokener*);
	int json_object_put(Json*);
	Json* json_object_get(Json*);
	int json_object_get_type(Json*);
	Json* json_object_new_array();
	Json* json_object_new_object();
	Json* json_object_new_string_len(const(char)*, int);
	Json* json_object_new_int(int);
	int json_object_array_add(Json*, Json*);
	size_t json_object_array_length(Json*);
	Json* json_object_array_get_idx(Json*, size_t);
	int json_object_object_add(Json*, const(char)*, Json*);
	int json_object_object_get_ex(Json*, const(char)*, Json**);
	const(char)* json_object_get_string(Json*);
	int json_object_get_string_len(Json*);
	long json_object_get_int64(Json*);
	int json_object_get_boolean(Json*);
	const(char)* json_object_to_json_string_length(Json*, int, size_t*);
}

private Error set(Json* object, const(char)* key, Json* value) {
	if (value is null)
		return Error.outOfMemory;
	if (json_object_object_add(object, key, value) == 0)
		return Error.none;
	cast(void) json_object_put(value);
	return Error.outOfMemory;
}

private Error append(Json* array, Json* value) {
	if (value is null)
		return Error.outOfMemory;
	if (json_object_array_add(array, value) == 0)
		return Error.none;
	cast(void) json_object_put(value);
	return Error.outOfMemory;
}

private Error appendBlock(Json* output, Block block) {
	auto item = json_object_new_object();
	if (item is null)
		return Error.outOfMemory;
	scope (exit)
		cast(void) json_object_put(item);
	if (block.text.length > int.max || block.color.length > int.max)
		return Error.invalidInput;
	auto error = set(item, "full_text", json_object_new_string_len(block.text.ptr, cast(int) block.text.length));
	if (error != Error.none)
		return error;
	if (block.color.length != 0) {
		error = set(item, "color", json_object_new_string_len(block.color.ptr, cast(int) block.color.length));
		if (error != Error.none)
			return error;
	}
	return append(output, json_object_get(item));
}

private Error pad(Json* item) {
	if (json_object_get_type(item) != jsonObject)
		return Error.invalidInput;
	Json* value;
	if (!json_object_object_get_ex(item, "full_text", &value) || json_object_get_type(value) != jsonString)
		return Error.invalidInput;
	auto text = json_object_get_string(value)[0 .. json_object_get_string_len(value)];
	while (text.length && text[0] == ' ')
		text = text[1 .. $];
	while (text.length && text[$ - 1] == ' ')
		text = text[0 .. $ - 1];
	if (text.length > int.max - 2)
		return Error.invalidInput;
	auto buffer = cast(char*) malloc(text.length + 2);
	if (buffer is null)
		return Error.outOfMemory;
	scope (exit)
		free(buffer);
	buffer[0] = ' ';
	memcpy(buffer + 1, text.ptr, text.length);
	buffer[text.length + 1] = ' ';
	auto error = set(item, "full_text", json_object_new_string_len(buffer, cast(int) text.length + 2));
	if (error != Error.none)
		return error;
	return set(item, "separator_block_width", json_object_new_int(1));
}

private bool hasNonJsonNumber(const(char)[] input) {
	bool quoted;
	bool escaped;
	foreach (character; input) {
		if (escaped) {
			escaped = false;
		} else if (quoted && character == '\\') {
			escaped = true;
		} else if (character == '"') {
			quoted = !quoted;
		} else if (!quoted && (character == 'N' || character == 'I')) {
			return true;
		}
	}
	return false;
}

Result!(char[]) render(const(char)[] input, Block[3] blocks) {
	if (input.length > int.max || hasNonJsonNumber(input))
		return Result!(char[])(null, Error.invalidInput);
	auto tokener = json_tokener_new();
	if (tokener is null)
		return Result!(char[])(null, Error.outOfMemory);
	scope (exit)
		json_tokener_free(tokener);
	json_tokener_set_flags(tokener, strictUtf8);
	auto source = json_tokener_parse_ex(tokener, input.ptr, cast(int) input.length);
	scope (exit)
		if (source !is null)
			cast(void) json_object_put(source);
	if (json_tokener_get_error(tokener) != 0 || json_tokener_get_parse_end(tokener) != input.length
			|| json_object_get_type(source) != jsonArray)
		return Result!(char[])(null, Error.invalidInput);
	foreach (index; 0 .. json_object_array_length(source)) {
		if (json_object_get_type(json_object_array_get_idx(source, index)) != jsonObject)
			return Result!(char[])(null, Error.invalidInput);
	}
	auto output = json_object_new_array();
	if (output is null)
		return Result!(char[])(null, Error.outOfMemory);
	scope (exit)
		cast(void) json_object_put(output);
	foreach (index, block; blocks) {
		auto error = appendBlock(output, block);
		if (error != Error.none)
			return Result!(char[])(null, error);
		if (index == 1 && json_object_array_length(source) != 0) {
			error = append(output, json_object_get(json_object_array_get_idx(source, 0)));
			if (error != Error.none)
				return Result!(char[])(null, error);
		}
	}
	foreach (index; 1 .. json_object_array_length(source)) {
		auto error = append(output, json_object_get(json_object_array_get_idx(source, index)));
		if (error != Error.none)
			return Result!(char[])(null, error);
	}
	foreach (index; 0 .. json_object_array_length(output)) {
		auto error = pad(json_object_array_get_idx(output, index));
		if (error != Error.none)
			return Result!(char[])(null, error);
	}
	size_t length;
	auto serialized = json_object_to_json_string_length(output, 0, &length);
	if (serialized is null)
		return Result!(char[])(null, Error.outOfMemory);
	auto owned = cast(char*) malloc(length);
	if (owned is null)
		return Result!(char[])(null, Error.outOfMemory);
	memcpy(owned, serialized, length);
	return Result!(char[])(owned[0 .. length], Error.none);
}

unittest {
	Block[3] blocks = [Block("EN"), Block("VPN: off", "#FF5555"), Block("RAM")];
	enum input = `[{"full_text":" Русский \"\\\n ","count":9007199254740993`
		~ `,"urgent":true,"nested":{"a":[null,false,3]}}]`;
	auto result = render(input, blocks);
	assert(result.error == Error.none);
	scope (exit)
		free(result.value.ptr);
	auto tokener = json_tokener_new();
	scope (exit)
		json_tokener_free(tokener);
	auto output = json_tokener_parse_ex(tokener, result.value.ptr, cast(int) result.value.length);
	scope (exit)
		cast(void) json_object_put(output);
	assert(json_object_array_length(output) == 4);
	Json* text;
	assert(json_object_object_get_ex(json_object_array_get_idx(output, 2), "full_text", &text));
	assert(json_object_get_string(text)[0 .. json_object_get_string_len(text)] == " Русский \"\\\n ");
	Json* count;
	assert(json_object_object_get_ex(json_object_array_get_idx(output, 2), "count", &count));
	assert(json_object_get_int64(count) == 9_007_199_254_740_993);
	Json* urgent;
	assert(json_object_object_get_ex(json_object_array_get_idx(output, 2), "urgent", &urgent));
	assert(json_object_get_boolean(urgent));
	foreach (index; 0 .. json_object_array_length(output)) {
		Json* separator;
		assert(json_object_object_get_ex(json_object_array_get_idx(output, index),
				"separator_block_width", &separator));
		assert(json_object_get_int64(separator) == 1);
	}
	foreach (invalid; [
		"null", "{}", "[1]", "[{\"full_text\":3}]", "[{\"full_text\":\"x\",\"bad\":01}]",
		"[] garbage", "[null]", `[{"full_text":"x","bad":NaN}]`,
		`[{"full_text":"x","bad":Infinity}]`, `[{"full_text":"x","bad":-Infinity}]`,
		"[{\"full_text\":\"\xff\"}]"
	]) {
		const auto rejected = render(invalid, blocks);
		assert(rejected.error != Error.none);
	}
	auto empty = render("[]", blocks);
	assert(empty.error == Error.none);
	free(empty.value.ptr);
}
