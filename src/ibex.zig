const std = @import("std");
const assert = std.debug.assert;

pub const IbexTag = enum {
    End,
    Null,
    False,
    True,
    String,
    NegativeInfinity,
    Negative,
    NegativeZero,
    PositiveZero,
    Positive,
    PositiveInfinity,
    Array,
    Object,
};

pub const ByteReader = struct {
    const Self = @This();
    bytes: []const u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn eof(self: *const Self) bool {
        assert(self.pos <= self.bytes.len);
        return self.pos == self.bytes.len;
    }

    pub fn peek(self: *Self) u8 {
        assert(self.pos < self.bytes.len);
        return self.bytes[self.pos] ^ self.flip;
    }

    pub fn next(self: *Self) u8 {
        assert(self.pos < self.bytes.len);
        defer self.pos += 1;
        return self.peek();
    }
};

// 0xf9 0xXX 0xXX    => 0x000001f8 .. 0x000101f7
// 0xf8 0xXX         => 0x000000f8 .. 0x000001f7
// 0x08 .. 0xF7      => 0x00000008 .. 0x000000f7

pub fn IbexInt(comptime T: type) !type {
    const LIN_LO = 0x08;
    const LIN_HI = 0xf8;
    comptime {
        // const UT = switch (@typeInfo(T)) {
        //     .int => |info| ut: {
        //         if (info.signedness != .signed) return error.MustBeSignedInt;
        //         break :ut @Int(.unsigned, info.bits);
        //     },
        //     else => return error.MustBeSignedInt,
        // };
        return struct {
            pub fn read(r: *ByteReader) T {
                const nb = r.next();
                if (nb >= LIN_HI) {
                    const extra = nb - LIN_HI;
                    var adj: T = 1;
                    var acc: T = 0;
                    for (0..extra) |_| {
                        acc = (acc << 8) + r.next();
                        adj = (adj << 8) + 1;
                    }
                    acc = (acc << 8) + r.next();
                    return 119 + (acc + adj);
                } else if (nb < LIN_LO) {
                    const extra = 7 - nb;
                    var adj: T = 1;
                    var acc: T = 0;
                    for (0..extra) |_| {
                        acc = (acc << 8) + (r.next() ^ 0xff);
                        adj = (adj << 8) + 1;
                    }
                    acc = (acc << 8) + (r.next() ^ 0xff);
                    return -120 - (acc + adj);
                } else {
                    return @as(T, @intCast(nb)) - 0x80;
                }
            }
        };
    }
}

test IbexInt {
    const TC = struct { bytes: []const u8, flip: u8 = 0x00, want: i64 };
    const cases = &[_]TC{
        .{ .bytes = &.{ 0xfb, 0x00, 0x00, 0x00, 0x00 }, .want = 16843128 },
        .{ .bytes = &.{ 0xfa, 0xff, 0xff, 0xff }, .want = 16843127 },
        .{ .bytes = &.{ 0xfa, 0x00, 0x00, 0x00 }, .want = 65912 },
        .{ .bytes = &.{ 0xf9, 0xff, 0xff }, .want = 65911 },
        .{ .bytes = &.{ 0xf9, 0x00, 0x00 }, .want = 376 },
        .{ .bytes = &.{ 0xf8, 0xff }, .want = 375 },
        .{ .bytes = &.{ 0xf8, 0x00 }, .want = 120 },
        .{ .bytes = &.{0xf7}, .want = 119 },
        .{ .bytes = &.{0x81}, .want = 1 },
        .{ .bytes = &.{0x80}, .want = 0 },
        .{ .bytes = &.{0x7f}, .want = -1 },
        .{ .bytes = &.{0x08}, .want = -120 },
        .{ .bytes = &.{ 0x07, 0xff }, .want = -121 },
        .{ .bytes = &.{ 0x07, 0x00 }, .want = -376 },
        .{ .bytes = &.{ 0x06, 0xff, 0xff }, .want = -377 },
        .{ .bytes = &.{ 0x06, 0x00, 0x00 }, .want = -65912 },
        .{ .bytes = &.{ 0x05, 0xff, 0xff, 0xff }, .want = -65913 },
        .{ .bytes = &.{ 0x05, 0x00, 0x00, 0x00 }, .want = -16843128 },
        .{ .bytes = &.{ 0x04, 0xff, 0xff, 0xff, 0xff }, .want = -16843129 },
    };

    for (cases) |tc| {
        const ii = try IbexInt(i64);
        var r = ByteReader{ .bytes = tc.bytes, .flip = tc.flip };
        try std.testing.expectEqual(tc.want, ii.read(&r));
        try std.testing.expectEqual(tc.bytes.len, r.pos);
    }
}
