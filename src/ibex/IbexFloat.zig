const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const ByteReader = ibex.ByteReader;
const ByteWriter = ibex.ByteWriter;
const IbexInt = @import("./IbexInt.zig");

fn floatCodec(comptime T: type) type {
    return T;
}

fn intCodec(comptime T: type) type {
    const info = @typeInfo(T).int;
    const max_exp = switch (info.signedness) {
        .signed => info.bits - 1,
        .unsigned => info.bits,
    };

    return struct {
        pub fn encodedLength(value: T) usize {
            if (value == 0)
                return 1;
            if (value < 0) {
                if (value == std.math.minInt(T))
                    return 1 + IbexInt.encodedLength(max_exp) + 1;
                return encodedLength(-value);
            }
            const hi_bit = info.bits - @clz(value) - 1; // drop MSB
            const lo_bit = @ctz(value);
            const bytes = @max(1, (hi_bit - lo_bit + 6) / 7);
            return 1 + IbexInt.encodedLength(hi_bit) + bytes;
        }

        fn writeInt(w: *ByteWriter, value: T) IbexError!void {
            const hi_bit = info.bits - @clz(value) - 1; // drop MSB
            const lo_bit = @ctz(value);
            const bytes: u16 = @max(1, (hi_bit - lo_bit + 6) / 7);
            // std.debug.print("\nhi={d}, lo={d}, bytes={d}\n", .{ hi_bit, lo_bit, bytes });

            try IbexInt.write(w, hi_bit); // exp

            for (0..bytes) |i| {
                const shift: i32 = @as(i32, @intCast(hi_bit - i * 7)) - 8;
                const shifted = if (shift >= 0) value >> @intCast(shift) else value << @intCast(-shift);
                var bits = shifted & 0xfe;
                if (i < bytes - 1) bits |= 1;
                // std.debug.print("byte={d}, shift={d}, bits={x}\n", .{ i, shift, bits });
                try w.put(@intCast(bits));
            }
        }

        pub fn write(w: *ByteWriter, value: T) IbexError!void {
            if (value == 0) {
                try w.put(@intFromEnum(IbexTag.FloatPosZero));
            } else if (value < 0) {
                try w.put(@intFromEnum(IbexTag.FloatNeg));
                w.negate();
                defer w.negate();
                if (value == std.math.minInt(T)) {
                    // Special case minInt
                    try IbexInt.write(w, max_exp);
                    try w.put(0x00);
                } else {
                    try writeInt(w, -value);
                }
            } else {
                try w.put(@intFromEnum(IbexTag.FloatPos));
                try writeInt(w, value);
            }
        }

        fn readIntBits(r: *ByteReader, exp: i64) IbexError!T {
            if (exp >= max_exp)
                return IbexError.Overflow;
            var acc: T = @as(T, 1) << @intCast(exp);
            var shift = exp - 8;
            while (true) : (shift -= 7) {
                const nb = try r.next();
                const bits: T = nb & 0xfe;
                if (shift >= -8)
                    acc |= if (shift >= 0) bits << @intCast(shift) else bits >> @intCast(-shift);
                if (nb & 0x01 == 0)
                    break;
            }
            return acc;
        }

        fn readPosInt(r: *ByteReader) IbexError!T {
            const exp = try IbexInt.read(r);
            return readIntBits(r, exp);
        }

        fn readNegInt(r: *ByteReader) IbexError!T {
            if (info.signedness == .unsigned)
                return IbexError.Overflow;
            r.negate();
            defer r.negate();
            const exp = try IbexInt.read(r);
            if (exp == max_exp) {
                const nb = try r.next();
                return if (nb == 0) std.math.minInt(T) else IbexError.Overflow;
            }
            return -try readIntBits(r, exp);
        }

        pub fn read(r: *ByteReader) IbexError!T {
            const nb = try r.next();
            const tag: IbexTag = @enumFromInt(nb);
            return switch (tag) {
                .FloatPosZero, .FloatNegZero => 0,
                .FloatPos => readPosInt(r),
                .FloatNeg => readNegInt(r),
                .FloatNegInf, .FloatPosInf => IbexError.Overflow,
                .FloatNegNaN, .FloatPosNaN => IbexError.Overflow,
                else => IbexError.InvalidData,
            };
        }
    };
}

pub fn IbexFloat(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => floatCodec(T),
        .int => intCodec(T),
        else => unreachable,
    };
}

fn TV(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        buf: [size]T = undefined,
        pos: usize = 0,

        pub fn put(self: *Self, value: T) void {
            assert(self.pos < size);
            self.buf[self.pos] = value;
            self.pos += 1;
        }

        pub fn slice(self: *const Self) []const T {
            return self.buf[0..self.pos];
        }
    };
}

const TVSize = 10;

fn testVectorInt(comptime T: type) TV(T, TVSize) {
    var tv = TV(T, TVSize){};
    tv.put(0);
    if (std.math.minInt(T) != 0)
        tv.put(std.math.minInt(T));
    tv.put(std.math.maxInt(T));
    return tv;
}

fn testVector(comptime T: type) TV(T, TVSize) {
    return switch (@typeInfo(T)) {
        .int => testVectorInt(T),
        else => unreachable,
    };
}

fn checkFloat(bytes: []const u8) void {
    var r = ByteReader{ .buf = bytes };
    defer assert(r.eof());
    const nb = r.next() catch unreachable;
    const tag: IbexTag = @enumFromInt(nb);
    switch (tag) {
        .FloatPos => {},
        .FloatNeg => r.negate(),
        .FloatPosZero, .FloatNegZero, .FloatNegInf => return,
        .FloatPosInf, .FloatNegNaN, .FloatPosNaN => return,
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

test IbexFloat {
    const types = [_]type{ u8, i9, i13, i32, u33, u32, u64, u1024, i1024 };
    inline for (types) |T| {
        // std.debug.print("=== {any} ===\n", .{T});
        const IF = IbexFloat(T);
        const tv = testVector(T);
        for (tv.slice()) |value| {
            var buf: [256]u8 = undefined;
            var w = ByteWriter{ .buf = &buf };
            try IF.write(&w, value);
            try std.testing.expectEqual(w.pos, IF.encodedLength(value));
            // std.debug.print("{d} -> {any}\n", .{ value, w.slice() });
            checkFloat(w.slice());
            var r = ByteReader{ .buf = w.slice() };
            try std.testing.expectEqual(value, try IF.read(&r));
        }
    }
}
