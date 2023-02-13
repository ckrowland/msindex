const std = @import("std");

const preFedValue = struct {
    year: i32,
    netWorthAtCurrentPrices: f64,
    stockMarketAtCurrentPrices: f64 
};

fn getFloatFromValue(v: std.json.Value) f64 {
    const float = switch (v) {
        .Integer => |num| @intToFloat(f64, num),
        .Float => |num| num,
    };
    return float;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    const json = @embedFile("./static/json/1900-45-nw-market.json");
    std.debug.assert(std.json.validate(json));

    var tree = try parser.parse(json);
    defer tree.deinit();

    for (tree.root.Array.items) |v| {
        var it = v.Object;
        const year = it.get("year").?.Integer;
        const net_worth = getFloatFromValue(it.get("netWorthAtCurrentPrices").?);
        const equity = getFloatFromValue(it.get("stockMarketAtCurrentPrices").?);
        std.debug.print("{any}, {any}, {any}\n", .{year, net_worth, equity});
    }

    //var ts = std.json.TokenStream.init(json);
    //const preFedArray = try std.json.parse(
    //    [52]preFedValue,
    //    &ts,
    //    .{ .allocator = hpa }
    //);
    //defer std.json.parseFree(
    //    [52]preFedValue,
    //    preFedArray,
    //    .{ .allocator = hpa }
    //);

    //Send two GET requests to the FRED API
    //var httpClient = std.http.Client{.allocator = hpa };
    //defer httpClient.deinit();
    //var req = try httpClient.request(.{
    //        .scheme = "https",
    //        .host = "api.stlouisfed.org",
    //        .path = "/fred/series/observations?series_id=NCBCEL&api_key=89f2a06210de32e0ea49e2aa9106543a&file_type=json",
    //        .port = 443,
    //        .user = null,
    //        .password = null,
    //        .query = null,
    //        .fragment = null,
    //    },
    //    .{},
    //    .{}
    //);
    //defer req.deinit();
    //var buffer = [_]u8{0} ** 10000;
    //_ = try req.readAll(&buffer);
    //std.debug.print("{any}\n\n", .{@TypeOf(&buffer)});
    //std.debug.assert(std.json.validate(&buffer));
}
