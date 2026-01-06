const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const ByteReader = ibex.ByteReader;
const IbexInt = @import("../IbexInt.zig");

pub fn TestVec(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        buf: [size]T = undefined,
        pos: usize = 0,

        pub fn has(self: *const Self, value: T) bool {
            for (self.slice()) |v| {
                if (v == value) return true;
            }
            return false;
        }

        pub fn put(self: *Self, value: T) void {
            if (!self.has(value)) {
                assert(self.pos < size);
                self.buf[self.pos] = value;
                self.pos += 1;
            }
        }

        pub fn slice(self: *const Self) []const T {
            return self.buf[0..self.pos];
        }
    };
}

pub fn checkFloat(bytes: []const u8) void {
    var r = ByteReader{ .buf = bytes };
    defer assert(r.eof());
    const nb = r.next() catch unreachable;
    const tag: IbexTag = @enumFromInt(nb);
    switch (tag) {
        .FloatPos => {},
        .FloatNeg => r.negate(),
        .FloatPosZero, .FloatPosInf, .FloatPosNaN => return,
        .FloatNegZero, .FloatNegInf, .FloatNegNaN => return,
        else => unreachable,
    }
    _ = IbexInt.read(&r) catch unreachable;
    var first = true;
    while (true) : (first = false) {
        const mb = r.next() catch unreachable;
        assert(first or mb != 0);
        if (mb & 0x01 == 0) break;
    }
}
