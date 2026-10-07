module tests.runner;
import bar.keyboard;
import bar.metrics;
import bar.stream;
import bar.vpn;
import core.stdc.stdio : puts;

extern (C) int main() @nogc nothrow {
	static foreach (test; __traits(getUnitTests, bar.keyboard))
		test();
	static foreach (test; __traits(getUnitTests, bar.metrics))
		test();
	static foreach (test; __traits(getUnitTests, bar.stream))
		test();
	static foreach (test; __traits(getUnitTests, bar.vpn))
		test();
	cast(void) puts("PASS: native D tests");
	return 0;
}
