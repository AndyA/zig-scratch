fn Literal(comptime VT: anytype) type {
    return struct { value: VT };
}

fn BinOp(comptime NT: type, comptime oper: []const u8) type {
    return struct {
        pub const op = oper;
        left: *const NT,
        right: *const NT,
    };
}

const ImplLiteralFloat = struct {
    pub fn eval(node: *const LiteralFloat, ctx: anytype) anyerror!f64 {
        _ = ctx;
        return node.value;
    }
};

const ImplAddOp = struct {
    pub fn eval(node: *const AddOp, ctx: anytype) anyerror!f64 {
        return (try node.left.eval(ctx)) + (try node.right.eval(ctx));
    }
};

const ImplMulOp = struct {
    pub fn eval(node: *const MulOp, ctx: anytype) anyerror!f64 {
        return (try node.left.eval(ctx)) * (try node.right.eval(ctx));
    }
};

const LiteralInt = Literal(i64);
const LiteralFloat = Literal(f64);
// const AddOp = BinOp(Node, "+");
// const MulOp = BinOp(Node, "*");

const AddOp = struct { left: *const Node, right: *const Node };
const MulOp = struct { left: *const Node, right: *const Node };

const Node = union(enum) {
    // int: LiteralInt,
    float: LiteralFloat,
    add_op: AddOp,
    mul_op: MulOp,

    pub fn eval(self: *const Node, ctx: anytype) anyerror!f64 {
        var rv: f64 = undefined;
        try ctx.despatch("eval", self, .{}, &rv);
        return rv;
    }

    // pub fn foo(self: *const Node, ctx: anytype, flag: bool) !bool {
    //     var rv: bool = undefined;
    //     try ctx.despatch("foo", self, .{flag}, &rv);
    //     return rv;
    // }
};

test Node {
    const node = Node{ .float = LiteralFloat{ .value = 3.14 } };
    const foo: *const Node = @fieldParentPtr("float", &node.float);
    try std.testing.expect(foo == &node);
    const flo = @field(&node, "float");
    try std.testing.expect(flo.value == 3.14);
}

const Type = std.builtin.Type;

fn structField(comptime name: []const u8, comptime T: type) Type.StructField {
    var z_name: [name.len:0]u8 = @splat(' ');
    @memcpy(&z_name, name);
    return .{
        .name = &z_name,
        .type = T,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = 0,
    };
}

fn Expr(comptime NodeT: type, comptime implementations: []const type) type {
    comptime {
        const node_info = @typeInfo(NodeT).@"union";
        var despatcher_fields: [node_info.fields.len]Type.StructField = undefined;
        var field_names: [node_info.fields.len][]const u8 = undefined;

        // Despatcher is a struct with a field for each node type
        // Each field is a struct with the appropriate impl for each method

        for (node_info.fields, 0..) |field, field_idx| {
            var method_fields: [node_info.decls.len]Type.StructField = undefined;
            // Loop over decls
            DECL: for (node_info.decls, 0..) |node_decl, node_decl_idx| {
                for (implementations) |impl| {
                    const impl_info = @typeInfo(impl).@"struct";
                    for (impl_info.decls) |impl_decl| {
                        if (!std.mem.eql(u8, node_decl.name, impl_decl.name))
                            continue;
                        const impl_fn = @field(impl, node_decl.name);
                        const impl_fn_info = @typeInfo(@TypeOf(impl_fn)).@"fn";
                        if (impl_fn_info.params.len < 1) continue;
                        if (impl_fn_info.params[0].type) |ft| {
                            switch (@typeInfo(ft)) {
                                .pointer => |ptr| {
                                    // @compileLog("trying " ++ @typeName(ptr.child));
                                    if (ptr.child != field.type) continue;

                                    const method_field = Type.StructField{
                                        .name = impl_decl.name,
                                        .type = @TypeOf(impl_fn),
                                        .default_value_ptr = impl_fn,
                                        .is_comptime = true,
                                        .alignment = @alignOf(@TypeOf(impl_fn)),
                                    };

                                    method_fields[node_decl_idx] = method_field;
                                    continue :DECL;
                                },
                                else => continue,
                            }
                        }
                    }
                }
                @compileError("No implementation for " ++ node_decl.name ++
                    " on " ++ @typeName(field.type));
            }

            const NodeDespatcher = @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &method_fields,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            } });

            despatcher_fields[field_idx] = Type.StructField{
                .name = field.name,
                .type = NodeDespatcher,
                .default_value_ptr = &NodeDespatcher{},
                .is_comptime = true,
                .alignment = @alignOf(@TypeOf(usize)),
            };

            field_names[field_idx] = field.name;
        }

        const Despatcher = @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = &despatcher_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        } });

        const despatcher = Despatcher{};
        const field_map = field_names;

        return struct {
            const Self = @This();

            pub fn despatch(
                self: Self,
                comptime method: []const u8,
                node: *const NodeT,
                params: anytype,
                rv: anytype,
            ) anyerror!void {
                const type_idx = @intFromEnum(node.*);
                switch (type_idx) {
                    inline 0...field_map.len - 1 => |idx| {
                        const jump = @field(despatcher, field_map[idx]);
                        const foo = @field(jump, method);
                        const value = @field(node, field_map[idx]);
                        rv.* = try @call(.auto, foo, .{ &value, self });
                    },
                    else => unreachable,
                }
                _ = params;
            }
        };
    }
}

test Expr {
    // const node = Node{ .float = LiteralFloat{ .value = 3.14 } };
    const node = Node{ .add_op = AddOp{
        .left = &Node{ .float = LiteralFloat{ .value = 1.3 } },
        .right = &Node{ .float = LiteralFloat{ .value = 2.1 } },
    } };

    const expr = Expr(Node, &.{
        ImplLiteralFloat,
        ImplAddOp,
        ImplMulOp,
    }){};

    const res = try node.eval(expr);
    std.debug.print("Result: {}\n", .{res});
    try std.testing.expect(AddOp != MulOp);
}

pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});
}

const std = @import("std");
