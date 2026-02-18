const std = @import("std");
const value = @import("value.zig");

pub const RenderOffsetPair = struct { render: []const u8, offset: usize };

pub const BYTE = u8;
pub const address = u8;

comptime {
    if (@sizeOf(OpCode) != 1) {
        @compileError("OpCode must be exactly 1 byte.");
    }
}

pub const OpCode = enum(BYTE) {
    // simple
    OP_RETURN,

    // unary
    OP_NEGATE,

    // binary
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,

    // constant
    OP_CONSTANT,

    const BINARY_OPS = [_]OpCode{ .OP_ADD, .OP_SUBTRACT, .OP_MULTIPLY, .OP_DIVIDE };

    pub fn render(self: OpCode, buf: []u8, bytestream: []BYTE) !RenderOffsetPair {
        var offset: usize = 0;
        switch (self) {
            .OP_RETURN => {
                return RenderOffsetPair{ .render = @tagName(self), .offset = offset };
            },
            .OP_NEGATE => {
                return RenderOffsetPair{ .render = @tagName(self), .offset = offset };
            },
            .OP_ADD, .OP_SUBTRACT, .OP_MULTIPLY, .OP_DIVIDE => {
                return RenderOffsetPair{ .render = @tagName(self), .offset = offset };
            },
            .OP_CONSTANT => {
                const size = @sizeOf(address);
                const val = std.mem.readInt(address, bytestream[0..size], std.builtin.Endian.little);
                const rend = try std.fmt.bufPrint(buf, "{s} {}", .{ @tagName(self), val });

                offset = size;
                return RenderOffsetPair{ .render = rend, .offset = offset };
            },
        }
    }
};
