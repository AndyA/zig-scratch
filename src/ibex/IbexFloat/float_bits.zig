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
