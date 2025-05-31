const std = @import("std");
const ob = @import("../visualization/orderbook.zig");

const OrderbookWindows = ob.OrderbookWindows;

pub const SharedData = struct {
    orderbook_windows: *OrderbookWindows = undefined,
};
