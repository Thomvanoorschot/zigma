const std = @import("std");
const zignite = @import("zignite");
const shared_models = @import("shared_models");

const shared_data = @import("shared_data.zig");
const OrderbookWindows = @import("../visualization/orderbook.zig").OrderbookWindows;

const websocket_web_worker = zignite.websocket_web_worker;
pub const SharedData = shared_data.SharedData;
pub const WebSocketWebWorker = websocket_web_worker.WebSocketWebWorker;

pub fn workerEntrypoint(web_worker: *WebSocketWebWorker(SharedData)) !void {
    _ = web_worker;
}

pub fn onOpenCallback(web_worker: *WebSocketWebWorker(SharedData)) !bool {
    try web_worker.std_out.print("WebSocket opened\n", .{});
    if (web_worker.open_socket) |open_socket| {
        web_worker.shared_data.orderbook_windows = try OrderbookWindows.init(web_worker.allocator, open_socket);
    }
    return true;
}

pub fn onMessageCallback(web_worker: *WebSocketWebWorker(SharedData), message: []const u8) !bool {
    const ws_message = shared_models.WsMessage.decode(message, web_worker.allocator) catch |err| {
        try web_worker.std_out.print("Failed {any}\n", .{err});
        return true;
    };
    if (ws_message.message) |msg| {
        switch (msg) {
            .orderbook => |orderbook| {
                try web_worker.shared_data.orderbook_windows.updateOrderbook(orderbook);
            },
            else => {
                return error.UnknownMessageType;
            },
        }
    }
    return true;
}

pub fn onErrorCallback(web_worker: *WebSocketWebWorker(SharedData)) !bool {
    _ = web_worker;
    return true;
}

pub fn onCloseCallback(web_worker: *WebSocketWebWorker(SharedData), code: u16, reason: []const u8) !bool {
    _ = web_worker;
    _ = code;
    _ = reason;
    return true;
}
