const std = @import("std");
const microzig = @import("microzig");

const SHT3x = @import("./sht3x.zig");

const time = microzig.drivers.time;
const rp2xxx = microzig.hal;
const i2c = rp2xxx.i2c;
const gpio = rp2xxx.gpio;

pub const microzig_options = microzig.Options{
    .log_level = .info,
    .logFn = rp2xxx.uart.logFn,
};

const uart = rp2xxx.uart.instance.UART0;
const baud_rate = 115200;
const uart_tx_pin = gpio.num(0);
const uart_rx_pin = gpio.num(1);

const i2c0 = i2c.instance.I2C0;

const relay = gpio.num(16);

fn RollingAverage(T: type, max_values: usize) type {
    const val_is_float = switch (T) {
        f64, f32, f16 => true,
        else => false,
    };

    return struct {
        num_values: usize = 0,
        current_average: f64 = 0,

        fn store(self: *@This(), value: T) void {
            if (self.num_values >= max_values) {
                self.num_values = 0;
                self.current_average = 0;
            }

            self.num_values += 1;
            self.current_average = self.current_average + (@as(f64, if (val_is_float) value else @floatFromInt(value)) - self.current_average) / @as(f64, @floatFromInt(self.num_values));
        }
    };
}

test {
    var avg = RollingAverage(usize, 100){};

    for (0..100) |value| {
        avg.store(value);
    }
    try std.testing.expectEqual(49.5, avg.current_average);

    avg.store(101);
    try std.testing.expectEqual(101, avg.current_average);
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

    const sda_pin = gpio.num(4);
    const scl_pin = gpio.num(5);
    inline for (&.{ sda_pin, scl_pin }) |pin| {
        pin.set_slew_rate(.slow);
        pin.set_schmitt_trigger(.enabled);
        pin.set_function(.i2c);
    }

    try i2c0.apply(.{ .clock_config = rp2xxx.clock_config });

    relay.set_direction(.out);
    relay.set_function(.sio);

    var sht3x = SHT3x{ .i2c_instance = i2c0 };

    while (true) {
        if (sht3x.reset()) {
            break;
        } else |err| {
            std.log.err("failed to reset SHT3x: {}", .{err});
            rp2xxx.time.sleep_ms(5000);
        }
    }

    var fan_on = false;

    var avg = RollingAverage(f64, 100){};

    while (true) {
        defer rp2xxx.time.sleep_ms(5000);

        const sample = sht3x.sample() catch |err| {
            std.log.err("failed to sample: {}", .{err});
            continue;
        };

        std.log.info("temperature: {d}°C", .{std.math.round(sample.temperature)});
        std.log.info("relative humidity: {d}%", .{std.math.round(sample.humidity)});

        if (fan_on and avg.current_average + dip_diff >= sample.humidity) {
            fan_on = false;
        } else if (sample.humidity > avg.current_average + spike_diff) {
            fan_on = true;
        } else if (!fan_on) {
            avg.store(sample.humidity);
        }

        relay.put(@intFromBool(fan_on));
    }
}
