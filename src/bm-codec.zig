const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const wildMatch = @import("./support/wildcard.zig").wildMatch;
const bm = @import("./support/bm.zig");
const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;

const Benchmarks = struct {
    pub fn @"IbexNumber/f64"(io: std.Io, gpa: Allocator, name: []const u8) !void {
        const numbers = try bm.loadTestData(f64, io, gpa, "ref/testdata/f64sample.bin");
        defer gpa.free(numbers);
        const codec = IbexNumber(f64);
        try bm.benchmarkCodec(gpa, codec, numbers, .{ .repeats = 1000, .name = name });
    }
};

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{ .environ = init.environ });
    defer threaded.deinit();
    const io = threaded.io();

    const args = try init.args.toSlice(gpa);
    defer gpa.free(args);
    const info = @typeInfo(Benchmarks);

    inline for (info.@"struct".decls) |d| {
        const selected = blk: {
            for (args[1..]) |arg| {
                if (wildMatch(arg, d.name))
                    break :blk true;
            }
            break :blk false;
        };
        if (selected) {
            const bm_fun = @field(Benchmarks, d.name);
            try bm_fun(io, gpa, d.name);
        }
    }
}
