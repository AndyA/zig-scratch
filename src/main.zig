pub fn main() !void {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const alloc = gpa.allocator();
    var args = std.process.args();
    _ = args.skip();

    while (args.next()) |arg| {
        std.debug.print("Loading {s}\n", .{arg});
        const src = try std.fs.cwd().readFileAlloc(arg, alloc, .unlimited);
        defer alloc.free(src);
        std.debug.print("Loaded {d} bytes\n", .{src.len});
    }
}

const std = @import("std");
const assert = std.debug.assert;
