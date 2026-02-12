const std = @import("std");
const value = @import("value.zig");

pub const RenderOffsetPair = struct { render: []const u8, offset: usize };

pub const BYTE = u8;

pub const OpCode = enum(BYTE) {
    OP_RETURN,
    OP_CONSTANT,

    pub fn render(self: OpCode) RenderOffsetPair {
        switch (self) {
            .OP_RETURN => {
                return RenderOffsetPair{ .render = @tagName(self), .offset = 1 };
            },
            .OP_CONSTANT => {
                return RenderOffsetPair{ .render = @tagName(self), .offset = 1 };
            }
        }
    }
};
