const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
    Nop = 0x00, // padding maybe

    End, // end of Object / Array - sorts before anything else

    Null,
    False,
    True,
    String,

    FloatNegNaN = 0x08,
    FloatNegInf,
    FloatNeg,
    FloatNegZero,
    FloatPosZero,
    FloatPos,
    FloatPosInf,
    FloatPosNaN,

    Array = 0x10,
    Object,
};

test IbexTag {
    try std.testing.expectEqual(0x08, @intFromEnum(IbexTag.FloatNegNaN));
    try std.testing.expectEqual(0x0f, @intFromEnum(IbexTag.FloatPosNaN));
}

pub const IbexError = error{
    InvalidData,
    Overflow,
    BufferFull,
    BufferEmpty,
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

    pub fn next(self: *Self) IbexError!u8 {
        if (self.eof())
            return IbexError.BufferEmpty;
        defer self.pos += 1;
        return self.peek();
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }
};

pub const ByteWriter = struct {
    const Self = @This();
    buf: []u8,
    flip: u8 = 0x00,
    pos: usize = 0,

    pub fn put(self: *Self, b: u8) IbexError!void {
        assert(self.pos <= self.buf.len);
        if (self.pos == self.buf.len)
            return IbexError.BufferFull;
        defer self.pos += 1;
        self.buf[self.pos] = b ^ self.flip;
    }

    pub fn slice(self: *const Self) []const u8 {
        return self.buf[0..self.pos];
    }

    pub fn negate(self: *Self) void {
        self.flip = ~self.flip;
    }
};
