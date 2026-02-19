const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const Value = @import("value.zig").Value;

pub const ParseError = error{
    TooManyConstants,
    InvalidCharacter,
    OutOfMemory,
    ExpectedExpression,
};

pub const Parser = struct {
    current: Token,
    previous: Token,
    scanner: Scanner,
    chunk: *Chunk,
    had_error: bool,
    panic_mode: bool,

    pub fn init(source: []const u8) Parser {
        return Parser{
            .current = undefined,
            .previous = undefined,
            .scanner = Scanner.init(source),
            .chunk = undefined,
            .had_error = false,
            .panic_mode = false,
        };
    }

    pub fn compile(self: *Parser, chunk: *Chunk) ParseError!void {
        self.chunk = chunk;
        self.advance();
        try self.getExpr();

        self.consume(.EOF, "Expected end of expression.");
        try self.endCompiler();
    }

    fn getExpr(self: *Parser) ParseError!void {
        try self.parsePrecendence(Precedence.Assignment);
    }

    fn getNumber(self: *Parser) ParseError!void {
        const val = std.fmt.parseFloat(Value, self.previous.lexeme) catch {
            return ParseError.InvalidCharacter;
        };
        try self.emitConstant(val);
    }

    fn getGrouping(self: *Parser) ParseError!void {
        try self.getExpr();
        self.consume(.RIGHT_PAREN, "Expected ')' after expression.");
    }

    fn getBinary(self: *Parser) ParseError!void {
        const op = self.previous.token_type;
        const rule = ParseRule.getRule(op);
        try self.parsePrecendence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (op) {
            .PLUS => try self.emitOp(.OP_ADD),
            .MINUS => try self.emitOp(.OP_SUBTRACT),
            .STAR => try self.emitOp(.OP_MULTIPLY),
            .SLASH => try self.emitOp(.OP_DIVIDE),
            else => unreachable,
        }
    }

    fn getUnary(self: *Parser) ParseError!void {
        const op = self.previous.token_type;

        try self.parsePrecendence(Precedence.Unary);

        switch (op) {
            .MINUS => try self.emitOp(.OP_NEGATE),
            else => unreachable,
        }
    }

    fn parsePrecendence(self: *Parser, precedence: Precedence) ParseError!void {
        self.advance();
        const prefix_rule = ParseRule.getRule(self.previous.token_type).prefix;
        const p_rule = prefix_rule orelse return ParseError.ExpectedExpression;
        try p_rule(self);

        while (@intFromEnum(precedence) <= @intFromEnum(ParseRule.getRule(self.current.token_type).precedence)) {
            self.advance();
            const infix_rule = ParseRule.getRule(self.previous.token_type).infix;
            const i_rule = infix_rule orelse return ParseError.InvalidCharacter;
            try i_rule(self);
        }
    }

    fn emitOp(self: Parser, op: OpCode) ParseError!void {
        self.chunk.writeOp(op, self.previous.line) catch {
            return ParseError.OutOfMemory;
        };
    }

    fn emitByte(self: Parser, byte: u8) ParseError!void {
        self.chunk.write(u8, byte, self.previous.line) catch {
            return ParseError.OutOfMemory;
        };
    }

    fn emitConstant(self: Parser, value: Value) ParseError!void {
        try self.emitOp(OpCode.OP_CONSTANT);
        try self.emitByte(try makeConstant(self, value));
    }

    fn makeConstant(self: Parser, value: Value) ParseError!u8 {
        const addr = self.chunk.addConstant(value) catch {
            return ParseError.OutOfMemory;
        };
        if (addr > std.math.maxInt(u8)) {
            return ParseError.TooManyConstants;
        }

        return @intCast(addr);
    }

    fn endCompiler(self: Parser) !void {
        self.emitOp(OpCode.OP_RETURN) catch {
            return ParseError.OutOfMemory;
        };
    }

    fn advance(self: *Parser) void {
        self.previous = self.current;

        while (true) {
            self.current = self.scanner.scanToken();
            if (self.current.token_type != .ERROR) {
                break;
            }

            self.reportErrorAtCurrent(self.current.lexeme);
        }
    }

    fn consume(self: *Parser, token_type: Token.Type, msg: []const u8) void {
        if (self.current.token_type == token_type) {
            self.advance();
            return;
        }

        self.reportErrorAtCurrent(msg);
    }

    fn reportErrorAtCurrent(self: *Parser, msg: []const u8) void {
        self.reportErrorAt(self.current, msg);
    }

    fn reportError(self: *Parser, msg: []const u8) void {
        self.reportErrorAt(self.previous, msg);
    }

    fn reportErrorAt(self: *Parser, token: Token, msg: []const u8) void {
        if (self.panic_mode) {
            return;
        }
        self.panic_mode = true;

        std.log.err("[line {}] Error", .{token.line});

        switch (token.token_type) {
            .EOF => std.log.err(" at end", .{}),
            .ERROR => {},
            else => std.log.err(" at {s}", .{token.lexeme}),
        }

        std.log.err(": {s}", .{msg});
        self.had_error = true;
    }
};

