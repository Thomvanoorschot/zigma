const std = @import("std");
const shared_models = @import("shared_models");
const websocket = @import("zignite").websocket;
const Orderbook = shared_models.Orderbook;
const OHLCList = shared_models.OHLCList;

pub const SharedData = struct {
    orderbooks: std.StringHashMap(Orderbook),
    ohlc_windows: std.StringHashMap(OHLCList),
};
