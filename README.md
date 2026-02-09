# coroutinez

[![CI](https://github.com/floscodes/coroutinez/actions/workflows/ci.yml/badge.svg)](https://github.com/floscodes/coroutinez/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

coroutinez is a small runtime for running tasks using coroutines in Zig.


## Minimal Example

```zig
const std = @import("std");
const coroutinez = @import("coroutinez");
const Runtime = coroutinez.Runtime;

fn main() !void {
    const allocator = std.heap.page_allocator;
    const rt = try Runtime.init(allocator);
    defer rt.deinit();

    const task = try rt.spawn(myTaskFunction, .{});
    const task = task.join(i32);
    std.debug.print("Result: {d}\n", .{result});
}

fn myTaskFunction() i32 {
    return 42;
}
```

For a complete example showcasing advanced usage with dynamic allocations and multiple parameters, see [examples/basic.zig](./examples/basic.zig).

## Overview

coroutinez spawns as many worker threads as logical CPU cores available on your machine. These threads continuously pick up and run asynchronous tasks you spawn via `Runtime.spawn`. Finished tasks remain in the task queue until you call the `join()` method on the associated `*Task` to retrieve the result.

You can also control the number of worker threads by initializing the runtime with a specific core count using `initWithCores()`:

```zig
const allocator = std.heap.page_allocator;
const rt = try Runtime.initWithCores(allocator, 16);
defer rt.deinit();
```
