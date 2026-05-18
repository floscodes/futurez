const std = @import("std");
const root = @import("root.zig");
const TaskWrapper = @import("task_wrapper.zig").TaskWrapper;

/// Represents an error that occurs when the CPU count is invalid.
const CpuCountError = error{
    InvalidCpuCount,
};

fn io() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// The `Runtime` struct provides a thread pool and task management for execution of functions using coroutines.
/// It allows spawning tasks that can be awaited, and manages the lifecycle of these tasks.
/// The runtime can be initialized with a specific number of CPU cores, or it defaults to the number of available cores.
/// It handles task scheduling, execution, and cleanup, ensuring that resources are properly managed.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    task_queue: std.ArrayList(*Task),
    mutex: std.Io.Mutex,
    cond: std.Io.Condition,
    threads: []std.Thread,
    threads_started: bool = false,
    stop_flag: *bool,
    const Self = @This();

    /// Initializes the runtime with the default number of CPU cores available on the system.
    pub fn init(allocator: std.mem.Allocator) !Self {
        const cores = try std.Thread.getCpuCount();
        return try Self.initRuntime(cores, allocator);
    }

    /// Initializes the runtime with a specific number of CPU cores.
    pub fn initWithCores(allocator: std.mem.Allocator, cpu_count: usize) !Self {
        const cores = try std.Thread.getCpuCount();
        if (cpu_count == 0 or cpu_count > cores) return CpuCountError.InvalidCpuCount;
        return try Self.initRuntime(cpu_count, allocator);
    }

    // Private function to initialize the runtime with a specific number of CPU cores.
    fn initRuntime(cpu_count: usize, allocator: std.mem.Allocator) !Self {
        const stop = try allocator.create(bool);
        stop.* = false;
        const task_queue = std.ArrayList(*Task).empty;
        const threads = try allocator.alloc(std.Thread, cpu_count);
        return Self{
            .allocator = allocator,
            .task_queue = task_queue,
            .threads = threads,
            .mutex = .init,
            .cond = .init,
            .stop_flag = stop,
        };
    }

    /// Deinitializes the runtime, cleaning up resources and ensuring all tasks are completed.
    /// This method waits for all tasks in the queue to finish before shutting down the worker threads.
    /// It is important to call this method to avoid memory leaks and ensure that all resources are properly released.
    pub fn deinit(self: *Self) void {
        while (self.task_queue.items.len > 0) {
            _ = self.task_queue.items[0].join(*anyopaque);
        }

        if (self.threads_started) {
            std.Io.Threaded.mutexLock(&self.mutex);
            self.stop_flag.* = true;
            self.cond.broadcast(io());
            std.Io.Threaded.mutexUnlock(&self.mutex);
            for (self.threads) |thread| {
                thread.join();
            }
        }

        self.allocator.free(self.threads);
        self.allocator.destroy(self.stop_flag);
        self.task_queue.deinit(self.allocator);
    }

    /// Spawns a task using the provided function `F` and parameters `params`.
    /// Params must match the expected parameters of the function `F` and must be passed as a tuple.
    /// The spawn-method returns a `Task` that can be joined to get the result of the operation.
    pub fn spawn(self: *Self, comptime F: anytype, params: anytype) !*Task {
        if (!self.threads_started) {
            for (self.threads) |*thread| {
                thread.* = try std.Thread.spawn(.{}, workerThread, .{self});
            }
            self.threads_started = true;
        }
        const ParamType = @TypeOf(params);
        const task_wrapper = TaskWrapper(F, ParamType);
        var gen_instance = task_wrapper.create(self.allocator);
        gen_instance.params = params;
        errdefer gen_instance.destroy();

        const wrapper_instance = try self.allocator.create(WrapperStruct);
        errdefer self.allocator.destroy(wrapper_instance);

        wrapper_instance.* = .{
            .self = @alignCast(@ptrCast(gen_instance)),
            .run_fn = @alignCast(@ptrCast(gen_instance.run_fn)),
            .params = @alignCast(@ptrCast(&gen_instance.params)),
            .output = @alignCast(@ptrCast(&gen_instance.output)),
            .wrapper_destroy_fn = @alignCast(@ptrCast(gen_instance.destroy_fn)),
        };

        const task = try self.allocator.create(Task);
        errdefer self.allocator.destroy(task);

        task.* = Task{
            .runtime = self,
            .task_wrapper = wrapper_instance,
        };

        std.Io.Threaded.mutexLock(&self.mutex);
        errdefer std.Io.Threaded.mutexUnlock(&self.mutex);
        try self.task_queue.append(self.allocator, task);
        std.Io.Threaded.mutexUnlock(&self.mutex);
        self.cond.signal(io());
        return task;
    }
};

