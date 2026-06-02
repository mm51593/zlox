const Allocator = @import("std").mem.Allocator;
const Order = @import("std").math.Order;
const debug = @import("std").debug;
const mem = @import("std").mem;
const StringTable = @import("string_table.zig").StringTable;

pub const ObjError = error{
    InvalidType,
};

pub const ObjType = enum {
    OBJ_STRING,
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
        }
    }

    pub fn equals(a: *Obj, b: *Obj) ObjError!bool {
        if (a.type != b.type) {
            return false;
        }

        return switch (a.type) {
            .OBJ_STRING => ObjString.cmp(try a.as(ObjString), try b.as(ObjString)) == .eq,
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
        p.* = .{
            .obj = .{ .type = .OBJ_STRING, .next = null },
            .chars = chars,
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

    pub fn concatenate(alloc: Allocator, a: *ObjString, b: *ObjString, str_table: *StringTable) !*ObjString {
        const len = a.chars.len + b.chars.len;
        const chars = try alloc.alloc(u8, len);
        @memcpy(chars, a.chars.ptr);
        @memcpy(chars[a.chars.len..], b.chars.ptr);

        const res = try ObjString.init(alloc, chars, str_table);
        if (res.status == .Existing) {
            alloc.free(chars);
        }

        return res.str;
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
            }
        }
    }

    pub fn create(self: *ObjectList, alloc: Allocator, tag: ObjType) !*Obj {
        const obj = switch (tag) {
            .OBJ_STRING => (try alloc.create(ObjString)).obj,
        };

        self.insert(obj);
        return obj;
    }

    pub fn insert(self: *ObjectList, o: *Obj) void {
        o.next = self.head;
        self.head = o;
    }
};
