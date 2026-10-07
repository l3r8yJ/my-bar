module bar::stream;
import bar::status, bar::errors;
import std::encoding::json, std::collections::object;

fn String? render(String input, Block[3] blocks) {
	Object* source = (json::tparse(input, JSON) ?? errors::INVALID_INPUT~)!;
	if (!source.is_array()) return errors::INVALID_INPUT~;
	Object* output = object::new_array(tmem);
	foreach (sz i, Block block : blocks) {
		Object* item = object::new_obj(tmem);
		item.set("full_text", block.text);
		if (block.color.len) item.set("color", block.color);
		output.push(item);
		if (i == 1 && source.len()) output.push(source.get_at(0));
	}
	for (sz i = 1; i < source.len(); i++) output.push(source.get_at(i));
	for (sz i = 0; i < output.len(); i++) {
		Object* item = output.get_at(i);
		if (!item.is_map()) return errors::INVALID_INPUT~;
		String text = (item.get_string("full_text") ?? errors::INVALID_INPUT~)!;
		text = text.trim(" ");
		DString padded = dstring::temp(" ");
		padded.append(text);
		padded.append(' ');
		item.set("full_text", padded.str_view());
		item.set("separator_block_width", 1);
	}
	return json::marshal_try(tmem, output) ?? errors::INVALID_INPUT~;
}
