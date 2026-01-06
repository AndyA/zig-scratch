const intCodec = @import("./IbexNumber/int.zig").intCodec;
const floatCodec = @import("./IbexNumber/float.zig").floatCodec;

test {
    _ = @import("./IbexNumber/mantissa.zig");
    _ = @import("./IbexNumber/float_bits.zig");
    _ = @import("./IbexNumber/int.zig");
    _ = @import("./IbexNumber/float.zig");
}

pub fn IbexNumber(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float => floatCodec(T),
        .int => intCodec(T),
        else => unreachable,
    };
}
