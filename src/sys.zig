const std = @import("std");

// RAW WEBASSEMBLY IMPORTS
extern "env" fn ore_dlopen(filename_ptr: [*]const u8, filename_len: u32) i32;
extern "env" fn ore_dlsym(handle: i32, symbol_ptr: [*]const u8, symbol_len: u32) i32;

pub const OreError = error{
    PluginLoadFailed,
    SymbolNotFound,
};

// The ABI Type Transformer
fn ToCAbiPtr(comptime T: type) type {
    const info = @typeInfo(T);
    
    if (info == .Pointer) return T;
    
    if (info != .Fn) {
        @compileError("ORE Error: bind() requires a function type like `fn(i32, i32) i32`");
    }

    var new_fn = info.Fn;
    new_fn.calling_convention = .c;
    
    return *const @Type(.{ .Fn = new_fn });
}

// THE HOST API
pub const Plugin = struct {
    handle: i32,

    pub fn load(plugin_name: []const u8) OreError!Plugin {
        const handle = ore_dlopen(plugin_name.ptr, @as(u32, @intCast(plugin_name.len)));
        
        if (handle <= 0) {
            return error.PluginLoadFailed;
        }
        
        return Plugin{ .handle = handle };
    }

    pub fn bind(self: Plugin, comptime FuncSig: type, symbol: []const u8) OreError!ToCAbiPtr(FuncSig) {
        const func_idx = ore_dlsym(self.handle, symbol.ptr, @as(u32, @intCast(symbol.len)));
        
        if (func_idx <= 0) {
            return error.SymbolNotFound;
        }

        const FinalType = ToCAbiPtr(FuncSig);

        return @as(FinalType, @ptrFromInt(@as(usize, @intCast(func_idx))));
    }
};