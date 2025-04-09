const std = @import("std");

pub const WsSubsribeRequest = struct {
    method: []const u8,
    params: struct {
        channel: []const u8,
        symbol: []const []const u8,
    },
};

const WsResponseMessageType = enum { orderbook, ohlc };

pub const WsResponseMessage = union(WsResponseMessageType) {
    orderbook: WsOrderbookResponseMessage,
    ohlc: WsOHLCResponseMessage,
};

const WsOrderbookResponseMessageType = enum { snapshot, update };
const WsOrderbookResponseMessage = union(WsOrderbookResponseMessageType) {
    snapshot: OrderbookUpdateMessage,
    update: OrderbookUpdateMessage,
};

const WsOHLCResponseMessageType = enum { snapshot, update };
const WsOHLCResponseMessage = union(WsOHLCResponseMessageType) {
    snapshot: OHLCUpdateMessage,
    update: OHLCUpdateMessage,
};
pub const PriceLevel = struct {
    price: f64,
    qty: f64,
};

pub const OrderbookUpdateData = struct {
    symbol: []const u8,
    bids: []const PriceLevel,
    asks: []const PriceLevel,
    checksum: u64,
    timestamp: ?[]const u8 = null,
};

pub const OrderbookUpdateMessage = struct {
    channel: []const u8,
    type: []const u8,
    data: []const OrderbookUpdateData,
};

pub const OHLCUpdateMessage = struct {
    channel: []const u8,
    type: []const u8,
    timestamp: []const u8,
    data: []const OHLCUpdateData,
};
pub const OHLCUpdateData = struct {
    symbol: []const u8,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    trades: u64,
    volume: f64,
    vwap: f64,
    interval_begin: []const u8,
    interval: u64,
    timestamp: []const u8,
};

pub fn parseMessage(allocator: std.mem.Allocator, json_str: []const u8) !?WsResponseMessage {
    var raw_json = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer raw_json.deinit();

    const raw_value = raw_json.value;
    const channel_str = if (raw_value.object.get("channel")) |c| c.string else "";
    if (std.mem.eql(u8, channel_str, "book")) {
        return parseOrderbookUpdate(allocator, raw_value);
    } else if (std.mem.eql(u8, channel_str, "ohlc")) {
        return parseOHLCUpdate(allocator, raw_value);
    }
    return null;
}

fn parseOrderbookUpdate(allocator: std.mem.Allocator, raw_value: std.json.Value) !?WsResponseMessage {
    const type_str = if (raw_value.object.get("type")) |t| t.string else "";

    const message_type: WsOrderbookResponseMessageType = std.meta.stringToEnum(WsOrderbookResponseMessageType, type_str) orelse
        return null;

    return switch (message_type) {
        .snapshot => {
            const snapshot_json = try std.json.parseFromValue(OrderbookUpdateMessage, allocator, raw_value, .{});
            return .{ .orderbook = .{ .snapshot = snapshot_json.value } };
        },
        .update => {
            const update_json = try std.json.parseFromValue(OrderbookUpdateMessage, allocator, raw_value, .{});
            return .{ .orderbook = .{ .update = update_json.value } };
        },
    };
}

fn parseOHLCUpdate(allocator: std.mem.Allocator, raw_value: std.json.Value) !?WsResponseMessage {
    const type_str = if (raw_value.object.get("type")) |t| t.string else "";
    const message_type: WsOHLCResponseMessageType = std.meta.stringToEnum(WsOHLCResponseMessageType, type_str) orelse
        return null;
    return switch (message_type) {
        .snapshot => {
            const snapshot_json = try std.json.parseFromValue(OHLCUpdateMessage, allocator, raw_value, .{});
            return .{ .ohlc = .{ .snapshot = snapshot_json.value } };
        },
        .update => {
            const update_json = try std.json.parseFromValue(OHLCUpdateMessage, allocator, raw_value, .{});
            return .{ .ohlc = .{ .update = update_json.value } };
        },
    };
}
