const Allocator = @import("std").mem.Allocator;
const Order = @import("std").math.Order;
const debug = @import("std").debug;
const mem = @import("std").mem;
const StringTable = @import("string_table.zig").StringTable;
const Chunk = @import("chunk.zig").Chunk;

pub const ObjError = error{
    InvalidType,
};

pub const ObjType = enum {
    OBJ_STRING,
    OBJ_FUNCTION,
};

pub const Obj = struct {
    type: ObjType,
    next: ?*Obj,

    pub fn is(self: Obj, objType: ObjType) bool {
        return self.type == objType;
    }

    pub fn as(self: *const Obj, comptime T: type) ObjError!*T {
        if (self.type != T.tag) {
            return ObjError.InvalidType;
        }
        return @alignCast(@constCast(@fieldParentPtr("obj", self)));
    }

    pub fn print(self: *const Obj) ObjError!void {
        switch (self.type) {
            .OBJ_STRING => (try self.as(ObjString)).print(),
            .OBJ_FUNCTION => (try self.as(ObjFunction)).print(),
        }
    }

    pub fn equals(a: *Obj, b: *Obj) ObjError!bool {
        if (a.type != b.type) {
            return false;
        }

        return switch (a.type) {
            .OBJ_STRING => ObjString.cmp(try a.as(ObjString), try b.as(ObjString)) == .eq,
            .OBJ_FUNCTION => a == b,
        };
    }
};

pub const ObjString = struct {
    pub const tag = ObjType.OBJ_STRING;
    obj: Obj,
    chars: []const u8,

    pub const InitResult = struct {
        str: *ObjString,
        status: enum {
            Existing,
            New,
        },
    };

    pub fn init(alloc: Allocator, chars: []const u8, table: *StringTable) !InitResult {
        if (table.get(chars)) |str| {
            return .{ .str = str, .status = .Existing };
        }

        const p = try alloc.create(ObjString);
        const chars_copy = try alloc.dupe(u8, chars);
        p.* = .{
            .obj = .{ .type = .OBJ_STRING, .next = null },
            .chars = chars_copy,
        };
        try table.put(p.chars, p);

        return .{ .str = p, .status = .New };
    }

    pub fn deinit(self: *ObjString, alloc: Allocator) void {
        alloc.free(self.chars);
        alloc.destroy(self);
    }

    pub fn print(self: *ObjString) void {
        debug.print("{s}\n", .{self.chars});
    }

    pub fn cmp(a: *ObjString, b: *ObjString) Order {
        return if (a == b) .eq else .lt;
    }

    pub fn concatenate(alloc: Allocator, a: *ObjString, b: *ObjString, str_table: *StringTable) !InitResult {
        const len = a.chars.len + b.chars.len;
        const chars = try alloc.alloc(u8, len);
        @memcpy(chars, a.chars.ptr);
        @memcpy(chars[a.chars.len..], b.chars.ptr);

        const res = try ObjString.init(alloc, chars, str_table);
        alloc.free(chars);

        return res;
    }
};

pub const ObjFunction = struct {
    pub const tag = ObjType.OBJ_FUNCTION;
    obj: Obj,
    arity: u8,
    chunk: *Chunk,
    name: *ObjString,

    pub const Type = enum {
        Function,
        Script,
    };

    pub fn init(alloc: Allocator, name: *ObjString) !*ObjFunction {
        const p = try alloc.create(ObjFunction);
        p.* = .{
            .obj = .{ .type = .OBJ_FUNCTION, .next = null },
            .arity = 0,
            .chunk = try Chunk.init(alloc),
            .name = name,
        };
        return p;
    }

    pub fn deinit(self: *ObjFunction, alloc: Allocator) void {
        self.chunk.deinit();
        alloc.destroy(self);
    }

    pub fn print(self: *ObjFunction) void {
        debug.print("<fn {s}>\n", .{self.name.chars});
    }
};

pub const ObjectList = struct {
    head: ?*Obj,

    pub fn init() ObjectList {
        return ObjectList{ .head = null };
    }

    pub fn deinit(self: *ObjectList, alloc: Allocator) !void {
        while (self.head) |node| {
            self.head = node.next;
            switch (node.type) {
                .OBJ_STRING => {
                    const o = try node.as(ObjString);
                    o.deinit(alloc);
                },
                .OBJ_FUNCTION => {
                    const o = try node.as(ObjFunction);
                    o.deinit(alloc);
                }
            }
        }
    }

    pub fn insert(self: *ObjectList, o: *Obj) void {
        o.next = self.head;
        self.head = o;
    }
};
