const std = @import("std");

const MSPoint = struct {
    date: [10]u8,
    equity: ?f64,
    netWorth: ?f64,
};

fn appendPreFED(
    array: *std.ArrayList(MSPoint),
    comptime file: []const u8
) void {
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
    var path = std.fmt.allocPrint(alloc, "/fred/series/observations?series_id={s}&api_key=89f2a06210de32e0ea49e2aa9106543a&file_type=json&observation_start=1952-01-01", .{series_id}) catch unreachable;
    var httpClient = std.http.Client{.allocator = alloc };
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
        },
        .{},
        .{}
    ) catch unreachable;
    defer req.deinit();

    var buffer = [_]u8{0} ** 50000;
    const numBytesRead = req.readAll(&buffer) catch unreachable;
    std.debug.assert(std.json.validate(buffer[0..numBytesRead]));
    return buffer[0..numBytesRead];
}

//Since quarterly reports use the first date of the quarter,
//on a time axis it needs to be the start of the next quarter.
fn correctDate(date: []const u8) [10]u8 {
    var month = std.fmt.parseUnsigned(u32, date[5..7], 10)
        catch unreachable;
    month = (month + 3) % 12;
    var buf: [10]u8 = undefined;
    const updated_date = std.fmt.bufPrint(&buf, "{s}{:0>2}{s}", .{
        date[0..5],
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
            .netWorth = null,
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

    appendPreFED(&MSPoints, "./static/json/1900-45-nw-market.json");
    appendEquity(&MSPoints);
    insertNetWorth(&MSPoints);
    std.debug.print("{any}\n", .{MSPoints.items});

}
