const std = @import("std");

const Allocator = @import("std").mem.Allocator;
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const Scanner = @import("scanner.zig").Scanner;
const Token = @import("token.zig").Token;
const Value = @import("value.zig").Value;
const ObjFunction = @import("object.zig").ObjFunction;
const ObjString = @import("object.zig").ObjString;
const ObjectList = @import("object.zig").ObjectList;
const StringTable = @import("string_table.zig").StringTable;
const Local = @import("local.zig").Local;

const ENTRY_POINT = "";
const MAX_LOCAL_COUNT = std.math.maxInt(u8);

pub const Parser = struct {
    pub const Error = union(enum) {
        TooManyConstants,
        InvalidCharacter,
        NotANumber,
        UnexpectedToken: struct { expected: Token.Type },
        ExpectedExpression,
        InvalidAsignmentTarget,
        TooManyLocals,
        DuplicateLocalDeclaration,
        ReadingInInitializer,
        JumpTooBig,
        TooManyParameters,
    };

    pub const Diagnostic = struct {
        error_type: Error,
        token: Token,
    };

    pub const Scope = struct {
        enclosing: ?*Scope,
        locals: [MAX_LOCAL_COUNT]Local,
        local_count: u8,
        depth: u8,
        function: *ObjFunction,
        fun_type: ObjFunction.Type,

        fn init(enclosing: ?*Scope, fun_type: ObjFunction.Type, fun: *ObjFunction) Scope {
            return .{
                .enclosing = enclosing,
                .locals = undefined,
                .local_count = 0,
                .depth = 0,
                .function = fun,
                .fun_type = fun_type,
            };
        }

        fn create(alloc: Allocator, enclosing: ?*Scope, fun_type: ObjFunction.Type, fun: *ObjFunction) !*Scope {
            const p = try alloc.create(Scope);
            p.* = Scope.init(enclosing, fun_type, fun);
            return p;
        }

        fn destroy(self: *Scope, alloc: Allocator) void {
            alloc.destroy(self);
        }

        fn getLastLocal(self: *Scope) *Local {
            return &self.locals[self.local_count];
        }
    };

    alloc: std.mem.Allocator,
    obj_list: *ObjectList,
    current: Token,
    previous: Token,
    diagnostics: std.ArrayList(Diagnostic),
    panic_mode: bool,
    str_table: *StringTable,
    scope: *Scope,

    _scanner: Scanner,

    pub fn init(alloc: Allocator, obj_list: *ObjectList, str_table: *StringTable) !Parser {
        const p = Parser{
            .alloc = alloc,
            .obj_list = obj_list,
            .current = undefined,
            .previous = undefined,
            .diagnostics = try std.ArrayList(Diagnostic).initCapacity(alloc, 4),
            .panic_mode = false,
            .str_table = str_table,
            .scope = undefined,
            ._scanner = undefined,
        };
        return p;
    }

    pub fn deinit(self: *Parser) void {
        self.scope.destroy(self.alloc);
        self.diagnostics.deinit(self.alloc);
    }

    pub fn compile(self: *Parser, scanner: Scanner) !?*ObjFunction {
        self.scope = try Scope.create(
            self.alloc,
            null,
            .Script,
            try self.constructFunction(ENTRY_POINT),
        );
        self._scanner = scanner;

        try self.advance();

        while (!try self.match(.EOF)) {
            try self.getDecl();
        }

        const res = try self.endCompiler();

        return if (self.diagnostics.items.len == 0) res else null;
    }

    fn getDecl(self: *Parser) !void {
        if (try self.match(.VAR)) {
            try self.getVarDecl();
        } else if (try self.match(.FUN)) {
            try self.getFunDecl();
        } else {
            try self.getStmt();
        }

        if (self.panic_mode) {
            try self.synchronize();
        }
    }

    fn getStmt(self: *Parser) anyerror!void {
        if (try self.match(.PRINT)) {
            try self.getPrintStmt();
        } else if (try self.match(.IF)) {
            try self.getIfStmt();
        } else if (try self.match(.WHILE)) {
            try self.getWhileStmt();
        } else if (try self.match(.FOR)) {
            try self.getForStmt();
        } else if (try self.match(.LEFT_BRACE)) {
            self.beginScope();
            try self.getBlock();
            try self.endScope();
        } else {
            try self.getExprStmt();
        }
    }

    fn getWhileStmt(self: *Parser) !void {
        const loop_start = self.getCurrentChunk().code.items.len;
        try self.consume(.LEFT_PAREN);
        try self.getExpr();
        try self.consume(.RIGHT_PAREN);

        const exit_jump = try self.emitJump(.OP_JUMP_IF_FALSE);
        try self.emitOp(.OP_POP);
        try self.getStmt();
        try self.emitLoop(loop_start);

        try self.patchJump(exit_jump);
        try self.emitOp(.OP_POP);
    }

    fn getForStmt(self: *Parser) !void {
        self.beginScope();

        // initializer
        try self.consume(.LEFT_PAREN);
        if (try self.match(.SEMICOLON)) {
            // no initializer
        } else if (try self.match(.VAR)) {
            try self.getVarDecl();
        } else {
            try self.getExprStmt();
        }

        var loop_start = self.getCurrentChunk().code.items.len;

        // condition
        var maybe_exit_jump: ?usize = null;
        if (!try self.match(.SEMICOLON)) {
            try self.getExpr();
            try self.consume(.SEMICOLON);

            maybe_exit_jump = try self.emitJump(.OP_JUMP_IF_FALSE);
            try self.emitOp(.OP_POP);
        }

        // increment
        if (!try self.match(.RIGHT_PAREN)) {
            const body_jump = try self.emitJump(.OP_JUMP);
            const increment_start = self.getCurrentChunk().code.items.len;
            try self.getExpr();
            try self.emitOp(.OP_POP);

            try self.consume(.RIGHT_PAREN);

            try self.emitLoop(loop_start);
            loop_start = increment_start;
            try self.patchJump(body_jump);
        }

        try self.getStmt();
        try self.emitLoop(loop_start);
        if (maybe_exit_jump) |exit_jump| {
            try self.patchJump(exit_jump);
            try self.emitOp(.OP_POP);
        }

        try self.endScope();
    }

    fn getPrintStmt(self: *Parser) !void {
        try self.getExpr();
        try self.consume(.SEMICOLON);
        try self.emitOp(.OP_PRINT);
    }

    fn getBlock(self: *Parser) anyerror!void {
        while (self.current.token_type != .RIGHT_BRACE and
            self.current.token_type != .EOF)
        {
            try self.getDecl();
        }

        try self.consume(.RIGHT_BRACE);
    }

    fn getFunDecl(self: *Parser) !void {
        const global = try self.parseVariable();
        self.markInitialized();

        const func = try self.getFunction(.Function);

        try self.emitConstant(Value{ .Obj = &func.obj });

        try self.defineVariable(global);
    }

    fn getFunction(self: *Parser, fun_type: ObjFunction.Type) !*ObjFunction {
        const name = self.previous.lexeme;
        const fun = try self.constructFunction(name);
        var scope = Scope.init(self.scope, fun_type, fun);

        self.scope = &scope;
        defer self.scope = self.scope.enclosing.?;
        self.beginScope();

        try self.consume(.LEFT_PAREN);
        if (self.current.token_type != .RIGHT_PAREN) {
            while (true) {
                self.currentFunction().arity += 1;
                if (self.currentFunction().arity >= std.math.maxInt(u8)) {
                    try self.reportErrorAtCurrent(.TooManyParameters);
                }

                const constant = try self.parseVariable();
                try self.defineVariable(constant);

                if (self.current.token_type != .COMMA) {
                    break;
                }
                try self.advance();
            }
        }
        try self.consume(.RIGHT_PAREN);
        try self.consume(.LEFT_BRACE);

        try self.getBlock();
        return try self.endCompiler();
    }

    fn getVarDecl(self: *Parser) !void {
        const global = try self.parseVariable();

        if (try self.match(.EQUAL)) {
            try self.getExpr();
        } else {
            try self.emitConstant(.Nil);
        }

        try self.consume(.SEMICOLON);

        try self.defineVariable(global);
    }

    fn getExprStmt(self: *Parser) !void {
        try self.getExpr();
        try self.consume(.SEMICOLON);
        try self.emitOp(.OP_POP);
    }

    fn getIfStmt(self: *Parser) !void {
        try self.consume(.LEFT_PAREN);
        try self.getExpr();
        try self.consume(.RIGHT_PAREN);

        const then_jump = try self.emitJump(.OP_JUMP_IF_FALSE);
        try self.emitOp(.OP_POP);

        try self.getStmt();
        const else_jump = try self.emitJump(.OP_JUMP);

        try self.patchJump(then_jump);
        try self.emitOp(.OP_POP);

        if (try self.match(.ELSE)) {
            try self.getStmt();
        }

        try self.patchJump(else_jump);
    }

    fn getExpr(self: *Parser) !void {
        try self.parsePrecendence(.Asgn);
    }

    fn getNum(self: *Parser, _: bool) !void {
        const val = std.fmt.parseFloat(f64, self.previous.lexeme) catch {
            return try self.reportError(.NotANumber);
        };
        try self.emitConstant(Value{ .Number = val });
    }

    fn getGrp(self: *Parser, _: bool) !void {
        try self.getExpr();
        try self.consume(.RIGHT_PAREN);
    }

    fn getBin(self: *Parser, _: bool) !void {
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

    fn getCall(self: *Parser, _: bool) !void {
        const arg_count = try self.getArgList();
        try self.emitOp(.OP_CALL);
        try self.emitByte(arg_count);
    }

    fn getArgList(self: *Parser) !u8 {
        var arg_count: u8 = 0;
        if (self.current.token_type != .RIGHT_PAREN) {
            while (true) {
                try self.getExpr();
                arg_count += 1;

                if (arg_count >= 255) {
                    try self.reportErrorAtCurrent(.TooManyParameters);
                }

                if (!try self.match(.COMMA)) {
                    break;
                }
            }
        }

        try self.consume(.RIGHT_PAREN);
        return arg_count;
    }

    fn getLit(self: *Parser, _: bool) !void {
        switch (self.previous.token_type) {
            .TRUE => try self.emitOp(.OP_TRUE),
            .FALSE => try self.emitOp(.OP_FALSE),
            .NIL => try self.emitOp(.OP_NIL),
            else => unreachable,
        }
    }

    fn getUnar(self: *Parser, _: bool) !void {
        const op = self.previous.token_type;

        try self.parsePrecendence(.Unar);

        switch (op) {
            .MINUS => try self.emitOp(.OP_NEGATE),
            .BANG => try self.emitOp(.OP_NOT),
            else => unreachable,
        }
    }

    fn getStr(self: *Parser, _: bool) !void {
        const chars = self.previous.lexeme[1 .. self.previous.lexeme.len - 1];
        const exists = self.str_table.get(chars);

        const str = if (exists) |s|
            s
        else blk: {
            const str_init_res = (try ObjString.init(self.alloc, chars, self.str_table));
            const str = str_init_res.str;
            if (str_init_res.status == .New) {
                self.obj_list.insert(&str.obj);
            }

            break :blk str;
        };

        const val = Value{ .Obj = &str.obj };
        try self.emitConstant(val);
    }

    fn getVar(self: *Parser, can_assign: bool) !void {
        try self.getNamedVariable(self.previous, can_assign);
    }

    fn parsePrecendence(self: *Parser, prec: Precedence) !void {
        try self.advance();
        const can_assign = prec.cmp(.Asgn) <= 0;
        const prefix_rule = ParseRule.getRule(self.previous.token_type).prefix;

        if (prefix_rule) |valid_prefix_rule| {
            try valid_prefix_rule(self, can_assign);
        } else {
            return try self.reportError(.ExpectedExpression);
        }

        while (prec.cmp(ParseRule.getRule(self.current.token_type).prec) <= 0) {
            try self.advance();
            const infix_rule = ParseRule.getRule(self.previous.token_type).infix;
            if (infix_rule) |valid_infix_rule| {
                try valid_infix_rule(self, can_assign);
            } else {
                return try self.reportError(.ExpectedExpression);
            }
        }
        if (can_assign and try self.match(.EQUAL)) {
            try self.reportErrorAtCurrent(.InvalidAsignmentTarget);
        }
    }

    fn makeIdentifier(self: *Parser, name: Token) !u8 {
        const ident_init_res = try ObjString.init(
            self.alloc,
            name.lexeme,
            self.str_table,
        );

        const str = ident_init_res.str;
        if (ident_init_res.status == .New) {
            self.obj_list.insert(&str.obj);
        }
        return try self.makeConstant(.{ .Obj = &str.obj });
    }

    fn addLocal(self: *Parser, name: Token) !void {
        if (self.scope.local_count == MAX_LOCAL_COUNT) {
            try self.reportErrorAtCurrent(.TooManyLocals);
            return;
        }

        self.scope.getLastLocal().* = .{
            .name = name,
            .depth = null,
        };
        self.scope.local_count += 1;
    }

    fn parseVariable(self: *Parser) !u8 {
        try self.consume(.IDENTIFIER);

        try self.declareVariable();
        if (self.scope.depth > 0) {
            return 0;
        }

        return try self.makeIdentifier(self.previous);
    }

    fn declareVariable(self: *Parser) !void {
        if (self.scope.depth == 0) {
            return;
        }

        const name = self.previous;
        for (self.scope.locals[0..self.scope.local_count]) |*local| {
            if (self.scope.depth != -1 and local.depth.? < self.scope.depth) {
                break;
            }

            if (identifiersEqual(name, local.name)) {
                try self.reportErrorAtCurrent(.DuplicateLocalDeclaration);
            }
        }

        try self.addLocal(name);
    }

    fn defineVariable(self: *Parser, global: u8) !void {
        if (self.scope.depth > 0) {
            self.markInitialized();
            return;
        }

        try self.emitOp(.OP_DEFINE_GLOBAL);
        try self.emitByte(global);
    }

    fn getAnd(self: *Parser, _: bool) !void {
        const end_jump = try self.emitJump(.OP_JUMP_IF_FALSE);

        try self.emitOp(.OP_POP);
        try self.parsePrecendence(.And);

        try self.patchJump(end_jump);
    }

    fn getOr(self: *Parser, _: bool) !void {
        const else_jump = try self.emitJump(.OP_JUMP_IF_FALSE);
        const end_jump = try self.emitJump(.OP_JUMP);

        try self.patchJump(else_jump);
        try self.emitOp(.OP_POP);

        try self.parsePrecendence(.Or);
        try self.patchJump(end_jump);
    }

    fn getNamedVariable(self: *Parser, name: Token, can_assign: bool) !void {
        const local = try self.resolveLocal(name);

        const get_op, const set_op, const addr =
            if (local) |local_idx| .{
                OpCode.OP_GET_LOCAL,
                OpCode.OP_SET_LOCAL,
                local_idx,
            } else .{
                OpCode.OP_GET_GLOBAL,
                OpCode.OP_SET_GLOBAL,
                try self.makeIdentifier(name),
            };

        if (can_assign and try self.match(.EQUAL)) {
            try self.getExpr();
            try self.emitOp(set_op);
            try self.emitByte(addr);
        } else {
            try self.emitOp(get_op);
            try self.emitByte(addr);
        }
    }

    fn emitOp(self: *Parser, op: OpCode) !void {
        try self.getCurrentChunk().writeOp(op, self.previous);
    }

    fn emitByte(self: *Parser, byte: u8) !void {
        try self.getCurrentChunk().write(u8, byte, self.previous);
    }

    fn emitLoop(self: *Parser, loop_start: usize) !void {
        try self.emitOp(.OP_LOOP);

        const offset = self.getCurrentChunk().code.items.len - loop_start + 2;
        if (offset > std.math.maxInt(u16)) {
            try self.reportErrorAtCurrent(.JumpTooBig);
        }
        const offset_downcast: u16 = @intCast(offset);

        try self.emitByte(@intCast((offset_downcast >> 8) & 0xff));
        try self.emitByte(@intCast(offset_downcast & 0xff));
    }

    fn emitConstant(self: *Parser, value: Value) !void {
        try self.emitOp(OpCode.OP_CONSTANT);
        try self.emitByte(try makeConstant(self, value));
    }

    fn emitJump(self: *Parser, instr: OpCode) !usize {
        try self.emitOp(instr);
        try self.emitByte(0xff);
        try self.emitByte(0xff);
        return self.getCurrentChunk().code.items.len - 2;
    }

    fn patchJump(self: *Parser, offset: usize) !void {
        const jump = self.getCurrentChunk().code.items.len - offset - 2;

        if (jump > std.math.maxInt(u16)) {
            try self.reportErrorAtCurrent(.JumpTooBig);
        }

        const jump_downcast: u16 = @intCast(jump);

        self.getCurrentChunk().code.items[offset] = @intCast((jump_downcast >> 8) & 0xff);
        self.getCurrentChunk().code.items[offset + 1] = @intCast(jump_downcast & 0xff);
    }

    fn makeConstant(self: *Parser, value: Value) !u8 {
        const addr = try self.getCurrentChunk().addConstant(value);

        if (addr > std.math.maxInt(u8)) {
            try self.reportError(.TooManyConstants);
        }

        return @intCast(addr);
    }

    fn resolveLocal(self: *Parser, name: Token) !?u8 {
        var idx = std.math.sub(u8, self.scope.local_count, 1) catch
            {
                return null;
            };
        while (idx >= 0) : (idx -= 1) {
            if (identifiersEqual(name, self.scope.locals[idx].name)) {
                if (self.scope.locals[idx].depth == null) {
                    try self.reportErrorAtCurrent(.ReadingInInitializer);
                }
                return idx;
            }
        }
        return null;
    }

    fn markInitialized(self: *Parser) void {
        if (self.scope.depth == 0) {
            return;
        }
        self.scope.locals[self.scope.local_count - 1].depth = self.scope.depth;
    }

    fn endCompiler(self: *Parser) !*ObjFunction {
        try self.emitOp(OpCode.OP_RETURN);
        return self.currentFunction();
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

    fn match(self: *Parser, token_type: Token.Type) !bool {
        if (self.current.token_type != token_type) {
            return false;
        }

        try self.advance();
        return true;
    }

    fn identifiersEqual(a: Token, b: Token) bool {
        return std.mem.eql(u8, a.lexeme, b.lexeme);
    }

    fn beginScope(self: *Parser) void {
        self.scope.depth += 1;
    }

    fn endScope(self: *Parser) !void {
        self.scope.depth -= 1;

        while (self.scope.local_count > 0 and
            self.scope.locals[self.scope.local_count - 1].depth.? > self.scope.depth)
        {
            try self.emitOp(.OP_POP);
            self.scope.local_count -= 1;
        }
    }

    fn getCurrentChunk(self: *Parser) *Chunk {
        return self.currentFunction().chunk;
    }

    fn reportErrorAtCurrent(self: *Parser, err: Error) !void {
        try self.reportErrorAt(self.current, err);
    }

    fn reportError(self: *Parser, err: Error) !void {
        try self.reportErrorAt(self.previous, err);
    }

    fn reportErrorAt(self: *Parser, token: Token, err: Error) !void {
        self.panic_mode = true;
        try self.diagnostics.append(self.alloc, Diagnostic{ .error_type = err, .token = token });
    }

    fn synchronize(self: *Parser) !void {
        self.panic_mode = false;

        while (self.current.token_type != .EOF) {
            if (self.previous.token_type == .SEMICOLON) {
                return;
            }
            switch (self.current.token_type) {
                .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN => {
                    return;
                },
                else => {},
            }

            try self.advance();
        }
    }

    fn constructFunction(self: Parser, name: []const u8) !*ObjFunction {
        const func_res = try ObjString.init(self.alloc, name, self.str_table);
        if (func_res.status == .New) {
            self.obj_list.insert(&func_res.str.obj);
        }

        const func = try ObjFunction.init(self.alloc, func_res.str);
        self.obj_list.insert(&func.obj);
        return func;
    }

    fn currentFunction(self: *Parser) *ObjFunction {
        return self.scope.function;
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

const ParseFn = *const fn (*Parser, bool) anyerror!void;
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
                .LEFT_PAREN    => rule(p.getGrp,  p.getCall, .Call),
                .RIGHT_PAREN   => rule(null,      null,      .None),
                .LEFT_BRACE    => rule(null,      null,      .None),
                .RIGHT_BRACE   => rule(null,      null,      .None),
                .COMMA         => rule(null,      null,      .None),
                .DOT           => rule(null,      null,      .None),
                .MINUS         => rule(p.getUnar, p.getBin,  .Term),
                .PLUS          => rule(null,      p.getBin,  .Term),
                .SEMICOLON     => rule(null,      null,      .None),
                .SLASH         => rule(null,      p.getBin,  .Fact),
                .STAR          => rule(null,      p.getBin,  .Fact),
                .BANG          => rule(p.getUnar, null,      .None),
                .BANG_EQUAL    => rule(null,      p.getBin,  .Eql ),
                .EQUAL         => rule(null,      null,      .None),
                .EQUAL_EQUAL   => rule(null,      p.getBin,  .Eql ),
                .GREATER       => rule(null,      p.getBin,  .Cmp ),
                .GREATER_EQUAL => rule(null,      p.getBin,  .Cmp ),
                .LESS          => rule(null,      p.getBin,  .Cmp ),
                .LESS_EQUAL    => rule(null,      p.getBin,  .Cmp ),
                .IDENTIFIER    => rule(p.getVar,  null,      .None),
                .STRING        => rule(p.getStr,  null,      .None),
                .NUMBER        => rule(p.getNum,  null,      .None),
                .AND           => rule(null,      p.getAnd,  .And),
                .CLASS         => rule(null,      null,      .None),
                .ELSE          => rule(null,      null,      .None),
                .FALSE         => rule(p.getLit,  null,      .None),
                .FUN           => rule(null,      null,      .None),
                .FOR           => rule(null,      null,      .None),
                .IF            => rule(null,      null,      .None),
                .NIL           => rule(p.getLit,  null,      .None),
                .OR            => rule(null,      p.getOr,   .None),
                .PRINT         => rule(null,      null,      .None),
                .RETURN        => rule(null,      null,      .None),
                .SUPER         => rule(null,      null,      .None),
                .THIS          => rule(null,      null,      .None),
                .TRUE          => rule(p.getLit,  null,      .None),
                .VAR           => rule(null,      null,      .None),
                .WHILE         => rule(null,      null,      .None),
                .EOF           => rule(null,      null,      .None),
                .ERROR         => rule(null,      null,      .None),
            };
        }

        break :blk table;
    };

    fn getRule(token_type: Token.Type) ParseRule {
        return rules[@intFromEnum(token_type)];
    }
};
