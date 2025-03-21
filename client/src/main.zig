const std = @import("std");
const app = @import("visualization/app.zig");

const App = app.App;
pub fn main() !void {
    // Start the app immediately without waiting for processing to complete
    App.init(800, 500, "Market Visualization");
}

// pub fn main() !void {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const allocator = gpa.allocator();

//     const pairs = [_][]const u8{
//         "EURUSD", "GBPUSD", "USDJPY", "AUDUSD",
//         "USDCHF", "NZDUSD", "XAUUSD",
//     };

//     const stdout = std.io.getStdOut().writer();
//     try stdout.print("Forex Pattern Analysis\n", .{});
//     try stdout.print("===================\n\n", .{});

//     // var chart_gen = ChartGenerator.init(allocator);

//     for (pairs) |pair| {
//         const filepath = try std.fmt.allocPrint(
//             allocator,
//             "src/market/data/{s}_Candlestick_1_D_BID_06.06.2017-15.06.2024.csv",
//             .{pair},
//         );
//         defer allocator.free(filepath);

//         try stdout.print("Processing {s}...\n", .{pair});
//         var provider = try CsvDataProvider.init(allocator, filepath);
//         defer provider.deinit();

//         var long_count: usize = 0;
//         var short_count: usize = 0;

//         const MAX_CANDLES = 20;
//         var data: [MAX_CANDLES]Candlestick = undefined;
//         var data_len: usize = 0;

//         while (try provider.next()) |candle| {
//             if (data_len < MAX_CANDLES) {
//                 data[MAX_CANDLES - 1 - data_len] = candle;
//                 data_len += 1;
//             } else {
//                 var i: usize = MAX_CANDLES - 1;
//                 while (i > 0) : (i -= 1) {
//                     data[i] = data[i - 1];
//                 }
//                 data[0] = candle;
//             }
//             const signal_result = PatternAnalyzer.analyzePattern(&data, data_len);
//             switch (signal_result) {
//                 .long => long_count += 1,
//                 .short => short_count += 1,
//                 .none => {},
//             }
//         }

//         // Generate chart
//         const title = try std.fmt.allocPrint(allocator, "{s} Price Chart", .{pair});
//         defer allocator.free(title);

//         const output_path = try std.fmt.allocPrint(
//             allocator,
//             "charts/{s}_chart.svg",
//             .{pair},
//         );
//         defer allocator.free(output_path);

//         // try chart_gen.generateChart(&data, title, output_path);

//         try stdout.print("  Found {d} long signals and {d} short signals\n", .{ long_count, short_count });
//     }
// }
