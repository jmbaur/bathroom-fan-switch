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

    var sht3x = SHT3x{ .i2c_instance = i2c0 };

    sht3x.reset();

    while (true) {
        defer rp2xxx.time.sleep_ms(1000);

        const sample = sht3x.sample() catch |err| {
            std.log.err("failed to sample: {}", .{err});
            continue;
        };

        std.log.info("temperature: {d}°C", .{std.math.round(sample.temperature)});
        std.log.info("relative humidity: {d}%", .{std.math.round(sample.humidity)});
    }
}
