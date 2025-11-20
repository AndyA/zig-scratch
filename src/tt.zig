fn isSymbol(chr: u8) bool {
    return std.ascii.isAlphanumeric(chr) or chr == '_';
}

const TTError = error{
    MissingQuote,
    UnexpectedEOF,
    SyntaxError,
};

pub const TokenIter = struct {
    const Self = @This();

    name: []const u8,
    src: []const u8,
    pos: u32 = 0,
    line_number: u32 = 1,
    line_start: u32 = 0,
    state: enum { TEXT, START, EXPR } = .TEXT,

    pub const Keyword = enum {
        @"%",
        @".",
        @"=",
        @"+",
        @"-",
        @"_",
        AND,
        BLOCK,
        BREAK,
        CALL,
        CASE,
        CATCH,
        CLEAR,
        DEFAULT,
        DIV,
        ELSE,
        ELSIF,
        END,
        FILTER,
        FINAL,
        FOR,
        FOREACH,
        GET,
        IF,
        INCLUDE,
        INSERT,
        LAST,
        MACRO,
        META,
        MOD,
        NEXT,
        NOT,
        OR,
        PERL,
        PLUGIN,
        PROCESS,
        RAWPERL,
        RETURN,
        SET,
        STEP,
        STOP,
        SWITCH,
        THROW,
        TO,
        TRY,
        UNLESS,
        USE,
        WHILE,
        WRAPPER,
    };
    const ExprFrame = struct { swallow: bool };

    pub const Token = union(enum) {
        literal: []const u8,
        symbol: []const u8,
        string: []const u8,
        start: ExprFrame,
        end: ExprFrame,
        keyword: Keyword,
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
        assert(!self.eof());
        return self.src[self.pos];
    }

    fn available(self: *const Self) usize {
        return self.src.len - self.pos;
    }

    fn slice(self: *const Self, len: usize) []const u8 {
        assert(self.available() >= len);
        return self.src[self.pos .. self.pos + len];
    }

    fn isNext(self: *Self, comptime want: []const u8) bool {
        if (self.available() < want.len)
            return false;
        if (std.mem.eql(u8, want, self.slice(want.len))) {
            self.pos += want.len; // assumes no newlines in want
            return true;
        }
        return false;
    }

    fn advance(self: *Self) u8 {
        assert(!self.eof());
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

    pub fn next(self: *Self) TTError!?Token {
        if (self.eof()) return null;
        return parse: switch (self.state) {
            .TEXT => text: {
                const start = self.pos;

                const text = nt: while (!self.eof()) {
                    const nc = self.advance();
                    if (nc == '[' and !self.eof() and self.advance() == '%') {
                        self.state = .START;
                        break :nt self.src[start .. self.pos - 2];
                    }
                } else {
                    break :nt self.src[start..self.pos];
                };

                if (text.len == 0) continue :parse self.state;
                break :text .{ .literal = text };
            },
            .START => es: {
                self.state = .EXPR;
                if (!self.eof()) {
                    const nc = self.peek();
                    if (nc == '-' or nc == '+') {
                        _ = self.advance();
                        break :es .{ .start = .{ .swallow = true } };
                    }
                }
                break :es .{ .start = .{ .swallow = false } };
            },
            .EXPR => expr: {
                self.skipSpace();
                if (self.eof()) break :expr error.UnexpectedEOF;

                switch (self.advance()) {
                    'a'...'z', 'A'...'Z', '_' => {
                        const start = self.pos - 1;
                        while (!self.eof() and isSymbol(self.peek()))
                            _ = self.advance();
                        const sym = self.src[start..self.pos];
                        if (std.meta.stringToEnum(Keyword, sym)) |op|
                            break :expr .{ .keyword = op };
                        break :expr .{ .symbol = sym };
                    },
                    '"', '\'' => |qc| {
                        const start = self.pos;
                        while (!self.eof()) {
                            const sc = self.advance();
                            if (sc == qc) break;
                            if (sc == '\\') {
                                if (self.eof())
                                    break :expr error.MissingQuote;
                                _ = self.advance();
                            }
                        } else {
                            break :expr error.MissingQuote;
                        }
                        break :expr .{ .string = self.src[start .. self.pos - 1] };
                    },
                    '+', '-' => |pm| {
                        if (self.isNext("%]")) {
                            self.state = .TEXT;
                            break :expr .{ .end = .{ .swallow = true } };
                        }
                        switch (pm) {
                            '+' => break :expr .{ .keyword = .@"+" },
                            '-' => break :expr .{ .keyword = .@"-" },
                            else => unreachable,
                        }
                    },
                    '%' => {
                        if (self.isNext("]")) {
                            self.state = .TEXT;
                            break :expr .{ .end = .{ .swallow = false } };
                        }

                        break :expr .{ .keyword = .@"%" };
                    },
                    '.' => break :expr .{ .keyword = .@"." },
                    '=' => break :expr .{ .keyword = .@"=" },
                    else => break :expr error.SyntaxError,
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
        .{ .src = "[% %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[%- %]", .want = &[_]T{
            .{ .start = .{ .swallow = true } },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[% -%]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .end = .{ .swallow = true } },
        } },
        .{ .src = "[%- -%]", .want = &[_]T{
            .{ .start = .{ .swallow = true } },
            .{ .end = .{ .swallow = true } },
        } },
        .{ .src = "[%---%]", .want = &[_]T{
            .{ .start = .{ .swallow = true } },
            .{ .keyword = .@"-" },
            .{ .end = .{ .swallow = true } },
        } },
        .{ .src = "[%+ %]", .want = &[_]T{
            .{ .start = .{ .swallow = true } },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[% + %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .keyword = .@"+" },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[% _ %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .keyword = ._ },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[% +%]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .end = .{ .swallow = true } },
        } },
        .{ .src = "[% '[%' %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .string = "[%" },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "hello [% %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .start = .{ .swallow = false } },
            .{ .end = .{ .swallow = false } },
            .{ .literal = " world" },
        } },
        .{ .src = "hello [% foo %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .start = .{ .swallow = false } },
            .{ .symbol = "foo" },
            .{ .end = .{ .swallow = false } },
            .{ .literal = " world" },
        } },
        .{ .src = "hello [% foo.bar %] world", .want = &[_]T{
            .{ .literal = "hello " },
            .{ .start = .{ .swallow = false } },
            .{ .symbol = "foo" },
            .{ .keyword = .@"." },
            .{ .symbol = "bar" },
            .{ .end = .{ .swallow = false } },
            .{ .literal = " world" },
        } },
        .{ .src = "[% foo = \"Hello\" %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .symbol = "foo" },
            .{ .keyword = .@"=" },
            .{ .string = "Hello" },
            .{ .end = .{ .swallow = false } },
        } },
        .{ .src = "[% INCLUDE foo %]", .want = &[_]T{
            .{ .start = .{ .swallow = false } },
            .{ .keyword = .INCLUDE },
            .{ .symbol = "foo" },
            .{ .end = .{ .swallow = false } },
        } },
    };

    for (cases) |case| {
        var iter = TokenIter.init("test", case.src);
        var tokens: std.ArrayList(T) = .empty;
        defer tokens.deinit(gpa);
        while (try iter.next()) |t| {
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
const assert = std.debug.assert;
