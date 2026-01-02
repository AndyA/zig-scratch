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
    const Sign = @Int(.unsigned, 1);
    const Exp = @Int(.unsigned, exp_bits);
    const Mant = @Int(.unsigned, bits - exp_bits - 1);

    return switch (endian) {
        .little => @Struct(
            .@"packed",
            @Int(.unsigned, bits),
            &.{ "mant", "exp", "sign" },
            &.{ Mant, Exp, Sign },
            &.{ .{}, .{}, .{} },
        ),
        .big => @Struct(
            .@"packed",
            @Int(.unsigned, bits),
            &.{ "sign", "exp", "mant" },
            &.{ Sign, Exp, Mant },
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
    switch (@typeInfo(T)) {
        .float => |f| return makeFloatStruct(f.bits, exponentSizeForBits(f.bits)),
        else => unreachable,
    }
}

fn unpack(comptime T: type, value: T) void {
    const fs: FloatStruct(T) = @bitCast(value);
    std.debug.print("{any}\n", .{fs});
}

test "foo" {
    std.debug.print("Testing\n", .{});
    // const x: f64 = 1;
    dumpBytes(f64, 1);
    dumpBytes(f64, 2);
    dumpBytes(f64, 3);
    dumpBytes(f64, -1);
    unpack(f64, 1);
    unpack(f32, 1);
    unpack(f64, 2);
    unpack(f64, -1);
    std.debug.print("endian: {any}\n", .{endian});
}
