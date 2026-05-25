const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const Value = @import("value.zig").Value;
const object = @import("object.zig");

pub const Parser = struct {
    pub const Error = union(enum) {
        TooManyConstants,
        InvalidCharacter,
        NotANumber,
        UnexpectedToken: struct { expected: Token.Type },
        ExpectedExpression,
    };

    pub const Diagnostic = struct {
        error_type: Error,
        token: Token,
    };

    alloc: std.mem.Allocator,
    obj_list: object.ObjectList,
    current: Token,
    previous: Token,
    diagnostics: std.ArrayList(Diagnostic),
    _chunk: ?Chunk,
    _scanner: Scanner,

    pub fn init(alloc: std.mem.Allocator, obj_list: object.ObjectList) !Parser {
        return Parser{
            .alloc = alloc,
            .obj_list = obj_list,
            .current = undefined,
            .previous = undefined,
            .diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 4),
            ._chunk = undefined,
            ._scanner = undefined,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.diagnostics.deinit(self.alloc);
    }

    pub fn compile(self: *Parser, alloc: std.mem.Allocator, scanner: Scanner) !?Chunk {
        self._chunk = try Chunk.init(alloc);
        self._scanner = scanner;

        try self.advance();
        try self.getExpr();

        try self.consume(.EOF);
        try self.endCompiler();

        return self._chunk;
    }

    fn getExpr(self: *Parser) !void {
        try self.parsePrecendence(.Asgn);
    }

    fn getNum(self: *Parser) !void {
        const val = std.fmt.parseFloat(f64, self.previous.lexeme) catch {
            return try self.reportError(.NotANumber);
        };
        try self.emitConstant(Value{ .Number = val });
    }

    fn getGrp(self: *Parser) !void {
        try self.getExpr();
        try self.consume(.RIGHT_PAREN);
    }

    fn getBin(self: *Parser) !void {
        const op = self.previous.token_type;
        const rule = ParseRule.getRule(op);
        const next_precedence: Precedence = @enumFromInt(@intFromEnum(rule.prec) + 1);
        try self.parsePrecendence(next_precedence);

        switch (op) {
            .PLUS => try self.emitOp(.OP_ADD),
            .MINUS => try self.emitOp(.OP_SUBTRACT),
            .STAR => try self.emitOp(.OP_MULTIPLY),
            .SLASH => try self.emitOp(.OP_DIVIDE),
            .BANG_EQUAL => {
                try self.emitOp(.OP_EQUAL);
                try self.emitOp(.OP_NOT);
            },
            .EQUAL_EQUAL => try self.emitOp(.OP_EQUAL),
            .GREATER => try self.emitOp(.OP_GREATER),
            .GREATER_EQUAL => {
                try self.emitOp(.OP_LESS);
                try self.emitOp(.OP_NOT);
            },
            .LESS => try self.emitOp(.OP_LESS),
            .LESS_EQUAL => {
                try self.emitOp(.OP_GREATER);
                try self.emitOp(.OP_NOT);
            },
            else => unreachable,
        }
    }

    fn getLit(self: *Parser) !void {
        switch (self.previous.token_type) {
            .TRUE => try self.emitOp(.OP_TRUE),
            .FALSE => try self.emitOp(.OP_FALSE),
            .NIL => try self.emitOp(.OP_NIL),
            else => unreachable,
        }
    }

    fn getUnar(self: *Parser) !void {
        const op = self.previous.token_type;

        try self.parsePrecendence(.Unar);

        switch (op) {
            .MINUS => try self.emitOp(.OP_NEGATE),
            .BANG => try self.emitOp(.OP_NOT),
            else => unreachable,
        }
    }

    fn getStr(self: *Parser) !void {
        const chars = try self.alloc.alloc(u8, self.previous.lexeme.len - 2);
        @memcpy(chars, self.previous.lexeme[1..self.previous.lexeme.len - 1]);
        const obj_str = try object.ObjString.init(self.alloc, chars);
        self.obj_list.insert(&obj_str.obj);

        const val = Value{ .Obj = &obj_str.obj };
        try self.emitConstant(val);
    }

    fn parsePrecendence(self: *Parser, prec: Precedence) !void {
        try self.advance();
        const prefix_rule = ParseRule.getRule(self.previous.token_type).prefix;

        if (prefix_rule) |valid_prefix_rule| {
            try valid_prefix_rule(self);
        } else {
            return try self.reportError(.ExpectedExpression);
        }

        while (prec.cmp(ParseRule.getRule(self.current.token_type).prec) <= 0) {
            try self.advance();
            const infix_rule = ParseRule.getRule(self.previous.token_type).infix;
            if (infix_rule) |valid_infix_rule| {
                try valid_infix_rule(self);
            } else {
                return try self.reportError(.ExpectedExpression);
            }
        }
    }

    fn emitOp(self: *Parser, op: OpCode) !void {
        if (self._chunk) |*chunk| {
            try chunk.writeOp(op, self.previous.line);
        }
    }

    fn emitByte(self: *Parser, byte: u8) !void {
        if (self._chunk) |*chunk| {
            try chunk.write(u8, byte, self.previous.line);
        }
    }

    fn emitConstant(self: *Parser, value: Value) !void {
        try self.emitOp(OpCode.OP_CONSTANT);
        try self.emitByte(try makeConstant(self, value));
    }

    fn makeConstant(self: *Parser, value: Value) !u8 {
        const addr = if (self._chunk) |*chunk|
            try chunk.addConstant(value)
        else
            0;

        if (addr > std.math.maxInt(u8)) {
            try self.reportError(.TooManyConstants);
        }

        return @intCast(addr);
    }

    fn endCompiler(self: *Parser) !void {
        try self.emitOp(OpCode.OP_RETURN);
    }

    fn advance(self: *Parser) !void {
        self.previous = self.current;

        while (true) {
            self.current = self._scanner.scanToken();
            if (self.current.token_type != .ERROR) {
                break;
            }

            try self.reportErrorAtCurrent(.InvalidCharacter);
        }
    }

    fn consume(self: *Parser, token_type: Token.Type) !void {
        if (self.current.token_type == token_type) {
            try self.advance();
            return;
        }

        try self.reportErrorAtCurrent(.{ .UnexpectedToken = .{ .expected = token_type } });
    }

    fn reportErrorAtCurrent(self: *Parser, err: Error) !void {
        try self.reportErrorAt(self.current, err);
    }

    fn reportError(self: *Parser, err: Error) !void {
        try self.reportErrorAt(self.previous, err);
    }

    fn reportErrorAt(self: *Parser, token: Token, err: Error) !void {
        self.deallocChunk();

        try self.diagnostics.append(self.alloc, Diagnostic{ .error_type = err, .token = token });
    }

    fn deallocChunk(self: *Parser) void {
        if (self._chunk) |*chunk| {
            chunk.deinit();
        }

        self._chunk = null;
    }
};

