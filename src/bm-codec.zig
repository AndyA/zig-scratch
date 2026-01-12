const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const wildMatch = @import("./support/wildcard.zig").wildMatch;
const bm = @import("./support/bm.zig");
const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;
const IbexInt = @import("./ibex/IbexInt.zig");

const Benchmarks = struct {
    pub fn @"IbexNumber/f64"(io: std.Io, gpa: Allocator, name: []const u8) !void {
        const numbers = try bm.loadTestData(f64, io, gpa, "ref/testdata/f64sample.bin");
        defer gpa.free(numbers);
        const codec = IbexNumber(f64);
        try bm.benchmarkCodec(gpa, codec, numbers, .{ .repeats = 1000, .name = name });
    }

    pub fn @"IbexInt/lengths"(io: std.Io, gpa: Allocator, name: []const u8) !void {
        const numbers = try bm.loadTestData(i64, io, gpa, "ref/testdata/i64lengths.bin");
        defer gpa.free(numbers);
        try bm.benchmarkCodec(gpa, IbexInt, numbers, .{ .repeats = 5000, .name = name });
    }
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    const info = @typeInfo(Benchmarks);

    inline for (info.@"struct".decls) |d| {
        const selected = blk: {
            if (args.len == 1)
                break :blk true;
            for (args[1..]) |arg| {
                if (wildMatch(arg, d.name))
                    break :blk true;
            }
            break :blk false;
        };
        if (selected) {
            const bm_fun = @field(Benchmarks, d.name);
            try bm_fun(init.io, init.gpa, d.name);
        }
    }
}
