const std = @import("std");
const runtime = @import("runtime.zig");

// Make the Runtime available at the root level
pub const Runtime = runtime.Runtime;

// Test functions
fn testfn(_: []const u8) i32 {
    return 31;
}

fn testfn2(s: []const u8, n: i32, allocator: std.mem.Allocator) []const u8 {
    var str = std.ArrayList(u8).empty;
    defer str.deinit(allocator);

    str.appendSlice(allocator, s) catch unreachable;
    str.appendSlice(allocator, "world!") catch unreachable;
    str.print(allocator, "{d}", .{n}) catch unreachable;

    return str.toOwnedSlice(allocator) catch unreachable;
}

fn testfn3(allocator: std.mem.Allocator) ![]const u8 {
    var str = std.ArrayList(u8).empty;
    defer str.deinit(allocator);

    try str.appendSlice(allocator, "testfn3");
    try str.appendSlice(allocator, " world!");

    return try str.toOwnedSlice(allocator);
}

// TESTS

test "init and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    rt.deinit();
}

test "init Runtime, spawn task, join it and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const task = try rt.spawn(testfn, .{"testparam"});
    const result = task.join(i32);
    std.debug.assert(result == 31);
}

test "init Runtime, spawn two tasks with testfn, join them and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const task1 = try rt.spawn(testfn, .{"testparam"});
    const task2 = try rt.spawn(testfn, .{"testparam"});
    const result1 = task1.join(i32);
    const result2 = task2.join(i32);
    std.debug.assert(result2 == 31);
    std.debug.assert(result1 == 31);
}

test "init Runtime, spawn task without joining it and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const task = try rt.spawn(testfn, .{"testparam"});
    _ = task;
}

test "testfn2" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const task = try rt.spawn(testfn2, .{ "hello ", 42, allocator });
    const result = task.join([]const u8);
    defer allocator.free(result);
    std.debug.assert(std.mem.eql(u8, result, "hello world!42"));
}

test "spawn two tasks, join them and deinit Runtime" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const task1 = try rt.spawn(testfn, .{"task1"});

    const task2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });

    const result1 = task1.join(i32);
    std.debug.assert(result1 == 31);

    const result2 = task2.join([]const u8);
    defer allocator.free(result2);

    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));
}

test "testfn3" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();
    const task = try rt.spawn(testfn3, .{allocator});
    const result = task.join([]const u8);
    defer allocator.free(result);
    std.debug.assert(std.mem.eql(u8, result, "testfn3 world!"));
}

test "testfn, testfn2 and testfn3" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const future1 = try rt.spawn(testfn, .{"task1"});
    const future2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });
    const future3 = try rt.spawn(testfn3, .{allocator});

    const result1 = future1.join(i32);
    std.debug.assert(result1 == 31);

    const result2 = future2.join([]const u8);
    defer allocator.free(result2);
    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));

    const result3 = future3.join([]const u8);
    defer allocator.free(result3);
    std.debug.assert(std.mem.eql(u8, result3, "testfn3 world!"));
}

test "test all testfns two times and join them" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    const future1 = try rt.spawn(testfn, .{"task1"});
    const future2 = try rt.spawn(testfn2, .{ "task2 ", 100, allocator });
    const future3 = try rt.spawn(testfn3, .{allocator});

    const result1 = future1.join(i32);
    std.debug.assert(result1 == 31);

    const result2 = future2.join([]const u8);
    defer allocator.free(result2);
    std.debug.assert(std.mem.eql(u8, result2, "task2 world!100"));

    const result3 = future3.join([]const u8);
    defer allocator.free(result3);
    std.debug.assert(std.mem.eql(u8, result3, "testfn3 world!"));

    // Run them again
    const future4 = try rt.spawn(testfn, .{"task1"});
    const future5 = try rt.spawn(testfn2, .{ "task2 ", 200, allocator });
    const future6 = try rt.spawn(testfn3, .{allocator});

    const result4 = future4.join(i32);
    std.debug.assert(result4 == 31);

    const result5 = future5.join([]const u8);
    defer allocator.free(result5);
    std.debug.assert(std.mem.eql(u8, result5, "task2 world!200"));

    const result6 = future6.join([]const u8);
    defer allocator.free(result6);
    std.debug.assert(std.mem.eql(u8, result6, "testfn3 world!"));
}

test "spawn testfn, testfn2 and tesfn3 20 times and join them, free memory of the resultsof testfn2 and testfn3" {
    const allocator = std.testing.allocator;
    var rt = try Runtime.init(allocator);
    defer rt.deinit();

    for (0..20) |i| {
        const future1 = try rt.spawn(testfn, .{"task1"});
        const n: i32 = @intCast(i);
        const future2 = try rt.spawn(testfn2, .{ "task2 ", n, allocator });
        const future3 = try rt.spawn(testfn3, .{allocator});

        const result1 = future1.join(i32);
        std.debug.assert(result1 == 31);

        const result2 = future2.join([]const u8);
        defer allocator.free(result2);
        const number_string = std.fmt.allocPrint(allocator, "{d}", .{n}) catch unreachable;
        defer allocator.free(number_string);
        const expected_string = std.mem.concat(allocator, u8, &.{ "task2 world!", number_string }) catch unreachable;
        defer allocator.free(expected_string);
        std.debug.assert(std.mem.eql(u8, result2, expected_string));

        const result3 = future3.join([]const u8);
        defer allocator.free(result3);
        std.debug.assert(std.mem.eql(u8, result3, "testfn3 world!"));
    }
}
