pub fn TreeNode(comptime K: type) type {
    return struct {
        const Self = @This();

        key: K,
        height: i32 = 1,
        left: ?*Self = null,
        right: ?*Self = null,

        pub fn create(gpa: Allocator, key: K) Allocator.Error!*Self {
            const node = try gpa.create(Self);
            node.* = .{ .key = key };
            return node;
        }

        fn getHeight(node: ?*const Self) i32 {
            if (node) |n| return n.height;
            return 0;
        }

        fn recalc(node: *Self) *Self {
            node.height = @max(getHeight(node.left), getHeight(node.right)) + 1;
            return node;
        }

        fn insert(node: *Self, gpa: Allocator, key: K) Allocator.Error!*Self {
            if (key < node.key)
                node.left = try insertNode(node.left, gpa, key)
            else if (key > node.key)
                node.right = try insertNode(node.right, gpa, key)
            else
                return node;

            const lh = getHeight(node.left);
            const rh = getHeight(node.right);

            //      (N)                (L)
            //     /   \              /   \
            //    A    (L)    ->    (N)    C
            //        /   \        /   \
            //       B     C      A     B

            if (lh > rh + 1) {
                // left too deep: pivot
                var left = node.left.?;
                node.left = left.right;
                left.right = node.recalc();
                return left.recalc();
            } else if (rh > lh + 1) {
                // right too deep: pivot
                var right = node.right.?;
                node.right = right.left;
                right.left = node.recalc();
                return right.recalc();
            } else {
                return node.recalc();
            }
        }

        pub fn insertNode(node: ?*Self, gpa: Allocator, key: K) Allocator.Error!*Self {
            if (node) |n| return insert(n, gpa, key);
            return Self.create(gpa, key);
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
    root = try root.insertNode(gpa, 5);
    root = try root.insertNode(gpa, 15);
    const n1 = root.find(5);
    const n2 = root.find(15);
    const n3 = root.find(11);
    try std.testing.expect(n1.?.key == 5);
    try std.testing.expect(n2.?.key == 15);
    try std.testing.expect(n3 == null);
}

test "Tree balance" {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(gpa, 1);
    defer root.deinit(gpa);

    for (2..1000) |i| {
        root = try root.insertNode(gpa, @intCast(i));
    }

    try std.testing.expectEqual(root.height, 10);
}

pub fn TreeIter(comptime K: type, comptime stack_size: usize) type {
    return struct {
        const Self = @This();
        const Node = TreeNode(K);

        stack: [stack_size]*const Node = undefined,
        sp: usize = 0,

        pub fn init(root: ?*const Node) Self {
            var self = Self{};
            self.schedule(root);
            return self;
        }

        fn schedule(self: *Self, node: ?*const Node) void {
            var current = node;
            while (current) |n| {
                assert(self.sp < stack_size);
                self.stack[self.sp] = n;
                self.sp += 1;
                current = n.left;
            }
        }

        pub fn next(self: *Self) ?K {
            if (self.sp == 0) return null;
            self.sp -= 1;
            const node = self.stack[self.sp];
            self.schedule(node.right);
            return node.key;
        }
    };
}

test TreeIter {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32);
    var root = try Node.create(gpa, 10);
    defer root.deinit(gpa);
    root = try root.insertNode(gpa, 5);
    root = try root.insertNode(gpa, 15);
    root = try root.insertNode(gpa, 11);
    root = try root.insertNode(gpa, 1);

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
