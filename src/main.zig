const std = @import("std");
const chunk = @import("chunk.zig");
const op_code = @import("op_code.zig");
const debug = @import("debug.zig");

pub fn main() !void {
    var cnk = try chunk.Chunk.init();
    try cnk.write(op_code.OpCode.OP_RETURN);

    const addr = try cnk.addConstant(1.2);
    try cnk.write(op_code.OpCode{ .OP_CONSTANT = addr });

    debug.disasChunk(cnk, "test chunk");
    cnk.free();
}
