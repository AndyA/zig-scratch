pub fn NumCompare(comptime T: type) fn (T, T) Order {
    return struct {
        pub fn inner(a: T, b: T) Order {
            return std.math.order(a, b);
        }
    }.inner;
}

test NumCompare {
    const cmp = NumCompare(i32);
    try std.testing.expectEqualDeep(.eq, cmp(1, 1));
    try std.testing.expectEqualDeep(.eq, cmp(0, 0));
    try std.testing.expectEqualDeep(.lt, cmp(0, 1));
    try std.testing.expectEqualDeep(.gt, cmp(1, -1));
}

pub fn TreeNode(comptime K: type, comptime V: type, comptime cmp: fn (K, K) Order) type {
    return struct {
        const Node = @This();

        const STACK_SIZE = 33;

        key: K,
        value: V,
        height: i32 = 1,
        left: ?*Node = null,
        right: ?*Node = null,

        pub fn create(gpa: Allocator, key: K, value: V) Allocator.Error!*Node {
            const node = try gpa.create(Node);
            node.* = .{ .key = key, .value = value };
            return node;
        }

        fn getHeight(node: ?*const Node) i32 {
            if (node) |n| return n.height;
            return 0;
        }

        fn recalc(node: *Node) *Node {
            node.height = @max(getHeight(node.left), getHeight(node.right)) + 1;
            return node;
        }

        fn insert(node: *Node, gpa: Allocator, key: K, value: V) Allocator.Error!*Node {
            switch (cmp(key, node.key)) {
                .lt => node.left = try insertNode(node.left, gpa, key, value),
                .gt => node.right = try insertNode(node.right, gpa, key, value),
                .eq => return node,
            }

            const lh = getHeight(node.left);
            const rh = getHeight(node.right);

            //      (N)                (L)
            //     /   \              /   \
            //    A    (L)    ->    (N)    C
            //        /   \        /   \
            //       B     C      A     B

            if (lh > rh + 1) {
                // left too tall: pivot
                var left = node.left.?;
                node.left = left.right;
                left.right = node.recalc();
                return left.recalc();
            } else if (rh > lh + 1) {
                // right too tall: pivot
                var right = node.right.?;
                node.right = right.left;
                right.left = node.recalc();
                return right.recalc();
            } else {
                return node.recalc();
            }
        }

        pub fn insertNode(node: ?*Node, gpa: Allocator, key: K, value: V) Allocator.Error!*Node {
            if (node) |n| return insert(n, gpa, key, value);
            return Node.create(gpa, key, value);
        }

        pub fn find(node: ?*const Node, key: K) ?*const Node {
            var here = node;
            while (here) |n| {
                here = switch (cmp(key, n.key)) {
                    .lt => n.left,
                    .eq => return n,
                    .gt => n.right,
                };
            }
            return null;
        }

        pub fn deinit(self: *Node, gpa: Allocator) void {
            if (self.left) |left| left.deinit(gpa);
            if (self.right) |right| right.deinit(gpa);
            gpa.destroy(self);
        }

        const Iter = struct {
            stack: [STACK_SIZE]*const Node = undefined,
            sp: u32 = 0,

            pub fn init(root: ?*const Node) Iter {
                var self = Iter{};
                self.schedule(root);
                return self;
            }

            fn schedule(self: *Iter, node: ?*const Node) void {
                var current = node;
                while (current) |n| {
                    assert(self.sp < STACK_SIZE);
                    self.stack[self.sp] = n;
                    self.sp += 1;
                    current = n.left;
                }
            }

            pub fn next(self: *Iter) ?*const Node {
                if (self.sp == 0) return null;
                self.sp -= 1;
                const node = self.stack[self.sp];
                self.schedule(node.right);
                return node;
            }
        };

        pub fn entryIterator(node: *const Node) Iter {
            return Iter.init(node);
        }

        const KeyIter = struct {
            iter: Iter,
            pub fn next(self: *KeyIter) ?K {
                if (self.iter.next()) |n| return n.key;
                return null;
            }
        };

        pub fn keyIterator(node: *const Node) KeyIter {
            const iter = node.entryIterator();
            return KeyIter{ .iter = iter };
        }
    };
}

test TreeNode {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32, void, NumCompare(u32));
    var root = try Node.create(gpa, 10, {});
    defer root.deinit(gpa);
    try std.testing.expect(root.key == 10);
    root = try root.insertNode(gpa, 5, {});
    root = try root.insertNode(gpa, 15, {});
    const n1 = root.find(5);
    const n2 = root.find(15);
    const n3 = root.find(11);
    try std.testing.expect(n1.?.key == 5);
    try std.testing.expect(n2.?.key == 15);
    try std.testing.expect(n3 == null);
}

test "Tree balance" {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32, void, NumCompare(u32));
    var root = try Node.create(gpa, 1, {});
    defer root.deinit(gpa);

    for (2..1000) |i| {
        root = try root.insertNode(gpa, @intCast(i), {});
    }

    try std.testing.expectEqual(10, root.height);
}

test "iter" {
    const gpa = std.testing.allocator;
    const Node = TreeNode(u32, void, NumCompare(u32));
    var root = try Node.create(gpa, 10, {});
    defer root.deinit(gpa);
    root = try root.insertNode(gpa, 5, {});
    root = try root.insertNode(gpa, 15, {});
    root = try root.insertNode(gpa, 11, {});
    root = try root.insertNode(gpa, 1, {});

    var i = root.keyIterator();
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
const Order = std.math.Order;
