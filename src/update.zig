const std = @import("std");
const Allocator = std.mem.Allocator;

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
        try writer.print("\n\n{s}\nEquity:{d}\nNetWorth:{d}\nIndex:{d}", .{
            p.date,
            p.equity,
            p.netWorth,
            p.index,
        });
    }
};

const fredRequest = struct {
    seriesID: []const u8,
    observationStart: []const u8,
    frequency: []const u8,
};

fn getFredSeries(alloc: Allocator, params: fredRequest) ![]u8 {
    const apiKey = std.posix.getenv("FRED_KEY").?;
    const url = try std.fmt.allocPrint(
        alloc,
        "https://api.stlouisfed.org/fred/series/observations?series_id={s}&api_key={s}&file_type=json&observation_start={s}&frequency={s}&units=lin",
        .{
            params.seriesID,
            apiKey,
            params.observationStart,
            params.frequency,
        },
    );
    defer alloc.free(url);

    const output = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "curl",
            url,
        },
        .max_output_bytes = 200 * 1024,
    });
    return output.stdout;
}

//Since quarterly reports use the first date of the quarter,
//on a time axis it needs to be the start of the next quarter.
fn advanceMonth(date: []const u8, change: u32) [10]u8 {
    var month = std.fmt.parseUnsigned(u32, date[5..7], 10) catch unreachable;
    var year = std.fmt.parseUnsigned(u32, date[0..4], 10) catch unreachable;

    month = (month + change) % 12;
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

fn appendPreFed(MSPoints: *std.ArrayList(MSPoint), json: []const u8) !void {
    const T = struct {
        year: [4]u8,
        netWorthAtCurrentPrices: f64,
        stockMarketAtCurrentPrices: f64,
    };
    var preFedTree = try std.json.parseFromSlice([]T, MSPoints.allocator, json, .{});
    defer preFedTree.deinit();

    var fullDate: [10]u8 = undefined;
    for (preFedTree.value) |v| {
        const year = v.year;
        const equity = v.stockMarketAtCurrentPrices;
        const netWorth = v.netWorthAtCurrentPrices;

        _ = try std.fmt.bufPrint(&fullDate, "{s}-01-01", .{year});

        try MSPoints.append(.{
            .date = fullDate,
            .equity = equity,
            .netWorth = netWorth,
        });
    }
}

fn writeRecentGraph(
    MSPoints: *std.ArrayList(MSPoint),
    name: []const u8,
    numYears: u32,
) !void {
    var points = std.ArrayList(MSPoint).init(MSPoints.allocator);
    defer points.deinit();
    const currentYearStr = MSPoints.getLast().date[0..4];
    const currentYear = try std.fmt.parseUnsigned(u32, currentYearStr, 10);
    for (MSPoints.items) |p| {
        const year = try std.fmt.parseUnsigned(u32, p.date[0..4], 10);
        if (year < currentYear - numYears) {
            continue;
        }
        try points.append(p);
    }
    const fileName = try std.fmt.allocPrint(
        MSPoints.allocator,
        "static/json/{s}.json",
        .{name},
    );
    defer MSPoints.allocator.free(fileName);

    const file = try std.fs.cwd().createFile(
        fileName,
        .{ .read = true },
    );
    defer file.close();
    try std.json.stringify(points.items, .{}, file.writer());
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var MSPoints = std.ArrayList(MSPoint).init(allocator);
    defer MSPoints.deinit();

    const preFedJson = @embedFile("./preFed.json");
    std.debug.assert(try std.json.validate(allocator, preFedJson));
    try appendPreFed(&MSPoints, preFedJson);

    const equityJson = try getFredSeries(allocator, .{
        .seriesID = "NCBCEL",
        .observationStart = "1952-01-01",
        .frequency = "q",
    });
    const netWorthJson = try getFredSeries(allocator, .{
        .seriesID = "TNWMVBSNNCB",
        .observationStart = "1952-01-01",
        .frequency = "q",
    });
    std.debug.assert(try std.json.validate(allocator, equityJson));
    std.debug.assert(try std.json.validate(allocator, netWorthJson));

    var equity_tree = try std.json.parseFromSlice(std.json.Value, allocator, equityJson, .{});
    defer equity_tree.deinit();
    const items = equity_tree.value.object.get("observations").?.array.items;
    for (items) |value| {
        const date_str = value.object.get("date").?.string;
        const equity_str = value.object.get("value").?.string;
        const equity_float = std.fmt.parseFloat(f64, equity_str) catch {
            continue;
        };
        try MSPoints.append(.{
            .date = advanceMonth(date_str, 3),
            .equity = equity_float,
        });
    }

    var net_worth_tree = try std.json.parseFromSlice(std.json.Value, allocator, netWorthJson, .{});
    defer net_worth_tree.deinit();
    const nw_items = net_worth_tree.value.object.get("observations").?.array.items;
    var i: usize = 0;
    for (nw_items) |value| {
        const date_str = value.object.get("date").?.string;
        const updated_date = advanceMonth(date_str, 3);
        while (!std.mem.eql(u8, &updated_date, &MSPoints.items[i].date)) {
            i += 1;
        }
        const net_worth_str = value.object.get("value").?.string;
        const net_worth_float = std.fmt.parseFloat(f64, net_worth_str) catch {
            continue;
        };
        MSPoints.items[i].netWorth = net_worth_float;
    }

    const lastQuarterPoint = MSPoints.getLast();
    const sp500Json = try getFredSeries(allocator, .{
        .seriesID = "SP500",
        .observationStart = &advanceMonth(&lastQuarterPoint.date, 1),
        .frequency = "m",
    });
    std.debug.assert(try std.json.validate(allocator, sp500Json));
    var sp_tree = try std.json.parseFromSlice(std.json.Value, allocator, sp500Json, .{});
    defer sp_tree.deinit();
    const sp_items = sp_tree.value.object.get("observations").?.array.items;
    for (sp_items) |value| {
        const date_str = value.object.get("date").?.string;
        const equity_str = value.object.get("value").?.string;
        const equity_float = std.fmt.parseFloat(f64, equity_str) catch {
            continue;
        };
        try MSPoints.append(.{
            .date = date_str[0..10].*,
            .equity = equity_float * 10,
            .netWorth = lastQuarterPoint.netWorth,
        });
    }

    const lastDay = try getFredSeries(allocator, .{
        .seriesID = "SP500",
        .observationStart = &advanceMonth(&lastQuarterPoint.date, 1),
        .frequency = "d",
    });
    std.debug.assert(try std.json.validate(allocator, lastDay));

    var last_tree = try std.json.parseFromSlice(std.json.Value, allocator, lastDay, .{});
    defer last_tree.deinit();
    const last_items = last_tree.value.object.get("observations").?.array.items;
    var last_point: MSPoint = undefined;
    for (last_items) |value| {
        const date_str = value.object.get("date").?.string;
        const equity_str = value.object.get("value").?.string;
        const equity_float = std.fmt.parseFloat(f64, equity_str) catch {
            continue;
        };
        last_point = .{
            .date = date_str[0..10].*,
            .equity = equity_float * 10,
            .netWorth = lastQuarterPoint.netWorth,
        };
    }
    try MSPoints.append(last_point);

    var product: f64 = 1;
    for (MSPoints.items, 0..) |p, idx| {
        const unscaled = p.equity / p.netWorth;
        product *= unscaled;

        const exponent: f32 = 1 / @as(f32, @floatFromInt(idx + 1));
        const geo_mean = std.math.pow(f64, product, exponent);
        MSPoints.items[idx].index = unscaled / geo_mean;
    }

    var max = std.ArrayList(MSPoint).init(allocator);
    defer max.deinit();
    for (MSPoints.items) |p| {
        if (std.mem.eql(u8, p.date[5..7], "01")) {
            try max.append(p);
        }
    }
    try max.append(MSPoints.getLast());
    _ = std.fs.cwd().makeDir("static/json") catch {};
    const file = try std.fs.cwd().createFile(
        "static/json/max.json",
        .{ .read = true },
    );
    defer file.close();
    try std.json.stringify(max.items, .{}, file.writer());

    try writeRecentGraph(&MSPoints, "tenYear", 10);
    try writeRecentGraph(&MSPoints, "fiveYear", 5);
    try writeRecentGraph(&MSPoints, "oneYear", 1);
}
