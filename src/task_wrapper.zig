const std = @import("std");

// A generic wrapper for tasks that can be used with the runtime.
pub fn TaskWrapper(comptime F: anytype, comptime ParamType: type) type {
    const tinfo = @typeInfo(@TypeOf(F));
    if (tinfo != .@"fn") {
        @compileError("Spawned task must be a function!");
    }

    const ReturnType = tinfo.@"fn".return_type.?;
    const OutputType = switch (@typeInfo(ReturnType)) {
        .error_union => |eu| eu.payload,
        else => ReturnType,
    };

    return struct {
        pub const Self = @This();

        pub fn create(allocator: std.mem.Allocator) *Self {
            const instance = allocator.create(Self) catch unreachable;

            instance.* = Self{
                .params = undefined,
                .output = undefined,
                .run_fn = &Self.run_thunk,
                .destroy_fn = &Self.destroy_thunk,
                .allocator = allocator,
            };
            return instance;
        }

        pub fn run(self: *Self) void {
            const result = @call(.auto, F, self.params);
            if (comptime @typeInfo(ReturnType) == .error_union) {
                self.output = result catch unreachable;
            } else {
                self.output = result;
            }
        }

        pub fn run_thunk(ctx: *anyopaque) void {
            const self: *Self = @alignCast(@ptrCast(ctx));
            self.run();
        }

        pub fn destroy(self: *Self) void {
            self.allocator.destroy(self);
        }

        pub fn destroy_thunk(ctx: *anyopaque) void {
            const self: *Self = @alignCast(@ptrCast(ctx));
            self.destroy();
        }

        params: ParamType,
        output: OutputType,
        run_fn: *const fn (*anyopaque) void,
        destroy_fn: *const fn (*anyopaque) void,
        allocator: std.mem.Allocator,
    };
}
