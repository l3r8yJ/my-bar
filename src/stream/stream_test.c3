module bar::stream;
import std::encoding::json, std::collections::object;

fn void preserves_fields_and_unicode() @test
{
	@pool()
	{
		String rendered = render(
			`[{"full_text":"  Русский \"\\\n ","count":9007199254740993,"urgent":true,"nested":{"a":[null,false,3]}}]`,
			{ { "EN", "" }, { "VPN: off", "#FF5555" }, { "RAM", "" } }
		)!!;
		Object* result = json::tparse(rendered, JSON)!!;
		assert(result.len() == 4);
		assert(result.get_at(0).get_string("full_text")!! == " EN ");
		assert(result.get_at(1).get_string("full_text")!! == " VPN: off ");
		Object* source = result.get_at(2);
		assert(source.get_string("full_text")!! == " Русский \"\\\n ");
		assert(source.get_long("count")!! == 9007199254740993);
		assert(source.get_bool("urgent")!!);
		assert(source.get("nested")!!.get("a")!!.get_at(0).is_null());
		assert(result.get_at(3).get_string("full_text")!! == " RAM ");
		for (sz i = 0; i < result.len(); i++) assert(result.get_at(i).get_int("separator_block_width")!! == 1);
	};
}

fn void rejects_malformed_frames() @test
{
	String[] inputs = {
		"{}",
		"null",
		"[{}]",
		"[null]",
		"[1]",
		"[{\"full_text\":3}]",
		"[] trailing",
		"[/* comment */]",
		"[true,]",
		"[",
		"[{\"full_text\":\"x\",\"bad\":01}]"
	};
	foreach (String input : inputs)
	{
		@pool()
		{
			if (try render(
				input,
				{ { "EN", "" }, { "VPN: off", "" }, { "RAM", "" } }
			)) assert(false, "Malformed frame accepted");
		};
	}
}

fn void accepts_empty_frame() @test
{
	@pool()
	{
		String rendered = render("[]", { { "EN", "" }, { "VPN: off", "" }, { "RAM", "" } })!!;
		Object* result  = json::tparse(rendered, JSON)!!;
		assert(result.len() == 3);
		assert(result.get_at(2).get_string("full_text")!! == " RAM ");
	};
}