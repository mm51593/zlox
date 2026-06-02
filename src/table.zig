const ObjString = @import("object.zig").ObjString;
const Value = @import("value.zig").Value;

const HashMap = @import("std").HashMap;
const Allocator = @import("std").mem.Allocator;

const TABLE_MAX_LOAD = 75;

const TableCtx = struct {
    fn hash(_: TableCtx, s: ObjString) u64 {
        var res = 2166136261;
        for (s.chars) |c| {
            res ^= c;
            res *= 16777619;
        }
        return res;
    }

    fn eql(_: TableCtx, s1: ObjString, s2: ObjString) bool {
        return ObjString.cmp(s1, s2) == .eq;
    }
};

const Table = struct {
    entires: HashMap(*ObjString, Value, TableCtx, TABLE_MAX_LOAD),

    pub fn init(self: *Table, alloc: Allocator) void {
        self.entires = .init(alloc);
    }

    pub fn deinit(self: *Table) void {
        self.entires.deinit();
    }

    pub fn put(self: *Table, key: *ObjString, value: Value) !bool {
        const res = try self.entires.getOrPut(key, value);
        return res.found_existing;
    }

    pub fn addAll(from: *Table, to: *Table) !void {
        var it = from.entires.iterator();
        while (it.next()) |entry| {
            try to.put(entry.key_ptr, entry.value_ptr);
        }
    }

    pub fn get(self: *Table, key: *ObjString) ?Value {
        return self.entires.get(key);
    }

    pub fn delete(self: *Table, key: *ObjString) bool {
        return self.entires.remove(key);
    }
};
