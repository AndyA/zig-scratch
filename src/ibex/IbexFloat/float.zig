const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ibex = @import("../ibex.zig");
const IbexTag = ibex.IbexTag;
const IbexError = ibex.IbexError;
const ByteReader = ibex.ByteReader;
const ByteWriter = ibex.ByteWriter;
const FloatValue = @import("./float_bits.zig").FloatValue;
const IbexInt = @import("../IbexInt.zig");

// Uh oh:
// https://en.wikipedia.org/wiki/Subnormal_number

pub fn floatCodec(comptime T: type) type {
    const VT = FloatValue(T);
    return struct {
        pub fn encodedLength(value: T) usize {
            if (math.isNegativeZero(value) or
                math.isPositiveZero(value) or
                math.isInf(value) or
                math.isNan(value))
                return 1;

            const v = VT.init(@abs(value));
            var exp: i64 = v.value.exp;
            var mant = v.value.mant;

            assert(exp < math.maxInt(VT.TExp));

            if (exp == 0) { // subnormal
                const lz = @clz(mant);
                mant <<= lz;
                exp -= lz;
            }

            const bytes: u16 = (VT.mant_bits - @ctz(mant) + 6) / 7;
            return 1 + IbexInt.encodedLength(exp - VT.exp_bias) + @max(1, bytes);
        }

        fn writeFloat(w: *ByteWriter, value: T) IbexError!void {
            const v = VT.init(value);
            var exp: i64 = v.value.exp;
            var mant = v.value.mant;

            assert(exp < math.maxInt(VT.TExp));

            if (exp == 0) { // subnormal
                const lz = @clz(mant);
                mant <<= lz;
                exp -= lz;
            }

            try IbexInt.write(w, exp - VT.exp_bias);

            const bytes: u16 = (VT.mant_bits - @ctz(mant) + 6) / 7;

            if (bytes == 0) {
                try w.put(0x00);
                return;
            }

            var shift = @as(i32, @intCast(VT.mant_bits)) - 8;
            for (0..bytes) |i| {
                const part = if (shift >= 0)
                    mant >> @intCast(shift)
                else
                    mant << @intCast(-shift);
                var bits = part & 0xfe;
                if (i < bytes - 1) bits |= 1;
                try w.put(@intCast(bits));
                shift -= 7;
            }
        }

        pub fn write(w: *ByteWriter, value: T) IbexError!void {
            if (math.isNegativeInf(value))
                return w.put(@intFromEnum(IbexTag.FloatNegInf))
            else if (math.isPositiveInf(value))
                return w.put(@intFromEnum(IbexTag.FloatPosInf))
            else if (math.isNegativeZero(value))
                return w.put(@intFromEnum(IbexTag.FloatNegZero))
            else if (math.isPositiveZero(value))
                return w.put(@intFromEnum(IbexTag.FloatPosZero))
            else if (math.isNan(value)) {
                const v = FloatValue(T).init(value);
                return w.put(@intFromEnum(if (v.value.sign)
                    IbexTag.FloatNegNaN
                else
                    IbexTag.FloatPosNaN));
            } else if (value < 0.0) {
                try w.put(@intFromEnum(IbexTag.FloatNeg));
                w.negate();
                defer w.negate();
                return writeFloat(w, -value);
            } else {
                try w.put(@intFromEnum(IbexTag.FloatPos));
                return writeFloat(w, value);
            }
        }

        fn readFloatPos(r: *ByteReader) IbexError!T {
            var exp = try IbexInt.read(r) + VT.exp_bias;
            if (exp >= math.maxInt(VT.TExp))
                return IbexError.Overflow;

            var mant: VT.TMant = 0;
            var shift: i64 = VT.mant_bits - 8;

            while (true) : (shift -= 7) {
                const nb = try r.next();
                const bits: VT.TMant = nb & 0xfe;
                if (shift > -8)
                    mant |= if (shift >= 0)
                        bits << @intCast(shift)
                    else
                        bits >> @intCast(-shift);
                if (nb & 0x01 == 0) {
                    // Detect non-canonical encoding
                    if (nb == 0 and shift != VT.mant_bits - 8)
                        return IbexError.InvalidData;
                    break;
                }
            }

            if (exp <= 0) { // subnormal
                if (-exp >= VT.mant_bits)
                    return 0.0;
                mant >>= @intCast(-exp);
                exp = 0;
            }

            const v = VT{ .value = .{
                .exp = @intCast(exp),
                .mant = mant,
                .sign = false,
            } };
            return v.get();
        }

        fn readFloatNeg(r: *ByteReader) IbexError!T {
            r.negate();
            defer r.negate();
            return -try readFloatPos(r);
        }

        pub fn read(r: *ByteReader) IbexError!T {
            const nb = try r.next();
            const tag: IbexTag = @enumFromInt(nb);
            return switch (tag) {
                .FloatPosZero => 0.0,
                .FloatNegZero => -0.0,
                .FloatNegInf => -math.inf(T),
                .FloatPosInf => math.inf(T),
                .FloatNegNaN => -math.nan(T),
                .FloatPosNaN => math.nan(T),
                .FloatPos => readFloatPos(r),
                .FloatNeg => readFloatNeg(r),
                else => IbexError.InvalidData,
            };
        }
    };
}

