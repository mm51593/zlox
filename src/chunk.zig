const std = @import("std");
const op_code = @import("op_code.zig");
const value = @import("value.zig");
const Token = @import("token.zig").Token;

const INITIAL_CAPACITY = 8;
const BYTE = op_code.BYTE;

pub const Chunk = struct {
    alloc: std.mem.Allocator,
    code: std.ArrayList(BYTE),
    tokens: std.ArrayList(Token),
    constants: value.ValueArray,

    pub fn init(alloc: std.mem.Allocator) !*Chunk {
        const p = try alloc.create(Chunk);
        p.* = .{
            .alloc = alloc,
            .code = try std.ArrayList(BYTE).initCapacity(alloc, INITIAL_CAPACITY),
            .tokens = try std.ArrayList(Token).initCapacity(alloc, INITIAL_CAPACITY),
            .constants = try value.ValueArray.init(alloc),
        };
        return p;
    }

    pub fn writeOp(self: *Chunk, op: op_code.OpCode, token: Token) !void {
        try self.write(u8, @intFromEnum(op), token);
    }

    pub fn write(self: *Chunk, comptime T: type, data: T, token: Token) !void {
        var buf: [@sizeOf(T)]BYTE = undefined;
        std.mem.writeInt(T, &buf, data, std.builtin.Endian.little);

        try self.code.appendSlice(self.alloc, &buf);

        try self.tokens.appendNTimes(self.alloc, token, @sizeOf(T) / @sizeOf(BYTE));
    }

    pub fn addConstant(self: *Chunk, val: value.Value) !usize {
        try self.constants.write(val);
        return self.constants.values.items.len - 1;
    }

    pub fn deinit(self: *Chunk) void {
        self.constants.deinit();
        self.tokens.deinit(self.alloc);
        self.code.deinit(self.alloc);
        self.alloc.destroy(self);
    }
};