/// Represents a task that can be joined, encapsulating the result of an operation that runs on a coroutine.
pub const Task = struct {
    const TaskSelf = @This();
    runtime: *Runtime,
    task_wrapper: *WrapperStruct,
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    status: TaskStatus = .Pending,

    /// Joins a task, blocking until the operation is complete.
    /// Returns the result of the operation, which is of type `T`.
    /// The task must be created with a compatible type for `T`.
    /// Make sure that the type `T` matches the output type of the executed function.
    /// After joining, the task is cleaned up and its resources are released.
    pub fn join(self: *Task, T: type) T {
        std.Io.Threaded.mutexLock(&self.mutex);
        while (self.status != .Finished) {
            self.cond.waitUncancelable(io(), &self.mutex);
        }
        const output: *T = @alignCast(@ptrCast(self.task_wrapper.output));
        const result = output.*;

        self.task_wrapper.wrapper_destroy_fn(self.task_wrapper.self);
        self.runtime.allocator.destroy(self.task_wrapper);

        for (self.runtime.task_queue.items, 0..) |item, idx| {
            if (item == self) {
                std.Io.Threaded.mutexLock(&self.runtime.mutex);
                _ = self.runtime.task_queue.orderedRemove(idx);
                std.Io.Threaded.mutexUnlock(&self.runtime.mutex);
                self.runtime.cond.broadcast(io());
                break;
            }
        }

        std.Io.Threaded.mutexUnlock(&self.mutex);
        self.runtime.allocator.destroy(self);
        return result;
    }
};

// A helper struct to encapsulate the function to be run and its parameters.
const WrapperStruct = struct {
    self: *anyopaque,
    run_fn: *const fn (*anyopaque) void,
    params: *const anyopaque,
    output: *anyopaque,
    wrapper_destroy_fn: *const fn (*anyopaque) void,
};

// Represents the status of a task in the runtime.
const TaskStatus = enum {
    Pending,
    Running,
    Finished,
};

// The worker thread function that processes tasks from the runtime's task queue.
fn workerThread(runtime: *Runtime) void {
    while (true) {
        std.Io.Threaded.mutexLock(&runtime.mutex);

        while (runtime.task_queue.items.len == 0 and !runtime.stop_flag.*) {
            runtime.cond.waitUncancelable(io(), &runtime.mutex);
        }

        if (runtime.stop_flag.*) {
            std.Io.Threaded.mutexUnlock(&runtime.mutex);
            break;
        }

        var task: ?*Task = null;

        for (runtime.task_queue.items) |t| {
            if (t.status == .Pending) {
                t.status = .Running;
                task = t;
                break;
            }
        }

        std.Io.Threaded.mutexUnlock(&runtime.mutex);

        if (task) |t| {
            std.Io.Threaded.mutexLock(&t.mutex);
            t.task_wrapper.run_fn(t.task_wrapper.self);
            t.status = .Finished;
            t.cond.broadcast(io());
            std.Io.Threaded.mutexUnlock(&t.mutex);
            // Do NOT access t after this point: join() may free it immediately.
        }
    }
}