const tt = @import("./test_tools.zig");

fn TV(comptime T: type) type {
    return tt.TestVec(T, 100);
}

fn floatTestVector(comptime T: type) TV(T) {
    var tv = TV(T){};

    tv.put(math.floatMin(T));
    tv.put(math.floatMax(T));
    tv.put(-math.floatMin(T));
    tv.put(-math.floatMax(T));
    tv.put(math.floatEpsAt(T, 0));
    tv.put(-math.floatEpsAt(T, 0));
    tv.put(math.inf(T));
    tv.put(-math.inf(T));
    tv.put(math.nan(T));
    tv.put(-math.nan(T));

    tv.put(math.pi);
    tv.put(math.phi);
    tv.put(-math.pi);
    tv.put(-math.phi);

    var small: T = 0.0;
    while (small < 15.0) : (small += 1.0) {
        tv.put(small);
        tv.put(-small);
        tv.put(1.0 / small);
        tv.put(-1.0 / small);
    }

    // std.debug.print("{any}: {any}\n", .{ T, tv.slice() });

    return tv;
}

fn TMost(comptime TA: type, comptime TB: type) type {
    return if (@typeInfo(TA).float.bits > @typeInfo(TB).float.bits) TA else TB;
}

fn TLeast(comptime TA: type, comptime TB: type) type {
    return if (@typeInfo(TA).float.bits < @typeInfo(TB).float.bits) TA else TB;
}

fn isOverflow(comptime T: type, value: f128) bool {
    return math.isFinite((value)) and
        (value < -math.floatMax(T) or
            value > math.floatMax(T));
}

fn testRoundTrip(comptime TWrite: type, comptime TRead: type, value: f128) !void {
    if (isOverflow(TWrite, value)) {
        // std.debug.print("skipping {d} out of range for {any}\n", .{ value, TWrite });
        return;
    }
    const enc = floatCodec(TWrite);
    var buf: [256]u8 = undefined;
    var w = ByteWriter{ .buf = &buf };
    try enc.write(&w, @floatCast(value));
    // std.debug.print("{d} -> {any}\n", .{ value, w.slice() });
    try std.testing.expectEqual(w.pos, enc.encodedLength(@floatCast(value)));

    const dec = floatCodec(TRead);
    var r = ByteReader{ .buf = w.slice() };
    if (isOverflow(TRead, value)) {
        const res = dec.read(&r);
        try std.testing.expectError(IbexError.Overflow, res);
        return;
    }

    const output = try dec.read(&r);
    if (math.isNegativeInf(value)) {
        try std.testing.expect(math.isNegativeInf(output));
    } else if (math.isPositiveInf(value)) {
        try std.testing.expect(math.isPositiveInf(output));
    } else if (math.isNan(value)) {
        try std.testing.expect(math.isNan(output));
    } else {
        const TMin = TLeast(TWrite, TRead);
        const TMax = TMost(TWrite, TRead);
        const eps: TMax = @floatCast(math.floatEpsAt(TMin, @floatCast(value)));
        const want: TMax = @floatCast(value);
        const got: TMax = @floatCast(output);
        // std.debug.print("diff={d}, eps={d}\n", .{ @abs(got - want), eps });
        try std.testing.expect(@abs(got - want) <= eps);
    }

    if (TWrite == TRead) {
        const want: TRead = @floatCast(value);
        try std.testing.expect(tt.exactSame(want, output));
    }
}

const FloatTypes = [_]type{ f16, f32, f64, f128 };

test floatCodec {
    inline for (FloatTypes) |TWrite| {
        inline for (FloatTypes) |TRead| {
            // std.debug.print("=== {any} -> {any} ===\n", .{ TWrite, TRead });
            const tvw = floatTestVector(TWrite);
            for (tvw.slice()) |value| {
                try testRoundTrip(TWrite, TRead, value);
            }
            const tvr = floatTestVector(TRead);
            for (tvr.slice()) |value| {
                try testRoundTrip(TWrite, TRead, value);
            }
        }
    }
}
