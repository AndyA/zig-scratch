const std = @import("std");

pub fn main() !void {
    std.debug.print("Woof\n", .{});
}

test {
    _ = @import("./tree.zig");
    _ = @import("./ibex/IbexInt.zig");
    _ = @import("./ibex/IbexNumber.zig");
    _ = @import("./ibex/IbexValue.zig");
    _ = @import("./support/bm.zig");
    _ = @import("./support/wildcard.zig");
}
