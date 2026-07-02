const Token = @import("token.zig").Token;

pub const Local = struct {
    name: Token,
    depth: ?u8,
};