const Precedence = enum(u8) {
    None,
    Assignment,
    Or,
    And,
    Equality,
    Comparison,
    Term,
    Factor,
    Unary,
    Call,
    Primary,
};

const ParseRule = struct {
    prefix: ParseFn,
    infix: ParseFn,
    precedence: Precedence,

    const ParseFn = ?*const fn (*Parser) ParseError!void;
    fn init(prefix: ParseFn, infix: ParseFn, precedence: Precedence) ParseRule {
        return ParseRule{
            .prefix = prefix,
            .infix = infix,
            .precedence = precedence,
        };
    }

    const group = Parser.getGrouping;
    const unary = Parser.getUnary;
    const binary = Parser.getBinary;
    const number = Parser.getNumber;
    const p = Precedence;
    // zig fmt: off
    fn getRule(token_type: Token.Type) ParseRule {
        return switch (token_type) {
            .LEFT_PAREN    => init(group,     null,   p.None),
            .RIGHT_PAREN   => init(null,      null,   p.None),
            .LEFT_BRACE    => init(null,      null,   p.None),
            .RIGHT_BRACE   => init(null,      null,   p.None),
            .COMMA         => init(null,      null,   p.None),
            .DOT           => init(null,      null,   p.None),
            .MINUS         => init(unary,     binary, p.Term),
            .PLUS          => init(null,      binary, p.Term),
            .SEMICOLON     => init(null,      null,   p.None),
            .SLASH         => init(null,      binary, p.Factor),
            .STAR          => init(null,      binary, p.Factor),
            .BANG          => init(unary,     null,   p.None),
            .BANG_EQUAL    => init(null,      binary, p.Comparison),
            .EQUAL         => init(null,      null,   p.None),
            .EQUAL_EQUAL   => init(null,      binary, p.Comparison),
            .GREATER       => init(null,      binary, p.Comparison),
            .GREATER_EQUAL => init(null,      binary, p.Comparison),
            .LESS          => init(null,      binary, p.Comparison),
            .LESS_EQUAL    => init(null,      binary, p.Comparison),
            .IDENTIFIER    => init(null,      null,   p.None),
            .STRING        => init(null,      null,   p.None),
            .NUMBER        => init(number,    null,   p.None),
            .AND           => init(null,      null,   p.None),
            .CLASS         => init(null,      null,   p.None),
            .ELSE          => init(null,      null,   p.None),
            .FALSE         => init(null,      null,   p.None),
            .FUN           => init(null,      null,   p.None),
            .FOR           => init(null,      null,   p.None),
            .IF            => init(null,      null,   p.None),
            .NIL           => init(null,      null,   p.None),
            .OR            => init(null,      null,   p.None),
            .PRINT         => init(null,      null,   p.None),
            .RETURN        => init(null,      null,   p.None),
            .SUPER         => init(null,      null,   p.None),
            .THIS          => init(null,      null,   p.None),
            .TRUE          => init(null,      null,   p.None),
            .VAR           => init(null,      null,   p.None),
            .WHILE         => init(null,      null,   p.None),
            .EOF           => init(null,      null,   p.None),
            .ERROR         => init(null,      null,   p.None),
            
        };

    }
};
