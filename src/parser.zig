const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const OpCode = @import("op_code.zig").OpCode;
const Value = @import("value.zig").Value;

pub const ParseError = error {
    TooManyConstants,
    InvalidCharacter,
    OutOfMemory,
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
        self.advance();
        try self.getNumber();
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

    fn getUnary(self: *Parser) ParseError!void {
        const op_type = self.previous.token_type;

        try self.getExpr();

        switch (op_type) {
            .MINUS => self.emitOp(.OP_NEGATE),
            else => unreachable,
        }
    }

    fn parsePrecendence(prec: Precedence) void {

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