const Precedence = enum(i8) {
    None,
    Asgn,
    Or,
    And,
    Eql,
    Cmp,
    Term,
    Fact,
    Unar,
    Call,
    Prim,

    fn cmp(self: Precedence, other: Precedence) i8 {
        return @intFromEnum(self) - @intFromEnum(other);
    }
};

const ParseFn = *const fn (*Parser) anyerror!void;
const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    prec: Precedence,

    const p = Parser;
    const q = Precedence;

    fn rule(prefix: ?ParseFn, infix: ?ParseFn, prec: Precedence) ParseRule {
        return .{ .prefix = prefix, .infix = infix, .prec = prec };
    }

    const rules = blk: {
        var table: [std.enums.values(Token.Type).len]ParseRule = undefined;

        for (std.enums.values(Token.Type)) |tag| {
            table[@intFromEnum(tag)] = switch (tag) {
                // zig fmt: off
                .LEFT_PAREN    => rule(p.getGrp,  null,     .None),
                .RIGHT_PAREN   => rule(null,      null,     .None),
                .LEFT_BRACE    => rule(null,      null,     .None),
                .RIGHT_BRACE   => rule(null,      null,     .None),
                .COMMA         => rule(null,      null,     .None),
                .DOT           => rule(null,      null,     .None),
                .MINUS         => rule(p.getUnar, p.getBin, .Term),
                .PLUS          => rule(null,      p.getBin, .Term),
                .SEMICOLON     => rule(null,      null,     .None),
                .SLASH         => rule(null,      p.getBin, .Fact),
                .STAR          => rule(null,      p.getBin, .Fact),
                .BANG          => rule(p.getUnar, null,     .None),
                .BANG_EQUAL    => rule(null,      p.getBin, .Eql ),
                .EQUAL         => rule(null,      null,     .None),
                .EQUAL_EQUAL   => rule(null,      p.getBin, .Eql ),
                .GREATER       => rule(null,      p.getBin, .Cmp ),
                .GREATER_EQUAL => rule(null,      p.getBin, .Cmp ),
                .LESS          => rule(null,      p.getBin, .Cmp ),
                .LESS_EQUAL    => rule(null,      p.getBin, .Cmp ),
                .IDENTIFIER    => rule(null,      null,     .None),
                .STRING        => rule(p.getStr,  null,     .None),
                .NUMBER        => rule(p.getNum,  null,     .None),
                .AND           => rule(null,      null,     .None),
                .CLASS         => rule(null,      null,     .None),
                .ELSE          => rule(null,      null,     .None),
                .FALSE         => rule(p.getLit,  null,     .None),
                .FUN           => rule(null,      null,     .None),
                .FOR           => rule(null,      null,     .None),
                .IF            => rule(null,      null,     .None),
                .NIL           => rule(p.getLit,  null,     .None),
                .OR            => rule(null,      null,     .None),
                .PRINT         => rule(null,      null,     .None),
                .RETURN        => rule(null,      null,     .None),
                .SUPER         => rule(null,      null,     .None),
                .THIS          => rule(null,      null,     .None),
                .TRUE          => rule(p.getLit,  null,     .None),
                .VAR           => rule(null,      null,     .None),
                .WHILE         => rule(null,      null,     .None),
                .EOF           => rule(null,      null,     .None),
                .ERROR         => rule(null,      null,     .None),
            };
        }

        break :blk table;
    };

    fn getRule(token_type: Token.Type) ParseRule {
        return rules[@intFromEnum(token_type)];
    }
};
