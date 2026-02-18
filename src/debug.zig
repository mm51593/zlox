const std = @import("std");
const cnk = @import("chunk.zig");
const OpCode = @import("op_code.zig").OpCode;

pub fn disasChunk(chunk: cnk.Chunk, name: []const u8) !void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;

    while (offset < chunk.code.items.len) {
        offset += try disasInst(chunk, offset);
    }
}

pub fn disasInst(chunk: cnk.Chunk, idx: usize) !usize {
    var offset: usize = 0;
    const inst = chunk.code.items[idx];
    const line = chunk.lines.items[idx];

    std.debug.print("{:0>4} ", .{idx});

    if (idx != 0 and line == chunk.lines.items[idx - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{: >4} ", .{line});
    }

    const op_code: OpCode = @enumFromInt(inst);
    offset += 1;

    var buf: [32]u8 = undefined;
    const r_o_pair = try op_code.render(&buf, chunk.code.items[idx + 1 ..]);
    offset += r_o_pair.offset;

    std.debug.print("{s}\n", .{r_o_pair.render});

    return offset;
}
