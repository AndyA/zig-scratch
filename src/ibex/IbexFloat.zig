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
    const min_int = std.math.minInt(T);

    return struct {
        pub fn encodedLength(value: T) usize {
            if (value == 0)
                return 1;
            if (value < 0) {
                if (value == min_int)
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
            const bytes: u16 = (hi_bit - lo_bit + 6) / 7;
            try IbexInt.write(w, hi_bit); // exp

            if (bytes == 0) {
                // Special case empty mantissa
                try w.put(0x00);
            } else {
                for (0..bytes) |i| {
                    const shift: i32 = @as(i32, @intCast(hi_bit - i * 7)) - 8;
                    const shifted = if (shift >= 0) value >> @intCast(shift) else value << @intCast(-shift);
                    var bits = shifted & 0xfe;
                    if (i < bytes - 1) bits |= 1;
                    try w.put(@intCast(bits));
                }
            }
        }

        pub fn write(w: *ByteWriter, value: T) IbexError!void {
            if (value == 0) {
                try w.put(@intFromEnum(IbexTag.FloatPosZero));
            } else if (value < 0) {
                try w.put(@intFromEnum(IbexTag.FloatNeg));
                w.negate();
                defer w.negate();
                if (value == min_int) {
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
            // std.debug.print(
            //     "T={any}, exp={d}, acc=0x{x}, shift={d}\n",
            //     .{ T, exp, acc, shift },
            // );

            while (true) : (shift -= 7) {
                const nb = try r.next();
                const bits: T = nb & 0xfe;
                // std.debug.print("shift={d}\n", .{shift});
                if (shift > -8)
                    acc |= if (shift >= 0) bits << @intCast(shift) else bits >> @intCast(-shift);
                if (nb & 0x01 == 0) {
                    // Detect non-canonical encoding
                    if (nb == 0 and shift != exp - 8)
                        return IbexError.InvalidData;
                    break;
                }
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
                return if (nb == 0) min_int else IbexError.Overflow;
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

const TVSize = 100;

fn testVectorInt(comptime T: type) TV(T, TVSize) {
    const min_int = std.math.minInt(T);
    const max_int = std.math.maxInt(T);
    const info = @typeInfo(T).int;
    var tv = TV(T, TVSize){};

    var small: T = 0;
    while (small < @min(15, max_int)) : (small += 1) {
        tv.put(small);
        tv.put(max_int - small);
        if (info.signedness == .signed) {
            tv.put(-small);
            tv.put(min_int + small);
        }
    }

    // std.debug.print("{any}: {any}\n", .{ T, tv.slice() });

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
