const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const bytes = @import("../ibex/bytes.zig");
const ByteWriter = bytes.ByteWriter;
const ByteReader = bytes.ByteReader;

pub fn showRate(name: []const u8, total: usize, timer: *std.time.Timer) void {
    const elapsed = timer.lap();
    // std.debug.print("elapsed={d}\n", .{elapsed});
    const seconds = @as(f64, @floatFromInt(elapsed)) / 1_000_000_000;
    const rate = @as(f64, @floatFromInt(total)) / seconds;
    std.debug.print("{s:>20}: {d:>20.0}/s\n", .{ name, rate });
}

pub const BMOptions = struct {
    output: bool = true,
    repeats: usize,
};

pub fn benchmarkCodec(gpa: Allocator, codec: anytype, numbers: anytype, options: BMOptions) !void {
    var enc_size: usize = undefined;

    {
        var timer = try std.time.Timer.start();
        for (0..options.repeats) |_| {
            enc_size = 0;
            for (numbers) |n| {
                enc_size += codec.encodedLength(n);
            }
        }
        if (options.output)
            showRate("encodedLength", numbers.len * options.repeats, &timer);
    }

    const enc_buf = try gpa.alloc(u8, enc_size);
    defer gpa.free(enc_buf);

    var w = ByteWriter{ .buf = enc_buf };
    {
        var timer = try std.time.Timer.start();
        for (0..options.repeats) |_| {
            w.pos = 0;
            for (numbers) |n| {
                try codec.write(&w, n);
            }
            assert(w.pos == enc_size);
        }
        if (options.output)
            showRate("write", numbers.len * options.repeats, &timer);
    }

    const output = try gpa.alloc(f64, numbers.len);
    defer gpa.free(output);

    var r = ByteReader{ .buf = w.slice() };
    {
        var timer = try std.time.Timer.start();
        for (0..options.repeats) |_| {
            r.pos = 0;
            for (0..numbers.len) |i| {
                output[i] = try codec.read(&r);
            }
            assert(w.pos == r.pos);
        }
        if (options.output)
            showRate("read", numbers.len * options.repeats, &timer);
    }

    for (numbers, 0..) |n, i| {
        assert(n == output[i]);
    }
}
