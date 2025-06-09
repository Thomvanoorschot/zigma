const std = @import("std");
const shared_models = @import("shared_models");
const websocket = @import("zignite").websocket;
const Orderbook = shared_models.Orderbook;
// const OHLCWindows = ohlc.OHLCWindows;

pub const SharedData = struct {
    open_socket: ?websocket.WebSocket = null,
    orderbooks: std.StringHashMap(*Orderbook),
    // ohlc_windows: *OHLCWindows = undefined,
};
