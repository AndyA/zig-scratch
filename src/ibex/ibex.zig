const std = @import("std");
const assert = std.debug.assert;

pub const IbexTag = enum(u8) {
    End, // end of Object / Array - sorts before anything else
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
    buf: []const u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn eof(self: *const Self) bool {
        assert(self.pos <= self.buf.len);
        return self.pos == self.buf.len;
    }

    pub fn peek(self: *Self) u8 {
        assert(self.pos < self.buf.len);
        return self.buf[self.pos] ^ self.flip;
    }

    pub fn next(self: *Self) u8 {
        assert(self.pos < self.buf.len);
        defer self.pos += 1;
        return self.peek();
    }
};

pub const ByteWriter = struct {
    const Self = @This();
    buf: []u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn put(self: *Self, b: u8) void {
        assert(self.pos < self.buf.len);
        defer self.pos += 1;
        self.buf[self.pos] = b ^ self.flip;
    }

    pub fn slice(self: *const Self) []const u8 {
        return self.buf[0..self.pos];
    }
};
