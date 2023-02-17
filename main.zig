const std = @import("std");
const zap = @import("zap");

fn on_request(r: zap.SimpleRequest) void {
    r.setStatus(.not_found);
    _ = r.sendBody("<html><body><h1>404 - File not found</h1></body></html>");
}

pub fn main() !void {
    var listener = zap.SimpleHttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        .public_folder = "static",
        .log = true,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 1,
        .workers = 1,
    });
}
