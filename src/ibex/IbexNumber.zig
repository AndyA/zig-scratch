const std = @import("std");
const intCodec = @import("./IbexNumber/int.zig").intCodec;
const floatCodec = @import("./IbexNumber/float.zig").floatCodec;

pub fn IbexNumber(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => floatCodec(T),
        .int => intCodec(T),
        else => unreachable,
    };
}

fn testRoundTrip(comptime TWrite: type, comptime TRead: type, value: comptime_float) !void {
    const ibex = @import("./ibex.zig");

    var buf: [256]u8 = undefined;
    var w = ibex.ByteWriter{ .buf = &buf };
    try IbexNumber(TWrite).write(&w, value);

    var r = ibex.ByteReader{ .buf = w.slice() };
    const got = try IbexNumber(TRead).read(&r);
    const fgot: f128 = switch (@typeInfo(TRead)) {
        .int => @floatFromInt(got),
        .float => @floatCast(got),
        else => unreachable,
    };
    try std.testing.expectEqual(@as(f128, @floatCast(value)), fgot);
}

test IbexNumber {
    try testRoundTrip(u8, f32, 1.0);
    try testRoundTrip(f32, u8, 1.0);
}
