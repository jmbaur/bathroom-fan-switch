const std = @import("std");
const microzig = @import("microzig");

const Duration = microzig.drivers.time.Duration;
const time = microzig.hal.time;
const i2c = microzig.hal.i2c;

const Sample = struct {
    temperature: f64,
    humidity: f64,
};

pub const Command = enum {
    MeasureHighrepStretch,
    MeasureMedrepStretch,
    MeasureLowrepStretch,
    MeasureHighrep,
    MeasureMidrep,
    MeasureLowrep,
    ReadStatus,
    ClearStatus,
    SoftReset,
    HeaterEnable,
    HeaterDisable,
};

const SHT3x = @This();

const i2c_addr: i2c.Address = @enumFromInt(0x44);

i2c_instance: i2c.I2C,

pub fn reset(self: *SHT3x) !void {
    try self.write_command(SHT3x.Command.SoftReset);
    time.sleep_ms(10);
}

fn write_command(self: *SHT3x, command: Command) !void {
    const data: [2]u8 = switch (command) {
        .MeasureHighrepStretch => .{ 0x2c, 0x06 },
        .MeasureMedrepStretch => .{ 0x2c, 0x0d },
        .MeasureLowrepStretch => .{ 0x2c, 0x10 },
        .MeasureHighrep => .{ 0x24, 0x00 },
        .MeasureMidrep => .{ 0x24, 0x0b },
        .MeasureLowrep => .{ 0x24, 0x16 },
        .ReadStatus => .{ 0xf3, 0x2d },
        .ClearStatus => .{ 0x30, 0x41 },
        .SoftReset => .{ 0x30, 0xa2 },
        .HeaterEnable => .{ 0x30, 0x6d },
        .HeaterDisable => .{ 0x30, 0x66 },
    };

    try self.i2c_instance.write_blocking(
        i2c_addr,
        &data,
        Duration.from_ms(100),
    );
}

pub fn sample(self: *SHT3x) !Sample {
    var s = Sample{
        .temperature = 0,
        .humidity = 0,
    };

    try self.write_command(SHT3x.Command.MeasureHighrep);
    time.sleep_ms(500);

    var rx_data: [6]u8 = undefined;
    _ = try self.i2c_instance.read_blocking(
        SHT3x.i2c_addr,
        &rx_data,
        Duration.from_ms(100),
    );

    if (std.hash.crc.Crc8Nrsc5.hash(rx_data[0..2]) != rx_data[2]) {
        return error.CRC;
    } else {
        const sensor_temperature: u16 = (@as(u16, rx_data[0]) << 8) | rx_data[1];
        const temperature_celcius: f64 = -45 + (175 * @as(f64, @floatFromInt(sensor_temperature)) / ((1 << 16) - 1));
        s.temperature = temperature_celcius;
    }

    if (std.hash.crc.Crc8Nrsc5.hash(rx_data[3..5]) != rx_data[5]) {
        return error.CRC;
    } else {
        const sensor_humidity: u16 = (@as(u16, rx_data[3]) << 8) | rx_data[4];
        const relative_humidity: f64 = 100 * @as(f64, @floatFromInt(sensor_humidity)) / ((1 << 16) - 1);
        s.humidity = relative_humidity;
    }

    return s;
}
