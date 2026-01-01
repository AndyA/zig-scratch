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

pub fn IbexInt(comptime T: type) !type {
    const BIAS = 0x80;
    const LIN_LO = 0x08;
    const LIN_HI = 0xf8;
    const POS_BIAS = LIN_HI - BIAS;
    const NEG_BIAS = LIN_LO - BIAS;
    const MAX_BYTES = LIN_LO + 1;

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
                return POS_BIAS - 1 + (acc + adj);
            } else if (nb < LIN_LO) {
                const extra = LIN_LO - 1 - nb;
                var adj: T = 1;
                var acc: T = 0;
                for (0..extra) |_| {
                    acc = (acc << 8) + (r.next() ^ 0xff);
                    adj = (adj << 8) + 1;
                }
                acc = (acc << 8) + (r.next() ^ 0xff);
                return NEG_BIAS - (acc + adj);
            } else {
                return @as(T, @intCast(nb)) - BIAS;
            }
        }

        pub fn length(value: T) usize {
            if (value >= 0) {
                var limit: i72 = POS_BIAS;
                inline for (1..MAX_BYTES) |len| {
                    if (value < limit)
                        return len;
                    limit += @as(i72, 1) << (@as(u7, @intCast(len)) * 8);
                }
                if (value < limit)
                    return MAX_BYTES;
            } else {
                var limit: i72 = NEG_BIAS;
                inline for (1..MAX_BYTES) |len| {
                    if (value >= limit)
                        return len;
                    limit -= @as(i72, 1) << (@as(u7, @intCast(len)) * 8);
                }
                if (value >= limit)
                    return MAX_BYTES;
            }
            unreachable;
        }
    };
}

test "IbexInt.read" {
    for (int_test_cases) |tc| {
        const ii = try IbexInt(i72);
        var r = ByteReader{ .bytes = tc.bytes, .flip = tc.flip };
        try std.testing.expectEqual(tc.want, ii.read(&r));
        try std.testing.expectEqual(tc.bytes.len, r.pos);
    }
}

test "IbexInt.length" {
    for (int_test_cases) |tc| {
        const ii = try IbexInt(i72);
        try std.testing.expectEqual(tc.bytes.len, ii.length(tc.want));
    }
}

const IntTestCase = struct { bytes: []const u8, flip: u8 = 0x00, want: i72 };
const int_test_cases = &[_]IntTestCase{
    .{ .bytes = &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -18519084246547628408 },
    .{ .bytes = &.{ 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -72340172838076793 },
    .{ .bytes = &.{ 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -72340172838076792 },
    .{ .bytes = &.{ 0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -282578800148857 },
    .{ .bytes = &.{ 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -282578800148856 },
    .{ .bytes = &.{ 0x02, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -1103823438201 },
    .{ .bytes = &.{ 0x03, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = -1103823438200 },
    .{ .bytes = &.{ 0x03, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = -4311810425 },
    .{ .bytes = &.{ 0x04, 0x00, 0x00, 0x00, 0x00 }, .want = -4311810424 },
    .{ .bytes = &.{ 0x04, 0xff, 0xff, 0xff, 0xff }, .want = -16843129 },
    .{ .bytes = &.{ 0x05, 0x00, 0x00, 0x00 }, .want = -16843128 },
    .{ .bytes = &.{ 0x05, 0xff, 0xff, 0xff }, .want = -65913 },
    .{ .bytes = &.{ 0x06, 0x00, 0x00 }, .want = -65912 },
    .{ .bytes = &.{ 0x06, 0xff, 0xff }, .want = -377 },
    .{ .bytes = &.{ 0x07, 0x00 }, .want = -376 },
    .{ .bytes = &.{ 0x07, 0xff }, .want = -121 },
    .{ .bytes = &.{0x08}, .want = -120 },
    .{ .bytes = &.{0x7f}, .want = -1 },
    .{ .bytes = &.{0x80}, .want = 0 },
    .{ .bytes = &.{0x81}, .want = 1 },
    .{ .bytes = &.{0xf7}, .want = 119 },
    .{ .bytes = &.{ 0xf8, 0x00 }, .want = 120 },
    .{ .bytes = &.{ 0xf8, 0xff }, .want = 375 },
    .{ .bytes = &.{ 0xf9, 0x00, 0x00 }, .want = 376 },
    .{ .bytes = &.{ 0xf9, 0xff, 0xff }, .want = 65911 },
    .{ .bytes = &.{ 0xfa, 0x00, 0x00, 0x00 }, .want = 65912 },
    .{ .bytes = &.{ 0xfa, 0xff, 0xff, 0xff }, .want = 16843127 },
    .{ .bytes = &.{ 0xfb, 0x00, 0x00, 0x00, 0x00 }, .want = 16843128 },
    .{ .bytes = &.{ 0xfb, 0xff, 0xff, 0xff, 0xff }, .want = 4311810423 },
    .{ .bytes = &.{ 0xfc, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 4311810424 },
    .{ .bytes = &.{ 0xfc, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 1103823438199 },
    .{ .bytes = &.{ 0xfd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 1103823438200 },
    .{ .bytes = &.{ 0xfd, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 282578800148855 },
    .{ .bytes = &.{ 0xfe, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 282578800148856 },
    .{ .bytes = &.{ 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 72340172838076791 },
    .{ .bytes = &.{ 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }, .want = 72340172838076792 },
    .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, .want = 18519084246547628407 },
};
