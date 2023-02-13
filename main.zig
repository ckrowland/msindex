// -------------------------------------------------------------------------- //
// Copyright (c) 2019-2020, Jairus Martin.                                    //
// Distributed under the terms of the MIT License.                            //
// The full license is in the file LICENSE, distributed with this software.   //
// -------------------------------------------------------------------------- //
const std = @import("std");
const web = @import("zhp");
const Request = web.Request;
const Response = web.Response;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const io_mode = .evented;
pub const log_level = .debug;

/// This handler demonstrates how to send a template resrponse using
/// zig's built-in formatting.
const TemplateHandler = struct {
    const template = @embedFile("templates/index.html");

    pub fn get(self: *TemplateHandler, req: *Request, resp: *Response) !void {
        _ = self;
        _ = req;
        @setEvalBranchQuota(100000);
        try resp.stream.print(template, .{});
    }
};

/// When an error is returned the framework will return the error handler response
const ErrorTestHandler = struct {
    pub fn get(self: *ErrorTestHandler, req: *Request, resp: *Response) !void {
        _ = self;
        _ = req;
        try resp.stream.writeAll("Do some work");
        return error.Ooops;
    }
};

// The routes must be defined in the "root"
pub const routes = [_]web.Route{
    web.Route.create("index", "/", TemplateHandler),
    web.Route.static("static", "/static/", "msindex/static/"),
};

pub const middleware = [_]web.Middleware{
    //web.Middleware.create(web.middleware.LoggingMiddleware),
    //web.Middleware.create(web.middleware.SessionMiddleware),
};

pub fn main() !void {
    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    var app = web.Application.init(allocator, .{ .debug = true });

    defer app.deinit();
    try app.listen("127.0.0.1", 9000);
    try app.start();
}
