pub fn TreeNode(comptime K: type) type {
    return struct {
        const Self = @This();

        key: K,
        left: ?*Self = null,
        right: ?*Self = null,

        pub fn create(gpa: Allocator, key: K) !*Self {
            const node = try gpa.create(Self);
            node.* = .{ .key = key };
            return node;
        }

        pub fn insert(self: *Self, gpa: Allocator, key: K) !void {
            if (key < self.key) {
                if (self.left) |left|
                    try left.insert(gpa, key)
                else
                    self.left = try Self.create(gpa, key);
            } else if (key > self.key) {
                if (self.right) |right|
                    try right.insert(gpa, key)
                else
                    self.right = try Self.create(gpa, key);
            }
        }

        pub fn find(self: *const Self, key: K) ?*const Self {
            if (key == self.key) return self;
            if (key < self.key) {
                if (self.left) |left| return left.find(key);
            } else {
                if (self.right) |right| return right.find(key);
            }
            return null;
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            if (self.left) |left| left.deinit(gpa);
            if (self.right) |right| right.deinit(gpa);
            gpa.destroy(self);
        }

        pub fn iter(self: *const Self, comptime stack_size: usize) TreeIter(K, stack_size) {
            return TreeIter(K, stack_size).init(self);
        }
    };
}

test TreeNode {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(gpa, 10);
    defer root.deinit(gpa);
    try std.testing.expect(root.key == 10);
    try root.insert(gpa, 5);
    try root.insert(gpa, 15);
    const n1 = root.find(5);
    const n2 = root.find(15);
    const n3 = root.find(11);
    try std.testing.expect(n1.?.key == 5);
    try std.testing.expect(n2.?.key == 15);
    try std.testing.expect(n3 == null);
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

        pub fn init(root: ?*const Node) Self {
            var iter = Self{};
            if (root) |r| iter.push(r);
            return iter;
        }

        fn push(self: *Self, node: *const Node) void {
            assert(self.sp < stack_size);
            self.stack[self.sp] = StackNode{ .node = node };
            self.sp += 1;
        }

        pub fn next(self: *Self) ?T {
            while (true) {
                if (self.sp == 0) return null;
                const peeked = &self.stack[self.sp - 1];
                switch (peeked.state) {
                    .Left => {
                        peeked.state = .Right;
                        if (peeked.node.left) |left| self.push(left);
                    },
                    .Right => {
                        const value = peeked.node.key;
                        self.sp -= 1; // re-use stack slot
                        if (peeked.node.right) |right| self.push(right);
                        return value;
                    },
                }
            }
        }
    };
}

test TreeIter {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(gpa, 10);
    defer root.deinit(gpa);
    try root.insert(gpa, 5);
    try root.insert(gpa, 15);
    try root.insert(gpa, 11);
    try root.insert(gpa, 1);

    var i = root.iter(10);
    try std.testing.expectEqualDeep(1, i.next());
    try std.testing.expectEqualDeep(5, i.next());
    try std.testing.expectEqualDeep(10, i.next());
    try std.testing.expectEqualDeep(11, i.next());
    try std.testing.expectEqualDeep(15, i.next());
    try std.testing.expectEqualDeep(null, i.next());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
