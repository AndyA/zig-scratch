const std = @import("std");

const endian = @import("builtin").cpu.arch.endian();

fn hexDump(bytes: []const u8) void {
    for (bytes) |b| {
        std.debug.print("{x:0>2} ", .{b});
    }
    std.debug.print("\n", .{});
}

fn dumpBytes(comptime T: type, value: T) void {
    const bytes = @bitSizeOf(T) / 8;
    const buf: [bytes]u8 = @bitCast(value);
    hexDump(&buf);
}

fn makeFloatStruct(comptime bits: usize, comptime exp_bits: usize) type {
    const exp = @Int(.unsigned, exp_bits);
    const mant = @Int(.unsigned, bits - exp_bits - 1);

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

fn FloatStruct(comptime T: type) type {
    const bits = @typeInfo(T).float.bits;
    const exp_bits = exponentSizeForBits(bits);

    const TValue = makeFloatStruct(bits, exp_bits);
    const TExp = @Int(.signed, exp_bits + 1);

    return struct {
        const Self = @This();
        pub const BITS = bits;
        pub const EXP_BITS = exp_bits;
        pub const EXP_BIAS = (1 << (EXP_BITS - 1)) - 1;

        value: TValue,

        pub fn init(value: T) Self {
            return Self{ .value = @bitCast(value) };
        }

        pub fn get(self: Self) T {
            return @bitCast(self.value);
        }

        pub fn exponent(self: *const Self) TExp {
            return @as(TExp, @intCast(self.value.exp)) - EXP_BIAS;
        }

        pub fn isSpecial(self: Self) bool {
            return self.value.exp == (1 << exp_bits) - 1;
        }

        pub fn isInf(self: Self) bool {
            return self.isSpecial() and self.value.mant == 0;
        }

        pub fn isNaN(self: Self) bool {
            return self.isSpecial() and self.value.mant != 0;
        }
    };
}

fn unpack(comptime T: type, value: T) void {
    const FS = FloatStruct(T);
    const fs = FS.init(value);
    std.debug.print(
        "[{d}] {d}: {any} {d} {any} {any}\n",
        .{ FS.BITS, value, fs, fs.exponent(), fs.isInf(), fs.isNaN() },
    );
}

test "foo" {
    std.debug.print("Testing\n", .{});
    // const x: f64 = 1;
    // dumpBytes(f64, 1);
    // dumpBytes(f64, 2);
    // dumpBytes(f64, 3);
    // dumpBytes(f64, -1);
    unpack(f64, std.math.nan(f64));
    unpack(f64, std.math.inf(f64));
    unpack(f64, 0);
    unpack(f64, 1);
    unpack(f32, 1);
    unpack(f16, 0.5);
    unpack(f32, 0.5);
    unpack(f64, 0.5);
    unpack(f80, 0.5);
    unpack(f128, 0.5);
    unpack(f64, 2);
    unpack(f64, -1);
    std.debug.print("endian: {any}\n", .{endian});
}
