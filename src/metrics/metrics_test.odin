#+test
package metrics

import "core:testing"

@(test)
validates_memory_values :: proc(t: ^testing.T) {
	value, err := memory_value("MemTotal:   12345 kB\n", "MemTotal:")
	testing.expect_value(t, value, 12345)
	testing.expect_value(t, err, .None)
	value, err = memory_value("MemAvailable: 0 kB\n", "MemAvailable:")
	testing.expect_value(t, value, 0)
	testing.expect_value(t, err, .None)
	for line in ([]string{"MemTotal: -1 kB\n", "MemTotal: nope kB\n", "MemTotal: 123 GB\n", "MemTotal: 9999999999999999999999 kB\n", "MemAvailable: 1 kB\n"}) {
		_, invalid := memory_value(line, "MemTotal:")
		testing.expect_value(t, invalid, .Invalid_Input)
	}
}
