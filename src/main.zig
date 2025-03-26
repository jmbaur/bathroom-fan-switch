const builtin = @import("builtin");
const std = @import("std");
const microzig = @import("microzig");

const SHT3x = @import("./sht3x.zig");

const time = microzig.drivers.time;
const rp2xxx = microzig.hal;
const i2c = rp2xxx.i2c;
const gpio = rp2xxx.gpio;

pub const microzig_options = microzig.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = rp2xxx.uart.logFn,
};

const uart = rp2xxx.uart.instance.UART0;
const baud_rate = 115200;
const uart_tx_pin = gpio.num(0);
const uart_rx_pin = gpio.num(1);

const i2c1 = i2c.instance.I2C1;
const i2c_pins = &.{ gpio.num(2), gpio.num(3) };

const relay = gpio.num(13);
const button = gpio.num(7);

fn RollingAverage(T: type, max_values: usize) type {
    // TODO(jared): Is it safe to convert f128 or f80 to f64? Probably not!
    const data_is_float = switch (T) {
        f128, f80, f64, f32, f16 => true,
        else => false,
    };

    return struct {
        /// The position in the array where the next stored sample will go.
        index: usize = 0,

        /// The data itself.
        data: [max_values]?T = [_]?T{null} ** max_values,

        fn reset(self: *@This()) void {
            self.data = [_]?T{null} ** max_values;
        }

        fn average(self: *@This()) f64 {
            var total: f64 = 0;
            var count: f64 = 0;

            for (self.data) |data| {
                if (data) |d| {
                    total += @as(f64, if (data_is_float) d else @floatFromInt(d));
                    count += 1;
                }
            }

            return total / count;
        }

        fn store(self: *@This(), value: T) void {
            std.debug.assert(0 <= self.index and self.index < self.data.len);

            self.data[self.index] = value;

            if (self.index + 1 >= self.data.len) {
                self.index = 0;
            } else {
                self.index += 1;
            }
        }
    };
}

test {
    var avg = RollingAverage(usize, 100){};

    avg.store(1);
    try std.testing.expectEqual(1, avg.average());

    avg.reset();

    for (0..100) |value| {
        avg.store(value);
    }
    try std.testing.expectEqual(49.5, avg.average());

    avg.store(100);
    try std.testing.expectEqual(50.5, avg.average());
}

const spike_diff = 7.5;
const dip_diff = 2.5;

pub fn main() !void {
    inline for (&.{ uart_tx_pin, uart_rx_pin }) |pin| {
        pin.set_function(.uart);
    }

    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });

    rp2xxx.uart.init_logger(uart);

    inline for (i2c_pins) |pin| {
        pin.set_slew_rate(.slow);
        pin.set_schmitt_trigger(.enabled);
        pin.set_function(.i2c);
    }

    try i2c1.apply(.{ .clock_config = rp2xxx.clock_config });

    relay.set_direction(.out);
    relay.set_function(.sio);

    button.set_direction(.in);
    button.set_function(.sio);

    var sht3x = SHT3x{ .i2c_instance = i2c1 };

    while (true) {
        if (sht3x.reset()) {
            break;
        } else |err| {
            std.log.err("failed to reset SHT3x: {}", .{err});
            rp2xxx.time.sleep_ms(5000);
        }
    }

    var relay_status: enum {
        force_closed,
        closed,
        open,
    } = .open;

    var avg = RollingAverage(f64, 100){};

    while (true) {
        defer rp2xxx.time.sleep_ms(1000);

        relay.put(@intFromBool(relay_status != .open));

        const sample = sht3x.sample() catch |err| {
            std.log.err("failed to sample: {}", .{err});
            continue;
        };

        std.log.debug("current humidity: {d:.1}%", .{sample.humidity});

        // Do not store sampled data if the fan is on. Presumably the fan is on
        // for a reason, so the humidity might be higher than normal.
        if (relay_status == .open) {
            avg.store(sample.humidity);
        }

        // Turn on the fan no matter what. This allows for a user to manually
        // turn on the fan if they are pooping and don't want others to hear.
        if (button.read() == 1) {
            relay_status = .force_closed;
        } else {
            switch (relay_status) {
                .force_closed => {
                    // Only open the relay if the button is not pressed and was
                    // previously force closed (via button press).
                    relay_status = .open;
                },
                .closed => {
                    const average = avg.average();

                    if (sample.humidity < average + dip_diff) {
                        // We have come back down to an acceptable humidity
                        // where we can open the relay.
                        std.log.info(
                            "relative humidity below {d:.1}% + {d:.1}%, turning off fan",
                            .{ average, dip_diff },
                        );
                        relay_status = .open;
                    }
                },
                .open => {
                    const average = avg.average();

                    if (sample.humidity > average + spike_diff) {
                        // We have exceeded the acceptable humidity, so we can
                        // close the relay.
                        std.log.info(
                            "relative humidity above {d:.1}% + {d:.1}%, turning on fan",
                            .{ average, spike_diff },
                        );
                        relay_status = .closed;
                    }
                },
            }
        }
    }
}
