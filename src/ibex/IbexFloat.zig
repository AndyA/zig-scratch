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
    return struct {
        const info = @typeInfo(T).int;

        pub fn encodedLength(value: T) usize {
            const hi_bit = info.bits - @clz(value) - 1; // drop MSB
            const lo_bit = @ctz(value);
            const bytes = (hi_bit - lo_bit + 6) / 7;
            return 1 + IbexInt.encodedLength(hi_bit) + bytes;
        }

        fn writeInt(w: *ByteWriter, value: T) IbexError!void {
            const hi_bit = info.bits - @clz(value) - 1; // drop MSB
            const lo_bit = @ctz(value);
            const bytes: u16 = (hi_bit - lo_bit + 6) / 7;
            // std.debug.print("\nhi={d}, lo={d}, bytes={d}\n", .{ hi_bit, lo_bit, bytes });

            try IbexInt.write(w, hi_bit); // exp

            for (0..bytes) |i| {
                const shift: i32 = @as(i32, @intCast(hi_bit - i * 7)) - 8;
                const shifted = if (shift > 0) value >> @intCast(shift) else value << @intCast(-shift);
                var bits = shifted & 0xfe;
                if (i < bytes - 1) bits |= 1;
                // std.debug.print("byte={d}, shift={d}, bits={x}\n", .{ i, shift, bits });
                try w.put(@intCast(bits));
            }
        }

        fn readPosInt(r: *ByteReader) IbexError!T {
            const exp = try IbexInt.read(r);
            if (exp < 0) return 0;
            var acc: T = @as(T, 1) << @intCast(exp);
            var shift = exp - 8;
            while (true) : (shift -= 7) {
                const nb = try r.next();
                const bits = nb & 0xfe;
                acc |= if (shift >= 0) bits << @intCast(shift) else bits >> @intCast(-shift);
                if (nb & 0x01 == 0) break;
            }
            return acc;
        }

        fn readNegInt(r: *ByteReader) IbexError!T {
            r.negate();
            defer r.negate();
            return ~try readPosInt(r) + 1;
        }

        pub fn write(w: *ByteWriter, value: T) IbexError!void {
            if (value == 0) {
                try w.put(@intFromEnum(IbexTag.FloatPosZero));
            } else if (value < 0) {
                try w.put(@intFromEnum(IbexTag.FloatNeg));
                w.negate();
                defer w.negate();
                try writeInt(w, -value);
            } else {
                try w.put(@intFromEnum(IbexTag.FloatPos));
                try writeInt(w, value);
            }
        }

        pub fn read(r: *ByteReader) IbexError!T {
            const nb = try r.next();
            // todo check range of rag
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

test IbexFloat {
    const T = IbexFloat(u32);
    var buf: [20]u8 = undefined;
    var w = ByteWriter{ .buf = &buf };
    // T.write(&w, 3);
    try T.write(&w, 255);
    var r = ByteReader{ .buf = w.slice() };
    try std.testing.expectEqual(255, try T.read(&r));
    // for (w.slice()) |b| {
    //     std.debug.print("{x:0>2} ", .{b});
    // }
    // std.debug.print("\n", .{});
    // T.write(&w, 0xffee);
    // T.write(&w, std.math.maxInt(u32));
}

// test "foo" {
//     std.debug.print("Hello!\n", .{});
// }
