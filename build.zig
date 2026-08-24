const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("ore_sys", .{
        .root_source_file = b.path("src/sys.zig"),
    });

    // The HTTP Client SDK 
    // _ = b.addModule("ore_client", .{
    //     .root_source_file = b.path("src/client.zig"),
    // });
}