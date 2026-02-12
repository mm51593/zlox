const std = @import("std");
const op_code = @import("op_code.zig");
const value = @import("value.zig");

var gpa = std.heap.DebugAllocator(.{}){};
const alloc = gpa.allocator();

const INITIAL_CAPACITY = 8;
const BYTE = op_code.BYTE;

pub const Chunk = struct {
    code: std.ArrayList(BYTE),
    constants: value.ValueArray,

    pub fn init() !Chunk {
        const byte_stream = try std.ArrayList(BYTE).initCapacity(alloc, INITIAL_CAPACITY);
        const constants = try value.ValueArray.init();
        return Chunk{ .code = byte_stream, .constants = constants };
    }

    pub fn write(self: *Chunk, comptime T: type, data: T) !void {
        var buf: [@sizeOf(T)]BYTE = undefined;
        std.mem.writeInt(T, &buf, data, std.builtin.Endian.little);

        try self.code.appendSlice(alloc, &buf);
    }

    pub fn addConstant(self: *Chunk, val: value.Value) !usize {
        try self.constants.write(val);
        return self.constants.values.items.len - 1;
    }

    pub fn free(self: *Chunk) void {
        self.constants.free();
        alloc.free(self.code);
    }
};
