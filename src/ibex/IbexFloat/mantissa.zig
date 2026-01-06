const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const ByteReader = ibex.ByteReader;
const ByteWriter = ibex.ByteWriter;
const FloatValue = @import("./float_bits.zig").FloatValue;
const IbexInt = @import("../IbexInt.zig");

fn sizeInBytes(comptime T: type, mant: T) u16 {
    const sig_bits = @typeInfo(T).int.bits - @ctz(mant);
    return (sig_bits + 6) / 7;
}

pub fn mantissaLength(comptime T: type, mant: T) usize {
    return @max(1, sizeInBytes(T, mant));
}

pub fn writeMantissa(comptime T: type, w: *ByteWriter, mant: T) IbexError!void {
    const info = @typeInfo(T).int;
    assert(info.signedness == .unsigned);
    const len = sizeInBytes(T, mant);
    // std.debug.print("mant={x}, sig_bits={d}, bytes={d}\n", .{ mant, sig_bits, bytes });
    if (len == 0)
        return w.put(0x00);

    var shift: i32 = @as(i32, @intCast(info.bits)) - 8;

    const mant_bits: @Int(.unsigned, @max(8, info.bits)) = @intCast(mant);

    for (0..len) |i| {
        const part = if (shift >= 0)
            mant_bits >> @intCast(shift)
        else
            mant_bits << @intCast(-shift);
        var byte = part & 0xfe;
        if (i < len - 1) byte |= 1;
        try w.put(@intCast(byte));
        shift -= 7;
    }
}

test writeMantissa {
    const TestCase = struct {
        T: type,
        mant: comptime_int,
        want: []const u8,
    };

    const cases = &[_]TestCase{
        .{ .T = u16, .mant = 0, .want = &.{0x00} },
        .{ .T = u8, .mant = 0x80, .want = &.{0x80} },
        .{ .T = u8, .mant = 0xff, .want = &.{ 0xff, 0x80 } },
        .{ .T = u8, .mant = 0x81, .want = &.{ 0x81, 0x80 } },
        .{ .T = u9, .mant = 0x102, .want = &.{ 0x81, 0x80 } },
        .{ .T = u1, .mant = 0x1, .want = &.{0x80} },
    };

    inline for (cases) |tc| {
        var buf: [256]u8 = undefined;
        var w = ByteWriter{ .buf = &buf };
        try writeMantissa(tc.T, &w, tc.mant);
        // std.debug.print("T={any}, m={x} encoded={any}\n", .{ tc.T, tc.mant, w.slice() });
        try std.testing.expectEqual(w.pos, mantissaLength(tc.T, tc.mant));
        try std.testing.expectEqualDeep(tc.want, w.slice());
    }
}
