const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
    pub const OryxBase = @intFromEnum(IbexTag.OryxString);

    End = 0x00, // end of Object / Array - sorts before anything else

    Null = 0x01,
    False = 0x02,
    True = 0x03,
    String = 0x04,

    NumNegNaN = 0x05,
    NumNegInf = 0x06,
    NumNeg = 0x07,
    NumNegZero = 0x08,
    NumPosZero = 0x09,
    NumPos = 0x0a,
    NumPosInf = 0x0b,
    NumPosNaN = 0x0c,

    Array = 0x0d,
    Object = 0x0e,

    Nop = 0x0f,

    // Additional Oryx encodings
    OryxString = 0x10, // len: IbexInt, str: []u8
    OryxClass = 0x11, // parent: IbexInt, len: IbexInt, keys: []String
    OryxInt = 0x12, // IbexInt
    OryxArray = 0x13, // len: IbexInt, values: []IbexValue
    OryxObject = 0x14, // class: IbexInt, len: IbexInt, values: []IbexValue

    pub fn indexSafe(tag: IbexTag) bool {
        return @intFromEnum(tag) < OryxBase;
    }
};

test IbexTag {
    try std.testing.expect(IbexTag.indexSafe(.Object));
    try std.testing.expect(!IbexTag.indexSafe(.OryxString));
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
