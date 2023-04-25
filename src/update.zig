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

const FredIterator = struct {
    tree: std.json.ValueTree = undefined,
    parser: std.json.Parser,
    index: usize = 0,

    const ValuePair = struct {
        date: [10]u8,
        value: f64,
    };

    fn init(alloc: Allocator) !FredIterator {
        var parser = std.json.Parser.init(alloc, false);
        return FredIterator{
            .parser = parser,
        };
    }

    fn parse(self: *FredIterator, json: []const u8) !void {
        self.index = 0;
        self.parser.reset();
        self.tree = try self.parser.parse(json);
    }

    fn deinit(self: *FredIterator) void {
        self.tree.deinit();
        self.parser.deinit();
    }

    pub fn next(self: *FredIterator) ?ValuePair {
        const observations = self.tree.root.Object.get("observations").?;
        const arrayItems = observations.Array.items;
        for (arrayItems[self.index..]) |value| {
            self.index += 1;
            const dateStr = value.Object.get("date").?.String;
            const valueStr = value.Object.get("value").?.String;
            const valueFloat = std.fmt.parseFloat(f64, valueStr) catch {
                continue;
            };
            return ValuePair{
                .date = dateStr[0..10].*,
                .value = valueFloat,
            };
        }

        return null;
    }
};

const fredRequest = struct {
    seriesID: []const u8,
    observationStart: []const u8,
    frequency: []const u8,
};

fn getFredSeries(alloc: Allocator, params: fredRequest) ![]u8 {
    const apiKey = std.os.getenv("FRED_KEY").?;
    const url = try std.fmt.allocPrint(
        alloc,
        "https://api.stlouisfed.org/fred/series/observations?series_id={s}&api_key={s}&file_type=json&observation_start={s}&frequency={s}",
        .{
            params.seriesID,
            apiKey,
            params.observationStart,
            params.frequency,
        },
    );
    defer alloc.free(url);

    const output = try std.ChildProcess.exec(.{
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
    var parser = std.json.Parser.init(MSPoints.allocator, false);
    defer parser.deinit();

    var preFedTree = try parser.parse(json);
    defer preFedTree.deinit();

    var fullDate: [10]u8 = undefined;
    for (preFedTree.root.Array.items) |v| {
        const year = v.Object.get("year").?.String;
        const equityStr = v.Object.get("stockMarketAtCurrentPrices").?.String;
        const netWorthStr = v.Object.get("netWorthAtCurrentPrices").?.String;

        _ = try std.fmt.bufPrint(&fullDate, "{s}-01-01", .{year});
        const equity = try std.fmt.parseFloat(f64, equityStr);
        const netWorth = try std.fmt.parseFloat(f64, netWorthStr);

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
        var year = try std.fmt.parseUnsigned(u32, p.date[0..4], 10);
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
    const preFedJson = @embedFile("./preFed.json");
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
    std.debug.assert(std.json.validate(preFedJson));
    std.debug.assert(std.json.validate(equityJson));
    std.debug.assert(std.json.validate(netWorthJson));

    var MSPoints = std.ArrayList(MSPoint).init(allocator);
    defer MSPoints.deinit();

    try appendPreFed(&MSPoints, preFedJson);

    var iter = try FredIterator.init(allocator);
    defer iter.deinit();
    try iter.parse(equityJson);
    while (iter.next()) |v| {
        try MSPoints.append(.{
            .date = advanceMonth(&v.date, 3),
            .equity = v.value,
        });
    }

    try iter.parse(netWorthJson);
    var i: usize = 0;
    while (iter.next()) |v| {
        const updatedDate = advanceMonth(&v.date, 3);
        while (!std.mem.eql(u8, &updatedDate, &MSPoints.items[i].date)) {
            i += 1;
        }
        MSPoints.items[i].netWorth = v.value;
    }

    const lastPoint = MSPoints.getLast();
    const sp500Json = try getFredSeries(allocator, .{
        .seriesID = "SP500",
        .observationStart = &advanceMonth(&lastPoint.date, 1),
        .frequency = "m",
    });
    std.debug.assert(std.json.validate(sp500Json));

    try iter.parse(sp500Json);
    while (iter.next()) |v| {
        try MSPoints.append(.{
            .date = v.date,
            .equity = v.value * 10,
            .netWorth = lastPoint.netWorth,
        });
    }

    const lastDay = try getFredSeries(allocator, .{
        .seriesID = "SP500",
        .observationStart = &advanceMonth(&lastPoint.date, 1),
        .frequency = "d",
    });
    std.debug.assert(std.json.validate(lastDay));

    try iter.parse(lastDay);
    while (iter.next()) |v| {
        if (iter.next() == null) {
            try MSPoints.append(.{
                .date = v.date,
                .equity = v.value * 10,
                .netWorth = lastPoint.netWorth,
            });
        }
    }

    var product: f64 = 1;
    for (MSPoints.items, 0..) |p, idx| {
        const unscaled = p.equity / p.netWorth;
        product *= unscaled;
        const exponent: f32 = 1 / @intToFloat(f32, idx + 1);
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
