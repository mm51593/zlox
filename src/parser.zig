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
    had_error: bool,
    panic_mode: bool,

    pub fn init(source: []const u8) Parser {
        return Parser{
            .current = undefined,
            .previous = undefined,
            .scanner = Scanner.init(source),
            .had_error = false,
            .panic_mode = false,
        };
    }

    pub fn compile(self: *Parser, chunk: *Chunk) ParseError!void {
        self.advance();
        try self.getExpr(chunk);
        self.consume(.EOF, "Expected end of expression.");
        try self.endCompiler(chunk);
    }

    fn getExpr(self: *Parser, chunk: *Chunk) ParseError!void {
        self.advance();
        try self.getNumber(chunk);
    }

    fn getNumber(self: *Parser, chunk: *Chunk) ParseError!void {
        const val = std.fmt.parseFloat(Value, self.previous.lexeme) catch {
            return ParseError.InvalidCharacter;
        };
        try self.emitConstant(chunk, val);
    }

    fn emitOp(self: Parser, chunk: *Chunk, op: OpCode) ParseError!void {
        chunk.writeOp(op, self.previous.line) catch {
            return ParseError.OutOfMemory;
        };
    }

    fn emitByte(self: Parser, chunk: *Chunk, byte: u8) ParseError!void {
        chunk.write(u8, byte, self.previous.line) catch {
            return ParseError.OutOfMemory;
        };
    }

    fn emitConstant(self: Parser, chunk: *Chunk, value: Value) ParseError!void {
        try self.emitOp(chunk, OpCode.OP_CONSTANT);
        try self.emitByte(chunk, try makeConstant(chunk, value));
    }

    fn makeConstant(chunk: *Chunk, value: Value) ParseError!u8 {
        const addr = chunk.addConstant(value) catch {
            return ParseError.OutOfMemory;
        };
        if (addr > std.math.maxInt(u8)) {
            return ParseError.TooManyConstants;
        }

        return @intCast(addr);
    }

    fn endCompiler(self: Parser, chunk: *Chunk) !void {
        self.emitOp(chunk, OpCode.OP_RETURN) catch {
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
