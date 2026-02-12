const std = @import("std");
const chunk = @import("chunk.zig");
const OpCode = @import("op_code.zig").OpCode;
const debug = @import("debug.zig");

pub fn main() !void {
    var cnk = try chunk.Chunk.init();
    try cnk.write(u8, @intFromEnum(OpCode.OP_RETURN));

    const addr = try cnk.addConstant(1.2);
    try cnk.write(u8, @intFromEnum(OpCode.OP_CONSTANT));
    try cnk.write(@TypeOf(addr), addr);

    debug.disasChunk(cnk, "test chunk");
    cnk.free();
}
