const std = @import("std");

pub fn FloatValue(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const bits = @typeInfo(T).float.bits;
        pub const exp_bits = switch (bits) {
            16 => 5,
            32 => 8,
            64 => 11,
            80 => 15,
            128 => 15,
            else => unreachable,
        };
        // f80 stores the redundant MSB of the mantissa explicitly.
        // Presumably because f80 is a legacy 80(2)87 format?
        pub const explicit_msb = switch (bits) {
            80 => true,
            else => false,
        };
        pub const mant_bits = bits - exp_bits - 1;
        pub const exp_bias = (1 << exp_bits - 1) - 1;

        pub const TExpValue = @Int(.signed, exp_bits + 1);
        pub const TInt = @Int(.unsigned, bits);
        pub const TExp = @Int(.unsigned, exp_bits);
        pub const TMant = @Int(.unsigned, mant_bits);

        value: packed struct(TInt) {
            mant: TMant,
            exp: TExp,
            sign: bool,
        } = undefined,

        pub fn init(value: T) Self {
            return Self{ .value = @bitCast(value) };
        }

        pub fn get(self: Self) T {
            return @bitCast(self.value);
        }

        pub fn exponent(self: Self) TExpValue {
            return @as(TExpValue, @intCast(self.value.exp)) - exp_bias;
        }

        fn isSpecial(self: Self) bool {
            return self.value.exp == (1 << exp_bits) - 1;
        }

        fn nanBit(self: Self) bool {
            const nan_bit = 1 << mant_bits - if (explicit_msb) 2 else 1;
            return (self.value.mant & nan_bit) != 0;
        }

        pub fn isInf(self: Self) bool {
            return self.isSpecial() and !self.nanBit();
        }

        pub fn isNaN(self: Self) bool {
            return self.isSpecial() and self.nanBit();
        }

        pub fn format(self: Self, w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print(
                "{s} e( {x:>4} ) m( {x:>28} )",
                .{
                    if (self.value.sign) "-" else "+",
                    self.value.exp,
                    self.value.mant,
                },
            );
        }
    };
}

test FloatValue {
    const types = [_]type{ f16, f32, f64, f80, f128 };

    inline for (types) |T| {
        const FS = FloatValue(T);

        try std.testing.expect(FS.init(std.math.inf(T)).isInf());
        try std.testing.expect(!FS.init(std.math.inf(T)).isNaN());
        try std.testing.expect(!FS.init(std.math.nan(T)).isInf());
        try std.testing.expect(FS.init(std.math.nan(T)).isNaN());

        if (false) {
            std.debug.print("=== {d} bits ===\n", .{@typeInfo(T).float.bits});
            const values = [_]T{
                0,
                1,
                2,
                3,
                255,
                1023,
                0.5,
                0.25,
                0.125,
                0.0625,
                -1,
                1.25,
                1.0625,
                std.math.inf(T),
                std.math.nan(T),
                -std.math.inf(T),
                -std.math.nan(T),
                // std.math.pi,
            };
            for (values) |v| {
                const fs = FS.init(v);
                std.debug.print(
                    "{d:>6}: {f} exp: {d:>6} inf: {any:<5} nan: {any:<5}\n",
                    .{ v, fs, fs.exponent(), fs.isInf(), fs.isNaN() },
                );
            }
        }
    }
}
