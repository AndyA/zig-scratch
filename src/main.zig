const PROG = (
    \\Line 1
    \\Line 2
    \\Line 3
);

pub fn main() !void {
    var r_buf: [256]u8 = undefined;
    var r = std.fs.File.stdin().reader(&r_buf);

    while (true) {
        const res = try r.interface.takeDelimiter('\n');
        if (res) |ln| {
            std.debug.print("Line: \"{s}\"\n", .{ln});
        } else {
            break;
        }
    }

    std.debug.print("Done!\n", .{});
}

const std = @import("std");
