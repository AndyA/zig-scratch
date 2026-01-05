const intCodec = @import("./IbexFloat/int.zig").intCodec;

test {
    _ = @import("./IbexFloat/int.zig");
}

pub fn IbexFloat(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => unreachable,
        .int => intCodec(T),
        else => unreachable,
    };
}
