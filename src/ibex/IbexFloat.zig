const intCodec = @import("./IbexFloat/int.zig").intCodec;
const floatCodec = @import("./IbexFloat/float.zig").floatCodec;

test {
    _ = @import("./IbexFloat/mantissa.zig");
    _ = @import("./IbexFloat/float_bits.zig");
    _ = @import("./IbexFloat/int.zig");
    _ = @import("./IbexFloat/float.zig");
}

pub fn IbexFloat(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => floatCodec(T),
        .int => intCodec(T),
        else => unreachable,
    };
}
