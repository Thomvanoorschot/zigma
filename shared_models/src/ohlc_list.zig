// const std = @import("std");
// const zbor = @import("zbor");
// const zbor_build = zbor.build;
// const zborParse = zbor.parse;
// const zborStringify = zbor.stringify;
// const DataItem = zbor.DataItem;
// pub const OHLCList = std.ArrayList(OHLC);

// pub fn stringifyOHLCList(
//     allocator: std.mem.Allocator,
//     list: OHLCList,
// ) !std.ArrayList(u8) {
//     var str = std.ArrayList(u8).init(allocator);

//     try zborStringify(list.items, .{
//         .ignore_override = true,
//     }, str.writer());
//     return str;
// }

// pub fn parseOHLCList(
//     allocator: std.mem.Allocator,
//     str: []const u8,
// ) ![]OHLC {
//     const di = try DataItem.new(str);
//     const ob = try zborParse([]OHLC, di, .{ .allocator = allocator });
//     return ob;
// }

// pub const OHLC = struct {
//     symbol: []const u8,
//     open: f32,
//     high: f32,
//     low: f32,
//     close: f32,
//     trades: u64,
//     volume: f32,
//     interval: u64,
//     timestamp: []const u8,

//     // Add a dupe function for deep copying
//     pub fn dupe(self: OHLC, allocator: std.mem.Allocator) !OHLC {
//         // Duplicate the slices
//         const symbol_copy = try allocator.dupe(u8, self.symbol);
//         errdefer allocator.free(symbol_copy); // Free symbol if timestamp fails
//         const timestamp_copy = try allocator.dupe(u8, self.timestamp);

//         // Return the new struct with copied data
//         return OHLC{
//             .symbol = symbol_copy,
//             .open = self.open,
//             .high = self.high,
//             .low = self.low,
//             .close = self.close,
//             .trades = self.trades,
//             .volume = self.volume,
//             .interval = self.interval,
//             .timestamp = timestamp_copy,
//         };
//     }

//     // Add a corresponding deinit if needed (to free symbol/timestamp)
//     pub fn deinit(self: *OHLC, allocator: std.mem.Allocator) void {
//         allocator.free(self.symbol);
//         allocator.free(self.timestamp);
//         // No need to free self.* unless allocated with create()
//     }
// };
