module bar.status;
import core.stdc.stdlib : free;

struct Block {
	const(char)[] text;
	const(char)[] color;
	void* allocation;
}

void close(ref Block block) @nogc nothrow {
	free(block.allocation);
	block = Block.init;
}
