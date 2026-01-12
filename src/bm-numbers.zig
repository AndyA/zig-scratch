const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const bm = @import("./support/bm.zig");
const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;

const NUMBER_DATA = @embedFile("./ibex/testdata/numbers.bin");
const NUMBER_COUNT = NUMBER_DATA.len / @sizeOf(f64);

const TVT = [NUMBER_COUNT]f64;

fn getTestData() TVT {
    var numbers: TVT = undefined;
    const number_data: []const u64 = @ptrCast(@alignCast(NUMBER_DATA));
    for (0..NUMBER_COUNT) |i| {
        numbers[i] = @bitCast(std.mem.bigToNative(u64, number_data[i]));
    }
    return numbers;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const numbers = getTestData();
    const codec = IbexNumber(f64);

    try bm.benchmarkCodec(gpa, codec, numbers, .{ .repeats = 1000 });
}
