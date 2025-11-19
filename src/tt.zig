fn isSymbol(chr: u8) bool {
    return std.ascii.isAlphanumeric(chr) or chr == '_';
}

pub const TokenIter = struct {
    const Self = @This();

    name: []const u8,
    src: []const u8,
    pos: u32 = 0,
    line_number: u32 = 1,
    line_start: u32 = 0,
    state: enum { TEXT, EXPR } = .TEXT,

    pub const Operator = enum { PERCENT, DOT, EQUALS };

    pub const Token = union(enum) {
        literal: []const u8,
        symbol: []const u8,
        string: []const u8,
        end_expr,
        operator: Operator,
    };

    pub const Location = struct {
        name: []const u8,
        line: u32, // 1 based
        column: u32, // 0 based
    };

    pub fn init(name: []const u8, src: []const u8) Self {
        return Self{ .name = name, .src = src };
    }

    pub fn getLocation(self: *const Self) Location {
        return .{
            .name = self.name,
            .line = self.line_number,
            .column = self.pos - self.line_start,
        };
    }

    pub fn eof(self: *const Self) bool {
        return self.pos == self.src.len;
    }

    fn peek(self: *const Self) u8 {
        std.debug.assert(!self.eof());
        return self.src[self.pos];
    }

    fn advance(self: *Self) u8 {
        std.debug.assert(!self.eof());
        const nc = self.peek();
        self.pos += 1;
        if (nc == '\n') {
            @branchHint(.unlikely);
            self.line_number += 1;
            self.line_start = self.pos;
        }
        return nc;
    }

    fn skipSpace(self: *Self) void {
        while (!self.eof()) {
            if (!std.ascii.isWhitespace(self.peek())) break;
            _ = self.advance();
        }
    }

    pub fn next(self: *Self) ?Token {
        if (self.eof()) return null;
        return switch (self.state) {
            .TEXT => text: {
                const start = self.pos;

                const text = nt: while (!self.eof()) {
                    const nc = self.advance();
                    if (nc == '[' and !self.eof() and self.advance() == '%') {
                        self.state = .EXPR;
                        break :nt self.src[start .. self.pos - 2];
                    }
                } else {
                    break :nt self.src[start..self.pos];
                };

                break :text if (text.len > 0) .{ .literal = text } else self.next();
            },
            .EXPR => expr: {
                self.skipSpace();
                if (self.eof()) break :expr null;

                switch (self.advance()) {
                    'a'...'z', 'A'...'Z', '_' => {
                        const start = self.pos - 1;
                        while (!self.eof() and isSymbol(self.peek()))
                            _ = self.advance();
                        break :expr .{ .symbol = self.src[start..self.pos] };
                    },
                    '"', '\'' => |qc| {
                        const start = self.pos;
                        while (!self.eof()) {
                            const sc = self.advance();
                            if (sc == qc) break;
                            if (sc == '\\' and !self.eof()) _ = self.advance();
                        }
                        break :expr .{ .string = self.src[start .. self.pos - 1] };
                    },
                    '%' => {
                        if (!self.eof() and self.peek() == ']') {
                            _ = self.advance();
                            self.state = .TEXT;
                            break :expr .{ .end_expr = {} };
                        }

                        break :expr .{ .operator = .PERCENT };
                    },
                    '.' => break :expr .{ .operator = .DOT },
                    '=' => break :expr .{ .operator = .EQUALS },
                    else => unreachable,
                }
            },
        };
    }
};

test TokenIter {
    const gpa = testing.allocator;
    const T = TokenIter.Token;
    const cases = &[_]struct { src: []const u8, want: []const T }{
        .{ .src = "", .want = &[_]T{} },
        .{ .src = "hello", .want = &[_]T{.{ .literal = "hello" }} },
        .{ .src = "hello [% %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .end_expr = {} },
            .{ .literal = " world" },
        } },
        .{ .src = "hello [% foo %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .symbol = "foo" },
            .{ .end_expr = {} },
            .{ .literal = " world" },
        } },
        .{ .src = "hello [% foo.bar %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .symbol = "foo" },
            .{ .operator = .DOT },
            .{ .symbol = "bar" },
            .{ .end_expr = {} },
            .{ .literal = " world" },
        } },
        .{ .src = "[% foo = \"Hello\" %]", .want = &[_]T{
            .{ .symbol = "foo" },
            .{ .operator = .EQUALS },
            .{ .string = "Hello" },
            .{ .end_expr = {} },
        } },
    };

    for (cases) |case| {
        var iter = TokenIter.init("test", case.src);
        var tokens: std.ArrayList(T) = .empty;
        defer tokens.deinit(gpa);
        while (iter.next()) |t| {
            try tokens.append(gpa, t);
        }
        const got = try tokens.toOwnedSlice(gpa);
        defer gpa.free(got);
        try testing.expectEqualDeep(case.want, got);
    }
}

pub const ASTNode = union(enum) {
    const Node = @This();

    root: []const Node,
    literal: []const u8,
};

pub const TT = struct {
    const Self = @This();
    pub fn parse(self: *const Self, gpa: Allocator, tpl: []const u8) !ASTNode {
        _ = self;
        _ = gpa;
        return .{ .literal = tpl };
    }
};

test TT {
    const gpa = testing.allocator;
    const tt = TT{};
    const ast = try tt.parse(gpa, "Hello");
    // std.debug.print("root: {}\n", .{ast});
    try testing.expectEqualDeep(ASTNode{ .literal = "Hello" }, ast);
}

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
