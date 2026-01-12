const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const bm = @import("./support/bm.zig");
const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    const numbers = try bm.loadTestData(f64, io, gpa, "ref/testdata/numbers.bin");
    defer gpa.free(numbers);
    const codec = IbexNumber(f64);

    try bm.benchmarkCodec(gpa, codec, numbers, .{ .repeats = 1000 });
}
