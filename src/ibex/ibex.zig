const std = @import("std");
const assert = std.debug.assert;

// Ibex and Oryx

pub const IbexTag = enum(u8) {
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

    // Additional Oryx encodings
    OryxInt = 0x0f, // value: IbexInt
    OryxString = 0x10, // len: IbexInt, str: []u8
    OryxClass = 0x11, // parent: IbexInt, len: IbexInt, keys: []{len: IbexInt, str: []u8}
    OryxArray = 0x12, // len: IbexInt, values: []IbexValue
    OryxObject = 0x13, // class: IbexInt, len: IbexInt, values: []IbexValue

    pub fn indexSafe(tag: IbexTag) bool {
        return @intFromEnum(tag) < @intFromEnum(IbexTag.OryxInt);
    }
};

test IbexTag {
    try std.testing.expect(IbexTag.indexSafe(.Object));
    try std.testing.expect(!IbexTag.indexSafe(.OryxInt));
}

pub const IbexError = error{
    InvalidData,
    Overflow,
    BufferFull,
    BufferEmpty,
};
