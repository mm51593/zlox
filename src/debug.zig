const std = @import("std");
const chunk = @import("chunk.zig");
const op_code = @import("op_code.zig");

pub fn disasChunk(cnk: chunk.Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;

    while (offset < cnk.code.items.len) {
        offset += disasInst(cnk, offset);
    }
}

pub fn disasInst(cnk: chunk.Chunk, offset: usize) usize {
    std.debug.print("{:0>4} ", .{offset}); 

    const r_o_pair = @as(u8, cnk.code.items[offset]).render();
    std.debug.print("{s}\n", .{r_o_pair.render});

    return r_o_pair.offset;
}

