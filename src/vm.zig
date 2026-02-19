const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const value = @import("value.zig");
const BYTE = @import("op_code.zig").BYTE;
const OpCode = @import("op_code.zig").OpCode;
const Scanner = @import("scanner.zig").Scanner;
const Parser = @import("parser.zig").Parser;

const STACK_MAX = 256;

pub const Vm = struct {
    chunk: Chunk,
    ip: [*]u8,
    stack: [STACK_MAX]value.Value,
    sp: [*]value.Value,

    pub fn init() Vm {
        var vm = Vm{ .chunk = undefined, .ip = undefined, .stack = undefined, .sp = undefined };
        vm.sp = &vm.stack;
        return vm;
    }

    pub fn free(_: Vm) void {}

    pub fn interpret(vm: *Vm, source: []u8) InterpretResult {
        var parser = Parser.init(source);
        vm.chunk = Chunk.init() catch {return .INTERPRET_COMPILE_ERROR;};
        parser.compile(&vm.chunk) catch {return .INTERPRET_COMPILE_ERROR;};
        vm.ip = vm.chunk.code.items.ptr;

        return vm.run();

        // var line: ?usize = null;
        // while (true) {
        //     const token = scanner.scanToken();
        //     if (token.line != line) {
        //         std.debug.print("{d:0>4} ", .{line orelse 0});
        //         line = token.line;
        //     } else {
        //         std.debug.print("   | ", .{});
        //     }
        //     std.debug.print("{s} {s}\n", .{ @tagName(token.token_type), token.lexeme });
        //
        //     if (token.token_type == .EOF) {
        //         break;
        //     }
        // }
    }

    fn run(self: *Vm) InterpretResult {
        while (true) {
            const b = self.readByte();
            const instr: OpCode = @enumFromInt(b);
            switch (instr) {
                .OP_RETURN => {
                    const val = self.pop();
                    std.debug.print("Return: {}\n", .{val});
                    return InterpretResult.INTERPRET_OK;
                },
                .OP_NEGATE => {
                    const val = self.pop();
                    self.push(-val);
                },
                .OP_ADD, OpCode.OP_SUBTRACT, OpCode.OP_MULTIPLY, OpCode.OP_DIVIDE => {
                    self.interpretBinary(instr);
                },
                .OP_CONSTANT => {
                    const val = readConstant(self);
                    self.push(val);
                },
            }
        }
    }

    fn readByte(self: *Vm) BYTE {
        const byte: u8 = self.ip[0];
        self.ip += 1;
        return byte;
    }

    fn readConstant(self: *Vm) value.Value {
        return self.chunk.constants.values.items[self.readByte()];
    }

    fn push(self: *Vm, val: value.Value) void {
        self.sp[0] = val;
        self.sp += 1;
    }

    fn pop(self: *Vm) value.Value {
        self.sp -= 1;
        return self.sp[0];
    }

    fn printStack(self: Vm) void {
        for (&self.stack..self.sp) |slot| {
            std.debug.print("[{}]", .{slot.*});
        }
    }

    fn interpretBinary(self: *Vm, op: OpCode) void {
        const b = self.pop();
        const a = self.pop();
        const res = switch (op) {
            .OP_ADD => a + b,
            .OP_SUBTRACT => a - b,
            .OP_MULTIPLY => a * b,
            .OP_DIVIDE => a / b,
            else => unreachable,
        };
        self.push(res);
    }
};

pub const InterpretResult = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};
