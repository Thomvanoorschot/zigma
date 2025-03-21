const std = @import("std");

pub const WsSubsribeRequest = struct {
    method: []const u8,
    params: struct {
        channel: []const u8,
        symbol: []const []const u8,
    },
};

const WsResponseMessageType = enum { snapshot, update };

pub const WsResponseMessage = union(WsResponseMessageType) {
    snapshot: UpdateMessage,
    update: UpdateMessage,
};

pub const PriceLevel = struct {
    price: f64,
    qty: f64,
};

pub const UpdateData = struct {
    symbol: []const u8,
    bids: []const PriceLevel,
    asks: []const PriceLevel,
    checksum: u64,
    timestamp: ?[]const u8 = null,
};

pub const UpdateMessage = struct {
    channel: []const u8,
    type: []const u8,
    data: []const UpdateData,
};

pub fn parseOrderbookMessage(json_str: []const u8, allocator: std.mem.Allocator) !?WsResponseMessage {
    var raw_json = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
    defer raw_json.deinit();

    const raw_value = raw_json.value;
    const channel_str = if (raw_value.object.get("channel")) |c| c.string else "";
    if (!std.mem.eql(u8, channel_str, "book")) {
        return null;
    }
    const type_str = if (raw_value.object.get("type")) |t| t.string else "";

    const message_type: WsResponseMessageType = std.meta.stringToEnum(WsResponseMessageType, type_str) orelse
        return null;

    return switch (message_type) {
        .snapshot => {
            const snapshot_json = try std.json.parseFromValue(UpdateMessage, allocator, raw_value, .{});
            return .{ .snapshot = snapshot_json.value };
        },
        .update => {
            const update_json = try std.json.parseFromValue(UpdateMessage, allocator, raw_value, .{});
            return .{ .update = update_json.value };
        },
    };
}
