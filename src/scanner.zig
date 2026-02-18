const std = @import("std");
const Token = @import("token.zig").Token;

pub const Scanner = struct {
    start: usize,
    current: usize,
    source: []const u8,
    line: usize,

    pub fn init(source: []const u8) Scanner {
        return Scanner{ .start = 0, .current = 0, .source = source, .line = 1 };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;

        if (self.isAtEnd()) {
            return self.makeToken(.EOF);
        }

        const c = self.advance();

        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.makeIdentifier();
        }

        if (std.ascii.isDigit(c)) {
            return self.makeNumber();
        }

        switch (c) {
            '(' => return self.makeToken(.LEFT_PAREN),
            ')' => return self.makeToken(.RIGHT_PAREN),
            '{' => return self.makeToken(.LEFT_BRACE),
            '}' => return self.makeToken(.RIGHT_BRACE),
            ';' => return self.makeToken(.SEMICOLON),
            ',' => return self.makeToken(.COMMA),
            '.' => return self.makeToken(.DOT),
            '-' => return self.makeToken(.MINUS),
            '+' => return self.makeToken(.PLUS),
            '/' => return self.makeToken(.SLASH),
            '*' => return self.makeToken(.STAR),

            '!' => {
                const tknType: Token.Type = if (self.match('=')) .BANG_EQUAL else .BANG;
                return self.makeToken(tknType);
            },
            '=' => {
                const tknType: Token.Type = if (self.match('=')) .EQUAL_EQUAL else .EQUAL;
                return self.makeToken(tknType);
            },
            '>' => {
                const tknType: Token.Type = if (self.match('=')) .GREATER_EQUAL else .GREATER;
                return self.makeToken(tknType);
            },
            '<' => {
                const tknType: Token.Type = if (self.match('=')) .LESS_EQUAL else .LESS;
                return self.makeToken(tknType);
            },

            '"' => return self.makeString(),
            else => {},
        }

        return self.makeError("Unexpected character.");
    }

    fn isAtEnd(self: Scanner) bool {
        return self.current >= self.source.len;
    }

    // zig fmt: off
    fn makeToken(self: Scanner, token_type: Token.Type) Token {
        return Token{
            .token_type = token_type,
            .lexeme = self.source[self.start..self.current],
            .line = self.line
        };
    }

    fn makeError(self: Scanner, msg: []const u8) Token {
        return Token{
            .token_type = .ERROR,
            .lexeme = msg,
            .line = self.line,
        };
    }

    fn makeString(self: *Scanner) Token {
        while (self.peek() != '=' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            const msg = "Unterminated string.";
            return self.makeError(msg[0..]);
        }

        // closing quote
        _ = self.advance();
        return self.makeToken(.STRING);
    }

    fn makeNumber(self: *Scanner) Token {
        while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
            _ = self.advance();
        }

        if (!self.isAtEnd() and self.peek() == '.' and 
            std.ascii.isDigit(self.peekNext())) {
            // consume the '.'
            _ = self.advance();

            while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        return self.makeToken(.NUMBER);
    }

    fn makeIdentifier(self: *Scanner) Token {
        while (std.ascii.isAlphabetic(self.peek()) or
            std.ascii.isDigit(self.peek()) or self.peek() == '_')
        {
            _ = self.advance();
        }

        return self.makeToken(self.getIdentifierType());
    }

    fn peek(self: Scanner) u8 {
        return self.source[self.current];
    }

    fn peekNext(self: Scanner) u8 {
        if (self.isAtEnd()) {
            return 0;
        }
        return self.source[self.current + 1];
    }

    fn advance(self: *Scanner) u8 {
        const c = self.peek();
        self.current += 1;
        return c;
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) {
            return false;
        }

        if (self.peek() != expected) {
            return false;
        }

        self.current += 1;
        return true;
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            if (self.isAtEnd()) {
                return;
            }

            const c = self.peek();
            if (std.ascii.isWhitespace(c)) {
                _ = self.advance();
                if (c == '\n') {
                    self.line += 1;
                }
                continue;
            }

            if (c == '/' and self.peekNext() == '/') {
                while (self.peek() != '\n' and !self.isAtEnd()) {
                    _ = self.advance();
                }
                continue;
            }

            return;
        }
    }

    fn getIdentifierType(self: Scanner) Token.Type {
        switch (self.source[self.start]) {
            'a' => return self.checkKeyword(1, "nd", .AND),
            'c' => return self.checkKeyword(1, "lass", .CLASS),
            'e' => return self.checkKeyword(1, "lse", .ELSE),
            'f' => if (self.current - self.start > 1) {
                switch (self.source[self.start + 1]) {
                    'a' => return self.checkKeyword(2, "lse", .FALSE),
                    'o' => return self.checkKeyword(2, "r", .FOR),
                    else => {},
                }
            },
            'i' => return self.checkKeyword(1, "f", .IF),
            'n' => return self.checkKeyword(1, "il", .NIL),
            'o' => return self.checkKeyword(1, "r", .OR),
            'p' => return self.checkKeyword(1, "rint", .PRINT),
            'r' => return self.checkKeyword(1, "eturn", .RETURN),
            's' => return self.checkKeyword(1, "uper", .SUPER),
            't' => if (self.current - self.start > 1) {
                switch (self.source[self.start + 1]) {
                    'h' => return self.checkKeyword(2, "is", .THIS),
                    'r' => return self.checkKeyword(2, "ue", .TRUE),
                    else => {},
                }
            },
            'v' => return self.checkKeyword(1, "ar", .VAR),
            'w' => return self.checkKeyword(1, "hile", .WHILE),
            else => {},
        }

        return .IDENTIFIER;
    }

    fn checkKeyword(self: Scanner, idx: usize, rest: []const u8, token_type: Token.Type) Token.Type {
        if (self.current - self.start == rest.len + idx and
            std.mem.startsWith(u8, self.source[self.start + idx ..], rest))
        {
            return token_type;
        }
        return .IDENTIFIER;
    }
};
