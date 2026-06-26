const ObjString = @import("object.zig").ObjString;
const Value = @import("value.zig").Value;

const HashMap = @import("std").HashMap;
const Allocator = @import("std").mem.Allocator;

const TABLE_MAX_LOAD = 75;

const TableCtx = struct {
    pub fn hash(_: TableCtx, s: *ObjString) u64 {
        var res: u64 = 2166136261;
        for (s.chars) |c| {
            res ^= c;
            res *%= 16777619;
        }
        return res;
    }

    pub fn eql(_: TableCtx, s1: *ObjString, s2: *ObjString) bool {
        return ObjString.cmp(s1, s2) == .eq;
    }
};

pub const Table = struct {
    entries: HashMap(*ObjString, Value, TableCtx, TABLE_MAX_LOAD),

    pub fn init(self: *Table, alloc: Allocator) void {
        self.entries = .init(alloc);
    }

    pub fn deinit(self: *Table) void {
        self.entries.deinit();
    }

    pub fn put(self: *Table, key: *ObjString, value: Value) !void {
        try self.entries.put(key, value);
    }

    pub fn addAll(from: *Table, to: *Table) !void {
        var it = from.entries.iterator();
        while (it.next()) |entry| {
            try to.put(entry.key_ptr, entry.value_ptr);
        }
    }

    pub fn get(self: *Table, key: *ObjString) ?Value {
        return self.entries.get(key);
    }

    pub fn delete(self: *Table, key: *ObjString) bool {
        return self.entries.remove(key);
    }
};
