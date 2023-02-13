const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const dest_folder = "zig-packages";
    defer std.debug.assert(!gpa.deinit());
    const a = &gpa.allocator;

    try run(a, .{"wget", "https://github.com/frmdstryr/zhp/archive/refs/tags/v0.9.0.zip", "-O", "zhp.zip"});
    try run(a, .{"unzip", "-q", "zhp.zip", "-d", dest_folder});
    try run(a, .{"rm", "zhp.zip"});
}


pub fn run(allocator: *std.mem.Allocator, args: anytype) !void {
    var cmd: [args.len][]const u8 = undefined;
    inline for(args) |arg, i| {
        cmd[i] = arg;
    }
    var process = try std.ChildProcess.init(cmd[0..], allocator);
    defer process.deinit();
    try process.spawn();
    _ = try process.wait();

}
