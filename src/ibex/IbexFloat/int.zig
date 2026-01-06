const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const ByteReader = ibex.ByteReader;
const ByteWriter = ibex.ByteWriter;
const IbexInt = @import("../IbexInt.zig");

pub fn intCodec(comptime T: type) type {
    const info = @typeInfo(T).int;
    const min_int = std.math.minInt(T);
    const max_int = std.math.maxInt(T);
    const max_exp = switch (info.signedness) {
        .signed => info.bits - 1,
        .unsigned => info.bits,
    };

    if (max_exp < 8) {
        // To simplify the generic code we special-case sub-byte encodings
        const Codec = intCodec(switch (info.signedness) {
            .signed => i9,
            .unsigned => u8,
        });

        return struct {
            pub fn encodedLength(value: T) usize {
                return Codec.encodedLength(value);
            }

            pub fn write(w: *ByteWriter, value: T) IbexError!void {
                try Codec.write(w, value);
            }

            pub fn read(r: *ByteReader) IbexError!T {
                const value = try Codec.read(r);
                if (value < min_int or value > max_int)
                    return IbexError.Overflow;
                return @intCast(value);
            }
        };
    }

    return struct {
        pub fn encodedLength(value: T) usize {
            if (value == 0)
                return 1;
            if (value < 0) {
                if (value == min_int)
                    return 1 + IbexInt.encodedLength(max_exp) + 1;
                return encodedLength(-value);
            }
            const msb = info.bits - @clz(value) - 1; // drop MSB
            const bytes = (msb - @ctz(value) + 6) / 7;
            return 1 + IbexInt.encodedLength(msb) + @max(1, bytes);
        }

        fn writeInt(w: *ByteWriter, value: T) IbexError!void {
            const msb = info.bits - @clz(value) - 1; // drop MSB
            const bytes: u16 = (msb - @ctz(value) + 6) / 7;
            try IbexInt.write(w, msb); // exp

            if (bytes == 0) {
                // Special case empty mantissa
                try w.put(0x00);
                return;
            }

            var shift = @as(i32, @intCast(msb)) - 8;
            for (0..bytes) |i| {
                const part = if (shift >= 0)
                    value >> @intCast(shift)
                else
                    value << @intCast(-shift);
                var bits = part & 0xfe;
                if (i < bytes - 1) bits |= 1;
                try w.put(@intCast(bits));
                shift -= 7;
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
                    acc |= if (shift >= 0)
                        bits << @intCast(shift)
                    else
                        bits >> @intCast(-shift);
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
                return switch (nb) {
                    0x00 => min_int,
                    else => IbexError.Overflow,
                };
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

const tt = @import("./test_tools.zig");

fn TV(comptime T: type) type {
    return tt.TestVec(T, 100);
}

fn intTestVector(comptime T: type) TV(T) {
    const min_int = math.minInt(T);
    const max_int = math.maxInt(T);
    const info = @typeInfo(T).int;
    const BT = @Int(info.signedness, info.bits + 1);
    var tv = TV(T){};

    var small: BT = 0;
    while (small < @min(15, max_int)) : (small += 1) {
        tv.put(@intCast(small));
        tv.put(@intCast(max_int - small));
        if (info.signedness == .signed) {
            tv.put(@intCast(-small));
            tv.put(@intCast(min_int + small));
        }
    }

    // std.debug.print("{any}: {any}\n", .{ T, tv.slice() });

    return tv;
}

test intCodec {
    const bit_lengths = //
        [_]usize{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 } ++ //
        [_]usize{ 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 1024 };
    const signs = [_]std.builtin.Signedness{ .unsigned, .signed };

    inline for (bit_lengths) |bits| {
        inline for (signs) |signedness| {
            const T = @Int(signedness, bits);
            // std.debug.print("=== {any} ===\n", .{T});
            const IF = intCodec(T);
            const tv = intTestVector(T);
            for (tv.slice()) |value| {
                var buf: [256]u8 = undefined;
                var w = ByteWriter{ .buf = &buf };
                try IF.write(&w, value);
                // std.debug.print("{d} -> {any}\n", .{ value, w.slice() });
                try std.testing.expectEqual(w.pos, IF.encodedLength(value));
                tt.checkFloat(w.slice());
                var r = ByteReader{ .buf = w.slice() };
                try std.testing.expectEqual(value, try IF.read(&r));
            }
        }
    }
}
