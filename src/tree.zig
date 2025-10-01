pub fn TreeNode(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        left: ?*Self = null,
        right: ?*Self = null,

        pub fn create(alloc: std.mem.Allocator, value: T) !*Self {
            const node = try alloc.create(Self);
            node.* = .{ .value = value };
            return node;
        }

        pub fn insert(self: *Self, alloc: std.mem.Allocator, value: T) !void {
            if (value < self.value) {
                if (self.left) |left|
                    try left.insert(alloc, value)
                else
                    self.left = try Self.create(alloc, value);
            } else if (value > self.value) {
                if (self.right) |right|
                    try right.insert(alloc, value)
                else
                    self.right = try Self.create(alloc, value);
            }
        }

        pub fn find(self: *const Self, value: T) ?*const Self {
            if (value == self.value) return self;
            if (value < self.value) {
                if (self.left) |left| return left.find(value);
            } else {
                if (self.right) |right| return right.find(value);
            }
            return null;
        }

        pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
            if (self.left) |left| left.destroy(alloc);
            if (self.right) |right| right.destroy(alloc);
            alloc.destroy(self);
        }
    };
}

test TreeNode {
    const alloc = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(alloc, 10);
    defer root.destroy(alloc);
    try std.testing.expect(root.value == 10);
    try root.insert(alloc, 5);
    try root.insert(alloc, 15);
    const n1 = root.find(5);
    const n2 = root.find(15);
    try std.testing.expect(n1.?.value == 5);
    try std.testing.expect(n2.?.value == 15);
}

pub fn TreeIter(comptime T: type, comptime stack_size: usize) type {
    return struct {
        const Self = @This();
        const Node = TreeNode(T);

        const StackState = enum { Left, Right };
        const StackNode = struct {
            node: *const Node,
            state: StackState = .Left,
        };

        stack: [stack_size]StackNode = undefined,
        sp: usize = 0,

        fn push(self: *Self, node: StackNode) !void {
            if (self.sp >= stack_size)
                return error.StackOverflow;
            self.stack[self.sp] = node;
            self.sp += 1;
        }

        pub fn init(root: ?*const Node) !Self {
            var self = Self{};
            if (root) |r|
                try self.push(StackNode{ .node = r });
            return self;
        }

        pub fn next(self: *Self) !?T {
            while (true) {
                if (self.sp == 0) return null;
                const peeked = &self.stack[self.sp - 1];
                switch (peeked.state) {
                    .Left => {
                        peeked.state = .Right;
                        if (peeked.node.left) |left|
                            try self.push(StackNode{ .node = left });
                    },
                    .Right => {
                        const value = peeked.node.value;
                        self.sp -= 1; // re-use stack slot
                        if (peeked.node.right) |right|
                            try self.push(StackNode{ .node = right });
                        return value;
                    },
                }
            }
        }
    };
}

test TreeIter {
    const alloc = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(alloc, 10);
    defer root.destroy(alloc);
    try root.insert(alloc, 5);
    try root.insert(alloc, 15);
    try root.insert(alloc, 11);
    try root.insert(alloc, 1);

    var i = try TreeIter(u32, 10).init(root);
    try std.testing.expectEqualDeep(1, try i.next());
    try std.testing.expectEqualDeep(5, try i.next());
    try std.testing.expectEqualDeep(10, try i.next());
    try std.testing.expectEqualDeep(11, try i.next());
    try std.testing.expectEqualDeep(15, try i.next());
    try std.testing.expectEqualDeep(null, try i.next());
}

const std = @import("std");
