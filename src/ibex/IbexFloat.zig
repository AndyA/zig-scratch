const std = @import("std");
const assert = std.debug.assert;

const ibex = @import("./ibex.zig");
const IbexTag = ibex.IbexTag;
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

        fn writeInt(w: *ByteWriter, value: T) void {
            const hi_bit = info.bits - @clz(value) - 1; // drop MSB
            const lo_bit = @ctz(value);
            const bytes: u16 = (hi_bit - lo_bit + 6) / 7;
            // std.debug.print("\nhi={d}, lo={d}, bytes={d}\n", .{ hi_bit, lo_bit, bytes });

            IbexInt.write(w, hi_bit); // exp

            for (0..bytes) |i| {
                const shift: i32 = @as(i32, @intCast(hi_bit - i * 7)) - 8;
                const shifted = if (shift > 0) value >> @intCast(shift) else value << @intCast(-shift);
                var bits = shifted & 0xfe;
                if (i < bytes - 1) bits |= 1;
                // std.debug.print("byte={d}, shift={d}, bits={x}\n", .{ i, shift, bits });
                w.put(@intCast(bits));
            }
        }

        fn readPosInt(r: *ByteReader) T {
            const exp = IbexInt.read(r);
            if (exp < 0) return 0;
            var acc: T = @as(T, 1) << @intCast(exp);
            var shift = exp - 8;
            while (true) {
                const nb = r.next();
                const bits = nb & 0xfe;
                acc |= if (shift >= 0) bits << @intCast(shift) else bits >> @intCast(-shift);
                shift -= 7;
                if (nb & 0x01 == 0) break;
            }
            return acc;
        }

        fn readNegInt(r: *ByteReader) T {
            r.negate();
            defer r.negate();
            return ~readPosInt(r) + 1;
        }

        pub fn write(w: *ByteWriter, value: T) void {
            if (value == 0) {
                w.put(@intFromEnum(IbexTag.FloatPosZero));
            } else if (value < 0) {
                w.put(@intFromEnum(IbexTag.FloatNeg));
                w.negate();
                defer w.negate();
                writeInt(w, -value);
            } else {
                w.put(@intFromEnum(IbexTag.FloatPos));
                writeInt(w, value);
            }
        }

        pub fn read(r: *ByteReader) T {
            const tag: IbexTag = @enumFromInt(r.next());
            return switch (tag) {
                .FloatPosZero, .FloatNegZero => 0,
                .FloatPos => readPosInt(r),
                .FloatNeg => readNegInt(r),
                else => unreachable,
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
    T.write(&w, 255);
    var r = ByteReader{ .buf = w.slice() };
    try std.testing.expectEqual(255, T.read(&r));
    // T.write(&w, 0xffee);
    // T.write(&w, std.math.maxInt(u32));
}

// test "foo" {
//     std.debug.print("Hello!\n", .{});
// }
