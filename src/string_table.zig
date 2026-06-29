const ObjString = @import("object.zig").ObjString;

const StringHashMap = @import("std").StringHashMap;
const Allocator = @import("std").mem.Allocator;
const std = @import("std");

pub const StringTable = struct {
    entires: StringHashMap(*ObjString),

    pub fn init(alloc: Allocator) StringTable {
        return StringTable{ .entires = .init(alloc) };
    }

    pub fn deinit(self: *StringTable) void {
        self.entires.deinit();
    }

    pub fn put(self: *StringTable, key: []const u8, val: *ObjString) !void {
        const res = self.entires.get(key);
        if (res) |_| {
            return;
        }

        try self.entires.put(key, val);
    }

    pub fn get(self: StringTable, key: []const u8) ?*ObjString {
        return self.entires.get(key);
    }
};
