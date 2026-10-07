module bar::metrics;
import bar::errors, bar::status;
fn void validates_memory_values() @test
{
	assert(memory_value("MemTotal: 12345 kB\n", "MemTotal:")!! == 12345);
	assert(memory_value("MemAvailable: 0 kB\n", "MemAvailable:")!! == 0);
	foreach (String line : {
		"MemTotal: -1 kB\n",
		"MemTotal: nope kB\n",
		"MemTotal: 123 GB\n",
		"MemTotal: 9999999999999999999999 kB\n",
		"MemAvailable: 1 kB\n"
	})
	{
		if (catch err = memory_value(line, "MemTotal:"))
		{
			assert(err == errors::INVALID_INPUT);
		}
		else
		{
			assert(false);
		}
	}
}