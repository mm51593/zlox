const std = @import("std");
const mem = @import("memory.zig");
const op_code = @import("op_code.zig");
const value = @import("value.zig");

var gpa = std.heap.DebugAllocator(.{}){};
const allocator = gpa.allocator();

const INITIAL_CAPACITY = 8;

pub const Chunk = struct {
    count: usize,
    code: []op_code.OpCode,
    constants: value.ValueArray,

    pub fn init() !Chunk {
        const block = try allocator.alloc(op_code.OpCode, INITIAL_CAPACITY);
        const constants = try value.ValueArray.init();
        return Chunk{ .count = 0, .code = block, .constants = constants };
    }

    pub fn write(self: *Chunk, byte: op_code.OpCode) !void {
        self.code = try mem.ensureCapacity(op_code.OpCode, self.code, self.count, allocator);

        self.code[self.count] = byte;
        self.count += 1;
    }

    pub fn addConstant(self: *Chunk, val: value.Value) !usize {
        try self.constants.write(val);
        return self.constants.count - 1;
    }

    pub fn free(self: *Chunk) void {
        self.count = 0;
        self.constants.free();
        allocator.free(self.code);
    }
};
