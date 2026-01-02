const std = @import("std");

fn FloatValue(comptime bits: usize, comptime exp_bits: usize) type {
    const exp = @Int(.unsigned, exp_bits);
    const mant = @Int(.unsigned, bits - exp_bits - 1);
    const endian = @import("builtin").cpu.arch.endian();

    return switch (endian) {
        .little => @Struct(
            .@"packed",
            @Int(.unsigned, bits),
            &.{ "mant", "exp", "sign" },
            &.{ mant, exp, bool },
            &.{ .{}, .{}, .{} },
        ),
        .big => @Struct(
            .@"packed",
            @Int(.unsigned, bits),
            &.{ "sign", "exp", "mant" },
            &.{ bool, exp, mant },
            &.{ .{}, .{}, .{} },
        ),
    };
}

fn exponentSizeForBits(bits: usize) usize {
    return switch (bits) {
        16 => 5,
        32 => 8,
        64 => 11,
        80 => 15,
        128 => 15,
        else => unreachable,
    };
}

pub fn FloatBits(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const bits = @typeInfo(T).float.bits;
        pub const exp_bits = exponentSizeForBits(bits);
        pub const mant_bits = bits - exp_bits - 1;
        pub const exp_bias = (1 << exp_bits - 1) - 1;

        // f80 stores the redundant MSB of the mantissa explicitly.
        // Presumably because f80 is a legacy 80(2)87 format?
        pub const explicit_msb = switch (bits) {
            80 => true,
            else => false,
        };

        const TExp = @Int(.signed, exp_bits + 1);

        value: FloatValue(bits, exp_bits),

        pub fn init(value: T) Self {
            return Self{ .value = @bitCast(value) };
        }

        pub fn get(self: Self) T {
            return @bitCast(self.value);
        }

        pub fn exponent(self: Self) TExp {
            return @as(TExp, @intCast(self.value.exp)) - exp_bias;
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

test "foo" {
    const types = [_]type{ f16, f32, f64, f80, f128 };

    inline for (types) |T| {
        std.debug.print("=== {d} bits ===\n", .{@typeInfo(T).float.bits});
        const values = [_]T{
            0,
            1,
            2,
            3,
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
            const FS = FloatBits(T);
            const fs = FS.init(v);
            std.debug.print(
                "{d:>6}: {f} exp: {d:>6} inf: {any:<5} nan: {any:<5}\n",
                .{ v, fs, fs.exponent(), fs.isInf(), fs.isNaN() },
            );
        }
    }
}
