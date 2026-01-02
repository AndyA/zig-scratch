const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("./ibex.zig");
const ByteReader = ibex.ByteReader;
const ByteWriter = ibex.ByteWriter;

const BIAS = 0x80;
const LIN_LO = 0x08;
const LIN_HI = 0xf8;
const MAX_BYTES = LIN_LO + 1;
const MAX_ENCODED: i64 = 0x7efefefefefefe87;

const LIMITS: [MAX_BYTES]i72 = blk: {
    var limits: [MAX_BYTES]i72 = undefined;

    var limit: i72 = LIN_HI - BIAS;
    for (1..MAX_BYTES) |len| {
        limits[len - 1] = limit;
        limit += @as(i72, 1) << (@as(u7, @intCast(len)) * 8);
    }

    limits[MAX_BYTES - 1] = limit;

    break :blk limits;
};

pub fn IbexInt(comptime T: type) type {
    return struct {
        fn repLength(tag: u8) usize {
            if (tag >= LIN_HI)
                return tag - LIN_HI + 1
            else if (tag < LIN_LO)
                return LIN_LO - tag
            else
                return 1;
        }

        fn readBytes(r: *ByteReader, bytes: usize, comptime flip: u8) T {
            assert(bytes < MAX_BYTES);
            var acc: T = 0;
            for (0..bytes) |_| {
                acc = (acc << 8) + (r.next() ^ flip);
            }
            return acc;
        }

        pub fn read(r: *ByteReader) T {
            const nb = r.next();
            const bytes = repLength(nb);
            if (nb >= LIN_HI) {
                return LIMITS[bytes - 1] + readBytes(r, bytes, 0x00);
            } else if (nb < LIN_LO) {
                return ~(LIMITS[bytes - 1] + readBytes(r, bytes, 0xff));
            } else {
                return @as(T, @intCast(nb)) - BIAS;
            }
        }

        fn writeBytes(w: *ByteWriter, bytes: usize, value: T) void {
            assert(bytes < MAX_BYTES);
            for (0..bytes) |i| {
                const pos: u7 = @intCast(bytes - 1 - i);
                const byte: u8 = @intCast((value >> (pos * 8)) & 0xff);
                w.put(byte);
            }
        }

        pub fn write(w: *ByteWriter, value: T) void {
            const bytes = length(value) - 1;
            if (bytes == 0) {
                w.put(@intCast(value + BIAS));
            } else if (value >= 0) {
                w.put(@intCast(bytes - 1 + LIN_HI));
                writeBytes(w, bytes, value - LIMITS[bytes]);
            } else {
                w.put(@intCast(LIN_LO - bytes));
                writeBytes(w, bytes, value + LIMITS[bytes]);
            }
        }

        pub fn length(value: T) usize {
            const abs = if (value < 0) ~value else value;
            inline for (LIMITS, 1..) |limit, len| {
                if (abs < limit)
                    return len;
            }
            unreachable;
        }
    };
}

test "read" {
    for (test_cases) |tc| {
        const ii = IbexInt(i72);
        var r = ByteReader{ .buf = tc.buf, .flip = tc.flip };
        try std.testing.expectEqual(tc.want, ii.read(&r));
        try std.testing.expectEqual(tc.buf.len, r.pos);
    }
}

test "write" {
    for (test_cases) |tc| {
        const ii = IbexInt(i72);
        var buf: [9]u8 = undefined;
        var w = ByteWriter{ .buf = &buf, .flip = tc.flip };
        ii.write(&w, tc.want);
        try std.testing.expectEqualDeep(tc.buf, w.slice());
        try std.testing.expectEqual(tc.buf.len, w.pos);
    }
}

test "length" {
    for (test_cases) |tc| {
        const ii = IbexInt(i72);
        try std.testing.expectEqual(tc.buf.len, ii.length(tc.want));
    }
}

test "round trip" {
    var buf: [9]u8 = undefined;
    const ii = IbexInt(i72);
    for (0..140000) |offset| {
        const value = @as(i72, @intCast(offset)) - 70000;
        var w = ByteWriter{ .buf = &buf };
        ii.write(&w, value);
        try std.testing.expectEqual(w.pos, ii.length(value));
        var r = ByteReader{ .buf = w.slice() };
        const got = ii.read(&r);
        try std.testing.expectEqual(value, got);
    }
}

