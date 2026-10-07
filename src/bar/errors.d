module bar.errors;

enum Error {
	none,
	unavailable,
	invalidInput,
	outOfMemory,
	io
}

struct Result(T) {
	T value;
	Error error;
}
