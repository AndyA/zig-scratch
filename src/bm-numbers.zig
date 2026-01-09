const std = @import("std");
const assert = std.debug.assert;

const IbexNumber = @import("./ibex/IbexNumber.zig").IbexNumber;
const ibex = @import("./ibex/ibex.zig");
const ByteWriter = ibex.ByteWriter;
const ByteReader = ibex.ByteReader;

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

fn showRate(name: []const u8, total: usize, timer: *std.time.Timer) void {
    const elapsed = timer.lap();
    // std.debug.print("elapsed={d}\n", .{elapsed});
    const seconds = @as(f64, @floatFromInt(elapsed)) / 1_000_000_000;
    const rate = @as(f64, @floatFromInt(total)) / seconds;
    std.debug.print("{s:>20}: {d:>20.0}/s\n", .{ name, rate });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    const numbers = getTestData();
    const codec = IbexNumber(f64);

    var enc_size: usize = 0;

    {
        var timer = try std.time.Timer.start();
        for (numbers) |n| {
            enc_size += codec.encodedLength(n);
        }
        showRate("encodedLength", numbers.len, &timer);
        // std.debug.print("size: {d}\n", .{enc_size});
    }

    const enc_buf = try gpa.alloc(u8, enc_size);
    defer gpa.free(enc_buf);

    var w = ByteWriter{ .buf = enc_buf };
    {
        var timer = try std.time.Timer.start();
        for (numbers) |n| {
            try codec.write(&w, n);
        }
        assert(w.pos == enc_size);
        showRate("write", numbers.len, &timer);
    }

    const output = try gpa.alloc(f64, numbers.len);
    defer gpa.free(output);

    var r = ByteReader{ .buf = w.slice() };
    {
        var timer = try std.time.Timer.start();
        for (0..numbers.len) |i| {
            output[i] = try codec.read(&r);
        }
        assert(w.pos == r.pos);
        showRate("read", numbers.len, &timer);
    }

    for (numbers, 0..) |n, i| {
        assert(n == output[i]);
    }
}
