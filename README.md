# ORE Zig SDK (`ore-zig`)

[![Zig Version](https://img.shields.io/badge/Zig-0.12.0+-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Core Kernel](https://img.shields.io/badge/Core-ore--kernel-blue.svg)](https://github.com/Mahavishnu-K/ore-kernel)

The official Zig SDK for the **[ORE (Open Runtime Environment) Kernel](https://github.com/Mahavishnu-K/ore-kernel)**.

This SDK provides the systems-level abstractions for **True Memory Fusion** (`ore_sys`), allowing Zig Host Agents to dynamically load, link, and execute `.wasi.so` plugins at runtime with zero-copy overhead. 

It heavily leverages Zig's `comptime` features to provide an elegant, type-safe API for interacting with raw WebAssembly imports behind the scenes.

## Features

- **Zero-Copy Overhead**: True memory fusion execution model.
- **Dynamic Loading**: Dynamically load, link, and execute WebAssembly plugins at runtime using `ore_dlopen` and `ore_dlsym`.
- **Secure & Type-safe Binding**: Bind plugin functions securely using native Zig syntax.

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
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ADD THESE TWO LINES:
    const ore_dep = b.dependency("ore-zig", .{});
    exe.root_module.addImport("ore_sys", ore_dep.module("ore_sys"));

    b.installArtifact(exe);
}
```

---

## API Reference

The SDK exports the `Plugin` struct and `OreError` for robust error handling when interacting with the ORE kernel.

### `OreError`
- `error.PluginLoadFailed`: Returned when the `.wasi.so` file fails to load into physical RAM.
- `error.SymbolNotFound`: Returned when the requested function signature cannot be found in the loaded plugin.

### `Plugin`

#### `Plugin.load(plugin_name: []const u8) OreError!Plugin`
Loads a plugin from the ORE OS into physical RAM using `ore_dlopen`. 

#### `Plugin.bind(self: Plugin, comptime FuncSig: type, symbol: []const u8) OreError!*const FuncSig`
Extracts a function dynamically and casts it to the exact type instantly using `ore_dlsym`. Automatically handles WASM C-function pointer casting.

---

## Usage (Host Agent)

Here is a simple example of how to use the SDK to load and execute a plugin.

```zig
const std = @import("std");
const ore = @import("ore_sys");

pub fn main() !void {
    // 1. Load the Plugin into your physical RAM
    var plugin = try ore.Plugin.load("parser.wasi.so");

    // 2. ZERO FRICTION BINDING! No pointers, no `callconv(.c)`, no typedefs!
    const parse = try plugin.bind(fn([*]const u8, u32, u32) u32, "count_error_flags");

    // 3. Execute
    const data = [_]u8{ 0x00, 0xFF, 0x01 };
    const errors = parse(&data, data.len, 0xFF);
    
    std.debug.print("Errors found: {}\n", .{errors});
}
```

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
