const std = @import("std");
const value = @import("value.zig");

pub const RenderOffsetPair = struct { render: []const u8, offset: usize };

pub const OpCode = union(enum) {
    OP_RETURN,
    OP_CONSTANT: usize,

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
