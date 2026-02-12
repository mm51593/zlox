const std = @import("std");

pub fn ensureCapacity(comptime T: type, array: []T, count: usize, alloc: std.mem.Allocator) ![]T {
    if (array.len < count + 1) {
        const newCap = growCapacity(array.len);
        return alloc.realloc(array, newCap) catch |err| (return err);
    }

    return array;
}

fn growCapacity(capacity: usize) usize {
    if (capacity < 8) {
        return 8;
    }

    return capacity * 2;
}

fn reallocateArray(comptime T: type, ptr: []T, new_size: usize, alloc: std.mem.Allocator) ![]T {
    return alloc.realloc(ptr, new_size) catch |err| (return err);
}
