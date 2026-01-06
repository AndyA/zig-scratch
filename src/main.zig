const std = @import("std");

const IbexFloat = @import("./ibex//IbexFloat.zig").IbexFloat;
const ibex = @import("./ibex/ibex.zig");
const ByteWriter = ibex.ByteWriter;
const ByteReader = ibex.ByteReader;

pub fn main() !void {
    std.debug.print("Woof\n", .{});
    const types = [_]type{ u8, i9, i13, i32, u33, u32, u64, u1024, i1024, u32768 };
    inline for (types) |T| {
        // std.debug.print("=== {any} ===\n", .{T});
        const IF = IbexFloat(T);
        const values = [_]T{ 0, std.math.minInt(T), std.math.maxInt(T) };
        for (values) |value| {
            var buf: [32768 / 7 + 256]u8 = undefined;
            var w = ByteWriter{ .buf = &buf };
            try IF.write(&w, value);
            std.debug.print("{any}\n", .{w.slice()});
            var r = ByteReader{ .buf = w.slice() };
            const got = try IF.read(&r);
            std.debug.print("got {any}\n", .{got == value});
        }
    }
}

test {
    _ = @import("./tree.zig");
    _ = @import("./ibex/IbexInt.zig");
    _ = @import("./ibex/IbexFloat.zig");
}
