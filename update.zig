const std = @import("std");

const MSPoint = struct {
    date: [10]u8,
    equity: f64 = 0,
    netWorth: f64 = 0,
    index: f64 = 0,

    pub fn format(
        p: MSPoint,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("\n\n{s}\nEquity: {any}\nNetWorth: {any}\nIndex: {any}", .{
            p.date,
            p.equity,
            p.netWorth,
            p.index,
        });
    }
};

fn appendPreFED(array: *std.ArrayList(MSPoint), comptime file: []const u8) void {
    const json = @embedFile(file);
    std.debug.assert(std.json.validate(json));

    var parser = std.json.Parser.init(array.allocator, false);
    defer parser.deinit();
    var tree = parser.parse(json) catch unreachable;
    defer tree.deinit();
    for (tree.root.Array.items) |v| {
        var it = v.Object;
        var date = [_]u8{0} ** 10;
        const year = it.get("year").?.Integer;
        _ = std.fmt.bufPrint(&date, "{d}-01-01", .{year}) catch unreachable;
        const netWorth = it.get("netWorthAtCurrentPrices").?.Float;
        const equity = it.get("stockMarketAtCurrentPrices").?.Float;

        array.append(.{
            .date = date,
            .equity = equity,
            .netWorth = netWorth,
        }) catch unreachable;
    }
}

fn getFredJson(alloc: std.mem.Allocator, series_id: [:0]const u8) []u8 {
    var path = std.fmt.allocPrint(alloc, "/fred/series/observations?series_id={s}&api_key=89f2a06210de32e0ea49e2aa9106543a&file_type=json&observation_start=1952-01-01&frequency=a", .{series_id}) catch unreachable;
    var httpClient = std.http.Client{ .allocator = alloc };
    defer httpClient.deinit();
    //TODO: Read environment variable for api_key
    var req = httpClient.request(.{
        .scheme = "https",
        .host = "api.stlouisfed.org",
        .path = path,
        .port = 443,
        .user = null,
        .password = null,
        .query = null,
        .fragment = null,
    }, .{}, .{}) catch unreachable;
    defer req.deinit();

    var buffer = [_]u8{0} ** 50000;
    const numBytesRead = req.readAll(&buffer) catch unreachable;
    std.debug.assert(std.json.validate(buffer[0..numBytesRead]));
    return buffer[0..numBytesRead];
}

//Since quarterly reports use the first date of the quarter,
//on a time axis it needs to be the start of the next quarter.
fn correctDate(date: []const u8) [10]u8 {
    var month = std.fmt.parseUnsigned(u32, date[5..7], 10) catch unreachable;
    var year = std.fmt.parseUnsigned(u32, date[0..4], 10) catch unreachable;

    month = (month + 3) % 12;
    if (month == 1) {
        year += 1;
    }

    var buf: [10]u8 = undefined;
    const updated_date = std.fmt.bufPrint(&buf, "{d}-{:0>2}{s}", .{
        year,
        month,
        date[7..10],
    }) catch unreachable;
    return updated_date[0..10].*;
}

fn appendEquity(array: *std.ArrayList(MSPoint)) void {
    const json = getFredJson(array.allocator, "NCBCEL");

    var parser = std.json.Parser.init(array.allocator, false);
    defer parser.deinit();
    var tree = parser.parse(json) catch unreachable;
    defer tree.deinit();

    var observations = tree.root.Object.get("observations").?;
    for (observations.Array.items) |value| {
        const val = value.Object;

        const date = val.get("date").?.String;
        const updatedDate = correctDate(date);

        const equityStr = val.get("value").?.String;
        const equity = std.fmt.parseFloat(f64, equityStr) catch {
            continue;
        };

        array.append(.{
            .date = updatedDate,
            .equity = equity,
        }) catch unreachable;
    }
}

fn insertNetWorth(MSPoints: *std.ArrayList(MSPoint)) void {
    const json = getFredJson(MSPoints.allocator, "TNWMVBSNNCB");

    var parser = std.json.Parser.init(MSPoints.allocator, false);
    defer parser.deinit();
    var tree = parser.parse(json) catch unreachable;
    defer tree.deinit();

    var observations = tree.root.Object.get("observations").?;

    var idx: usize = 0;
    for (observations.Array.items) |value| {
        const val = value.Object;
        const netWorthStr = val.get("value").?.String;
        const netWorth = std.fmt.parseFloat(f64, netWorthStr) catch {
            continue;
        };
        const date = val.get("date").?.String;
        const updatedDate = correctDate(date);
        while (!std.mem.eql(u8, &updatedDate, &MSPoints.items[idx].date)) {
            idx += 1;
        }
        MSPoints.items[idx].netWorth = netWorth;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var MSPoints = std.ArrayList(MSPoint).init(allocator);
    defer MSPoints.deinit();

    appendPreFED(&MSPoints, "./static/json/preFed.json");
    appendEquity(&MSPoints);
    insertNetWorth(&MSPoints);

    var product: f64 = 1;
    for (MSPoints.items) |p, idx| {
        const unscaled = p.equity / p.netWorth;
        if (idx == 0) {
            MSPoints.items[idx].index = unscaled;
            continue;
        }
        product *= unscaled;
        const exponent: f64 = 1 / (@intToFloat(f64, idx));
        const geo_mean = std.math.pow(f64, product, exponent);
        MSPoints.items[idx].index = unscaled / geo_mean;
    }

    const file = try std.fs.cwd().createFile("static/json/max.json", .{ .read = true });
    defer file.close();
    try std.json.stringify(MSPoints.items, .{}, file.writer());
}