// fn testFoo(value: i72) void {
//     var buf: [9]u8 = undefined;
//     const ii = IbexInt(i72);
//     var w = ByteWriter{ .buf = &buf };
//     ii.write(&w, value);
//     std.debug.print("{d} => {any}\n", .{ value, w.slice() });
// }

// test "foo" {
//     testFoo(std.math.maxInt(i64));
//     testFoo(std.math.minInt(i64));
// }

const TestCase = struct { buf: []const u8, flip: u8 = 0x00, want: i72 };
const test_cases = &[_]TestCase{
    .{
        .buf = &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .want = -18519084246547628408,
    },
    .{
        .buf = &.{ 0x00, 0x81, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x78 },
        .want = -9223372036854775808, // minInt(i64)
    },
    .{
        .buf = &.{ 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        .want = -72340172838076793,
    },
    .{
        .buf = &.{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .want = -72340172838076792,
    },
    .{ .buf = &.{ 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -282578800148857 },
    .{ .buf = &.{ 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -282578800148856 },
    .{ .buf = &.{ 0x02, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -1103823438201 },
    .{ .buf = &.{ 0x03, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -1103823438200 },
    .{ .buf = &.{ 0x03, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -4311810425 },
    .{ .buf = &.{ 0x04, 0x00, 0x00, 0x00, 0x00 }, .want = -4311810424 },
    .{ .buf = &.{ 0x04, 0xff, 0xff, 0xff, 0xff }, .want = -16843129 },
    .{ .buf = &.{ 0x05, 0x00, 0x00, 0x00 }, .want = -16843128 },
    .{ .buf = &.{ 0x05, 0xff, 0xff, 0xff }, .want = -65913 },
    .{ .buf = &.{ 0x06, 0x00, 0x00 }, .want = -65912 },
    .{ .buf = &.{ 0x06, 0xff, 0xfe }, .want = -378 },
    .{ .buf = &.{ 0x06, 0xff, 0xff }, .want = -377 },
    .{ .buf = &.{ 0x07, 0x00 }, .want = -376 },
    .{ .buf = &.{ 0x07, 0xff }, .want = -121 },
    .{ .buf = &.{0x08}, .want = -120 },
    .{ .buf = &.{0x7f}, .want = -1 },
    .{ .buf = &.{0x80}, .want = 0 },
    .{ .buf = &.{0x81}, .want = 1 },
    .{ .buf = &.{0xf7}, .want = 119 },
    .{ .buf = &.{ 0xf8, 0x00 }, .want = 120 },
    .{ .buf = &.{ 0xf8, 0xff }, .want = 375 },
    .{ .buf = &.{ 0xf9, 0x00, 0x00 }, .want = 376 },
    .{ .buf = &.{ 0xf9, 0x00, 0x01 }, .want = 377 },
    .{ .buf = &.{ 0xf9, 0x01, 0x00 }, .want = 632 },
    .{ .buf = &.{ 0xf9, 0xff, 0xff }, .want = 65911 },
    .{ .buf = &.{ 0xfa, 0x00, 0x00, 0x00 }, .want = 65912 },
    .{ .buf = &.{ 0xfa, 0xff, 0xff, 0xff }, .want = 16843127 },
    .{ .buf = &.{ 0xfb, 0x00, 0x00, 0x00, 0x00 }, .want = 16843128 },
    .{ .buf = &.{ 0xfb, 0xff, 0xff, 0xff, 0xff }, .want = 4311810423 },
    .{ .buf = &.{ 0xfc, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 4311810424 },
    .{ .buf = &.{ 0xfc, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 1103823438199 },
    .{ .buf = &.{ 0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 1103823438200 },
    .{ .buf = &.{ 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 282578800148855 },
    .{ .buf = &.{ 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 282578800148856 },
    .{
        .buf = &.{ 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        .want = 72340172838076791,
    },
    .{
        .buf = &.{ 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        .want = 72340172838076792,
    },
    .{
        .buf = &.{ 0xff, 0x7e, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0xfe, 0x87 },
        .want = 9223372036854775807, // maxInt(i64)
    },
    .{
        .buf = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff },
        .want = 18519084246547628407,
    },
};
