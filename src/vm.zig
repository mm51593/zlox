const std = @import("std");
const Allocator = @import("std").mem.Allocator;

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
const ObjectList = @import("object.zig").ObjectList;
const StringTable = @import("string_table.zig").StringTable;
const Table = @import("table.zig").Table;

pub const RuntimeError = error{
    InvalidOperand,
    BufferTooSmall,
    UndefinedVariable,
};

const STACK_MAX = 256;

pub const Vm = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: [STACK_MAX]Value,
    sp: usize,
    alloc: Allocator,
    objects: *ObjectList,
    str_table: *StringTable,
    globals: Table,

    pub fn init(alloc: Allocator, obj_list: *ObjectList, str_table: *StringTable) Vm {
        var vm = Vm{
            .chunk = undefined,
            .ip = undefined,
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

    pub fn interpret(vm: *Vm, chunk: Chunk) !void {
        vm.chunk = chunk;
        vm.ip = vm.chunk.code.items.ptr;

        try vm.run();
    }

    fn run(self: *Vm) !void {
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
                .OP_DEFINE_GLOBAL => {
                    const name_obj: *Obj = try self.readConstant().as(.Obj);
                    const name_str = try name_obj.as(ObjString);
                    _ = try self.globals.put(name_str, self.pop());
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
                        self.objects.insert(&concat.obj);
                        self.push(try pack(&concat.obj));
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
        const byte: u8 = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *Vm) Value {
        return self.chunk.constants.values.items[self.readByte()];
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

    fn printStack(self: Vm) void {
        for (0..self.sp) |idx| {
            std.debug.print("[{}]", .{self.stack[idx]});
        }
    }

    fn interpretNumBinary(op1: Value, op2: Value, op: OpCode) RuntimeError!Value {
        const b = try unpack(op1.as(.Number));
        const a = try unpack(op2.as(.Number));
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

        try unpack(val.as(.Nil));
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

pub const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};
