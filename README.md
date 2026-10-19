# ORE Zig SDK (`ore-zig`)

[![Zig Version](https://img.shields.io/badge/Zig-0.17.0+-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Core Kernel](https://img.shields.io/badge/Core-ore--kernel-blue.svg)](https://github.com/Mahavishnu-K/ore-kernel)

The official Zig SDK for the **[ORE (Open Runtime Environment) Kernel](https://github.com/Mahavishnu-K/ore-kernel)**.

This SDK provides the systems-level abstractions for **True Memory Fusion** (`ore_sys`), allowing Zig Host Agents to dynamically load, link, execute, and unload `.wasi.so` plugins at runtime with zero-copy overhead.

It heavily leverages Zig's `comptime` features to provide an elegant, type-safe API for interacting with raw WebAssembly imports behind the scenes.

## Features

- **Zero-Copy Overhead**: True memory fusion execution model.
- **Dynamic Loading**: Load, link, and execute WebAssembly plugins at runtime using `ore_dlopen` and `ore_dlsym`.
- **Zero-Friction Binding**: Bind plugin functions with plain, idiomatic Zig function types. No `callconv(.c)` needed.
- **Deterministic Unloading**: Close plugins explicitly with `ore_dlclose`. The kernel poisons their function table slots.
- **Zero-Allocation Error Inspection**: Read the kernel's last error message through `ore_dlerror` into a static buffer, with no allocator required.

---

## Installation

Run this in your Zig project directory to fetch the SDK:

```bash
zig fetch --save git+https://github.com/Mahavishnu-K/ore-zig.git#main
```

### Setup `build.zig`

Add the module to your `build.zig` file so your application can import it:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my_agent",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // ADD THESE TWO LINES:
    const ore_dep = b.dependency("ore-zig", .{});
    exe.root_module.addImport("ore_sys", ore_dep.module("ore_sys"));

    b.installArtifact(exe);
}
```

---

## API Reference

The `ore_sys` module exports the `Plugin` struct, the `OreError` error set, and the `lastError()` function.

### `OreError`
- `error.PluginLoadFailed`: The `.wasi.so` file failed to load into physical RAM.
- `error.SymbolNotFound`: The requested symbol was not found in the loaded plugin.
- `error.PluginCloseFailed`: The kernel refused or failed to unload the plugin.

When any of these is returned, call `lastError()` to get the kernel's explanation.

### `Plugin`

#### `Plugin.load(plugin_name: []const u8) OreError!Plugin`
Loads a plugin from the ORE OS into physical RAM using `ore_dlopen`.

#### `Plugin.bind(self: Plugin, comptime FuncSig: type, symbol: []const u8) OreError!*const FuncSig`
Looks up `symbol` with `ore_dlsym` and returns it as a function pointer of type `*const FuncSig`. Pass a plain Zig function type such as `fn (u32) u32`. See [Zero Friction Binding](#the-webassembly-secret-zero-friction-binding) for why no calling convention is needed.

#### `Plugin.close(self: *Plugin) OreError!void`
Deterministically unloads the plugin using `ore_dlclose`. The kernel poisons the plugin's function table slots, so function pointers previously returned by `bind()` can no longer reach the unloaded code. Do not call them after closing. On success the handle is reset to `0`, which makes repeated calls to `close()` a safe no-op.

### `lastError() ?[]const u8`
Fetches the last error string emitted by the ORE kernel through `ore_dlerror`, then clears it. Returns `null` if there is no pending error.

This function is zero-allocation. The returned slice points into a shared 512-byte static buffer and is only valid until the next call to `lastError()`. Copy it if you need to keep it.

---

## Usage (Host Agent)

Here is a complete example: load a plugin, bind a function, run it, and unload the plugin.

```zig
const std = @import("std");
const ore = @import("ore_sys");

pub fn main() !void {
    // 1. Load the plugin into physical RAM
    var plugin = ore.Plugin.load("parser.wasi.so") catch |err| {
        std.debug.print("load failed: {s}\n", .{ore.lastError() orelse "unknown error"});
        return err;
    };
    // 4. Deterministically unload when done
    defer plugin.close() catch {
        std.debug.print("close failed: {s}\n", .{ore.lastError() orelse "unknown error"});
    };

    // 2. ZERO FRICTION BINDING! No pointers, no `callconv(.c)`, no typedefs!
    const parse = try plugin.bind(fn ([*]const u8, u32, u32) u32, "count_error_flags");

    // 3. Execute
    const data = [_]u8{ 0x00, 0xFF, 0x01 };
    const errors = parse(&data, data.len, 0xFF);

    std.debug.print("Errors found: {}\n", .{errors});
}
```

> `close()` takes `*Plugin`, so declare the plugin with `var`, not `const`.

---

## Kernel Imports

Under the hood, `ore_sys` declares four raw WebAssembly imports that the ORE kernel provides to the host module:

| Import        | Signature                          | Returns                                         |
| ------------- | ---------------------------------- | ----------------------------------------------- |
| `ore_dlopen`  | `(name_ptr, name_len) i32`         | Plugin handle (`> 0`), or `<= 0` on failure     |
| `ore_dlsym`   | `(handle, sym_ptr, sym_len) i32`   | Function table index (`> 0`), or `<= 0`         |
| `ore_dlclose` | `(handle) i32`                     | `0` on success, non-zero on failure             |
| `ore_dlerror` | `(buf_ptr, buf_len) i32`           | Bytes written into `buf` (`<= 0` means no error) |

You should never need to call these directly. The `Plugin` API and `lastError()` wrap them.

---

## ORE FFI Rule of Thumb: Strict 32/64-bit ABI

For developers building raw, high-performance WebAssembly plugins, passing smaller data types as 32-bit integers across the FFI (Foreign Function Interface) boundary is an industry-standard best practice.

To prevent `call_indirect` signature mismatches and ensure zero-overhead execution, ORE rejects bloated wrapper code (like the Component Model `.wit` files). Instead, we stick to the raw C-ABI, offering bare-metal performance.

**The Rule**: When passing arguments between the Host and the Plugin via the C-ABI, strictly use `u32`, `i32`, `f32`, or `f64`. WebAssembly does not natively support 8-bit or 16-bit function arguments on the call stack. 

*If you need to pass a single byte (like a `u8` flag), cast it to a `u32` before crossing the OS boundary.* Pointers (which are just 32-bit memory offsets in WASM32) map perfectly to this architecture.

---

## The WebAssembly Secret: Zero Friction Binding

In native x86/ARM programming, calling conventions (`.c`, `.stdcall`, `.fastcall`) are critical because they dictate whether arguments go into CPU registers or onto the stack. Getting it wrong causes immediate crashes.

**WebAssembly does not have calling conventions.**

At the bytecode level, WASM only has types: `i32`, `i64`, `f32`, and `f64`. A pointer is just an `i32`. When Zig compiles a `callconv(.c)` function and a `callconv(.zig)` function that use primitive types or pointers, they compile down to the exact same WebAssembly signature (e.g., `(param i32 i32 i32) (result i32)`).

Because the WASM runtime only checks the WASM signature, it literally does not know or care what calling convention Zig thinks it is using.

**This is the magic of ORE's Zero Friction Binding**: The developer doesn't need to fight the Zig compiler, hack `@Type`, or clutter their code with `callconv(.c)`. You just pass the clean, idiomatic Zig function signature directly into `bind()`, and the SDK handles the pointer casts internally.

---

## Compiling

Use the ORE CLI to automatically handle the strict WebAssembly C-ABI linker flags:

```bash
ore mktool . --host
```

---

## Related Projects

- **[ore-kernel](https://github.com/Mahavishnu-K/ore-kernel)**: The main Open Runtime Environment Kernel repository.
