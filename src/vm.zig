const std = @import("std");
const Allocator = @import("std").mem.Allocator;

const Token = @import("token.zig").Token;
const BYTE = @import("op_code.zig").BYTE;
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("op_code.zig").OpCode;
const ParseError = @import("parser.zig").ParseError;
const Parser = @import("parser.zig").Parser;
const Scanner = @import("scanner.zig").Scanner;
const Value = @import("value.zig").Value;
const ValueTag = @import("value.zig").ValueTag;
const Obj = @import("object.zig").Obj;
const ObjString = @import("object.zig").ObjString;
const ObjFunction = @import("object.zig").ObjFunction;
const ObjectList = @import("object.zig").ObjectList;
const StringTable = @import("string_table.zig").StringTable;
const Table = @import("table.zig").Table;

pub const RuntimeError = error{
    InvalidOperand,
    BufferTooSmall,
    UndefinedVariable,
    NotCallable,
};

const FRAMES_MAX = 64;
const STACK_MAX = FRAMES_MAX * std.math.maxInt(u8);

pub const Vm = struct {
    frames: [FRAMES_MAX]CallFrame,
    fp: usize,
    stack: [STACK_MAX]Value,
    sp: usize,
    alloc: Allocator,
    objects: *ObjectList,
    str_table: *StringTable,
    globals: Table,

    pub fn init(alloc: Allocator, obj_list: *ObjectList, str_table: *StringTable) Vm {
        var vm = Vm{
            .frames = undefined,
            .fp = 0,
            .stack = undefined,
            .sp = 0,
            .alloc = alloc,
            .objects = obj_list,
            .str_table = str_table,
            .globals = undefined,
        };
        vm.globals.init(alloc);
        return vm;
    }

    pub fn deinit(self: *Vm) void {
        self.globals.deinit();
    }

    pub fn interpret(self: *Vm, func: *ObjFunction) !void {
        self.push(Value{ .Obj = &func.obj });
        self.call(func, 0);

        try self.run();
    }

    pub fn getCurrentFrame(self: *Vm) *CallFrame {
        return &self.frames[self.fp - 1];
    }

    fn run(self: *Vm) !void {
        var frame = self.getCurrentFrame();

        while (true) {
            const word = self.readByte();
            const instr: OpCode = @enumFromInt(word);
            switch (instr) {
                .OP_RETURN => {
                    return;
                },
                .OP_PRINT => {
                    const val = self.pop();
                    try printValue(val);
                },
                .OP_POP => {
                    _ = self.pop();
                },
                .OP_GET_GLOBAL => {
                    const name_obj: *Obj = try self.readConstant().as(.Obj);
                    const name_str = try name_obj.as(ObjString);

                    const opt_val = self.globals.get(name_str);
                    if (opt_val) |val| {
                        self.push(val);
                    } else {
                        return RuntimeError.UndefinedVariable;
                    }
                },
                .OP_SET_GLOBAL => {
                    const name_obj: *Obj = try self.readConstant().as(.Obj);
                    const name_str = try name_obj.as(ObjString);

                    const exists = try self.globals.put(name_str, self.peek(0));
                    if (!exists) {
                        _ = self.globals.delete(name_str);
                        return RuntimeError.UndefinedVariable;
                    }
                },
                .OP_GET_LOCAL => {
                    const slot = self.readByte();
                    self.push(frame.slots[slot]);
                },
                .OP_SET_LOCAL => {
                    const slot = self.readByte();
                    frame.slots[slot] = self.peek(0);
                },
                .OP_DEFINE_GLOBAL => {
                    const name_obj: *Obj = try self.readConstant().as(.Obj);
                    const name_str = try name_obj.as(ObjString);
                    _ = try self.globals.put(name_str, self.pop()); // this pop might be dangerous
                },
                .OP_JUMP => {
                    const offset = self.readShort();
                    frame.ip += offset;
                },
                .OP_JUMP_IF_FALSE => {
                    const offset = self.readShort();
                    if (try isFalsey(self.peek(0))) {
                        frame.ip += offset;
                    }
                },
                .OP_LOOP => {
                    const offset = self.readShort();
                    frame.ip -= offset;
                },
                .OP_CALL => {
                    const arg_count = self.readByte();
                    try self.callValue(self.peek(arg_count), arg_count);
                    frame = &self.frames[self.fp - 1];
                },
                .OP_NEGATE => {
                    const val = try unpack(self.pop().as(.Number));
                    const negated = -val;
                    self.push(try pack(negated));
                },
                .OP_NOT => {
                    const val = self.pop();
                    const negated = try isFalsey(val);
                    self.push(try pack(negated));
                },
                .OP_ADD => {
                    const b = self.pop();
                    const a = self.pop();

                    if (a.is(.Number) and b.is(.Number)) {
                        self.push(try interpretNumBinary(a, b, instr));
                    } else if (a.is(.Obj) and (try a.as(.Obj)).is(.OBJ_STRING) and
                        b.is(.Obj) and (try b.as(.Obj)).is(.OBJ_STRING))
                    {
                        const a_str = try (try a.as(.Obj)).as(ObjString);
                        const b_str = try (try b.as(.Obj)).as(ObjString);
                        const concat = try ObjString.concatenate(self.alloc, a_str, b_str, self.str_table);
                        if (concat.status == .New) {
                            self.objects.insert(&concat.str.obj);
                        }
                        self.push(try pack(&concat.str.obj));
                    } else {
                        return RuntimeError.InvalidOperand;
                    }
                },
                .OP_SUBTRACT, .OP_MULTIPLY, .OP_DIVIDE, .OP_GREATER, .OP_LESS => {
                    const b = self.pop();
                    const a = self.pop();

                    self.push(try interpretNumBinary(a, b, instr));
                },
                .OP_CONSTANT => {
                    const val = readConstant(self);
                    self.push(val);
                },
                .OP_NIL => {
                    self.push(Value.Nil);
                },
                .OP_TRUE => {
                    self.push(.{ .Bool = true });
                },
                .OP_FALSE => {
                    self.push(.{ .Bool = false });
                },
                .OP_EQUAL => {
                    const a = self.pop();
                    const b = self.pop();
                    self.push(try pack(try valuesEqual(a, b)));
                },
            }
        }
    }

    fn readByte(self: *Vm) BYTE {
        const frame = self.getCurrentFrame();
        const byte = frame.getByteCode()[frame.ip];
        frame.ip += 1;
        return byte;
    }

    fn readShort(self: *Vm) u16 {
        const frame = self.getCurrentFrame();
        const bytecode = frame.getByteCode();
        const r: u16 = (@as(u16, bytecode[frame.ip]) << 8) | bytecode[frame.ip + 1];
        frame.ip += 2;
        return r;
    }

    fn readConstant(self: *Vm) Value {
        return self.getCurrentFrame().getConstants()[self.readByte()];
    }

    fn push(self: *Vm, val: Value) void {
        self.stack[self.sp] = val;
        self.sp += 1;
    }

    fn pop(self: *Vm) Value {
        self.sp -= 1;
        const val = self.stack[self.sp];
        return val;
    }

    fn peek(self: Vm, count: usize) Value {
        return self.stack[self.sp - 1 - count];
    }

    fn callValue(self: *Vm, callee: Value, arg_count: u8) !void {
        const obj: *Obj = callee.as(.Obj) catch {
            return RuntimeError.NotCallable;
        };
        const func = obj.as(ObjFunction) catch {
            return RuntimeError.NotCallable;
        };

        self.call(func, arg_count);
    }

    fn call(self: *Vm, func: *ObjFunction, arg_count: u8) void {
        var frame = &self.frames[self.fp];
        self.fp += 1;

        frame.function = func;
        frame.ip = 0;
        frame.slots = @ptrCast(&self.stack[self.sp - arg_count]);
    }

    fn printStack(self: Vm) !void {
        for (0..self.sp) |idx| {
            try printValue(self.stack[idx]);
        }
    }

    fn interpretNumBinary(op1: Value, op2: Value, op: OpCode) RuntimeError!Value {
        const a = try unpack(op1.as(.Number));
        const b = try unpack(op2.as(.Number));
        return switch (op) {
            .OP_ADD => try pack(a + b),
            .OP_SUBTRACT => try pack(a - b),
            .OP_MULTIPLY => try pack(a * b),
            .OP_DIVIDE => try pack(a / b),
            .OP_GREATER => try pack(a > b),
            .OP_LESS => try pack(a < b),
            else => unreachable,
        };
    }

    fn unpack(val: anytype) RuntimeError!payload(@TypeOf(val)) {
        return val catch RuntimeError.InvalidOperand;
    }

    fn pack(raw_value: anytype) RuntimeError!Value {
        const T = @TypeOf(raw_value);
        return switch (T) {
            f64 => Value{ .Number = raw_value },
            bool => Value{ .Bool = raw_value },
            void => Value{.Nil},
            *Obj => Value{ .Obj = raw_value },
            else => RuntimeError.InvalidOperand,
        };
    }

    fn payload(comptime T: type) type {
        return switch (@typeInfo(T)) {
            .error_union => |eu| eu.payload,
            else => @compileError("Expecting an error union"),
        };
    }

    fn isFalsey(val: Value) RuntimeError!bool {
        const maybe_bool_val = unpack(val.as(.Bool)) catch null;
        if (maybe_bool_val) |bool_val| {
            return !bool_val;
        }

        unpack(val.as(.Nil)) catch {
            return false;
        };

        return true;
    }

    fn valuesEqual(a: Value, b: Value) RuntimeError!bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) {
            return false;
        }

        return switch (a) {
            .Number => try unpack(a.as(.Number)) == try unpack(b.as(.Number)),
            .Bool => try unpack(a.as(.Bool)) == try unpack(b.as(.Bool)),
            .Nil => true,
            .Obj => try unpack(Obj.equals(try unpack(a.as(.Obj)), try unpack(b.as(.Obj)))),
        };
    }

    pub fn printValue(val: Value) !void {
        switch (val) {
            .Number => |n| std.debug.print("{}\n", .{n}),
            .Bool => |b| std.debug.print("{}\n", .{b}),
            .Nil => std.debug.print("nil\n", .{}),
            .Obj => |o| try o.print(),
        }
    }
};

pub const CallFrame = struct {
    function: *ObjFunction,
    ip: usize,
    slots: [*]Value,

    pub fn getCurrentToken(self: CallFrame) *Token {
        const tokens = self.function.chunk.tokens.items;
        const idx = self.ip;
        return &tokens[idx];
    }

    pub fn getConstants(self: CallFrame) []Value {
        return self.function.chunk.constants.values.items;
    }

    pub fn getByteCode(self: *CallFrame) []BYTE {
        return self.function.chunk.code.items;
    }
};

pub const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};
