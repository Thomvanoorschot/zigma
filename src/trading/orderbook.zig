const std = @import("std");

pub const OrderType = enum {
    market,
    limit,
    stop,
    stop_limit,
};

pub const OrderSide = enum {
    buy,
    sell,
};

pub const OrderStatus = enum {
    pending,
    active,
    filled,
    partially_filled,
    canceled,
    rejected,
};

pub const Order = struct {
    id: u64,
    currency_pair: []const u8,
    price: f64,
    size: f64,
    side: OrderSide,
    type: OrderType,
    status: OrderStatus,
    timestamp: i64,

    pub fn init(
        id: u64,
        currency_pair: []const u8,
        price: f64,
        size: f64,
        side: OrderSide,
        order_type: OrderType,
    ) Order {
        return Order{
            .id = id,
            .currency_pair = currency_pair,
            .price = price,
            .size = size,
            .side = side,
            .type = order_type,
            .status = .pending,
            .timestamp = std.time.timestamp(),
        };
    }
};

pub const PriceLevel = struct {
    price: f64,
    total_size: f64,
    orders: std.ArrayList(Order),

    pub fn init(allocator: std.mem.Allocator, price: f64) PriceLevel {
        return PriceLevel{
            .price = price,
            .total_size = 0,
            .orders = std.ArrayList(Order).init(allocator),
        };
    }

    pub fn deinit(self: *PriceLevel) void {
        self.orders.deinit();
    }

    pub fn addOrder(self: *PriceLevel, order: Order) !void {
        try self.orders.append(order);
        self.total_size += order.size;
    }

    pub fn removeOrder(self: *PriceLevel, order_id: u64) ?Order {
        for (self.orders.items, 0..) |order, i| {
            if (order.id == order_id) {
                const removed_order = self.orders.orderedRemove(i);
                self.total_size -= removed_order.size;
                return removed_order;
            }
        }
        return null;
    }
};

pub const PriceLevelSummary = struct {
    price: f64,
    size: f64,
};

pub const OrderBook = struct {
    currency_pair: []const u8,
    bids: std.AutoHashMap(f64, PriceLevel),
    asks: std.AutoHashMap(f64, PriceLevel),
    allocator: std.mem.Allocator,
    next_order_id: u64,

    pub fn init(allocator: std.mem.Allocator, currency_pair: []const u8) OrderBook {
        return OrderBook{
            .currency_pair = currency_pair,
            .bids = std.AutoHashMap(f64, PriceLevel).init(allocator),
            .asks = std.AutoHashMap(f64, PriceLevel).init(allocator),
            .allocator = allocator,
            .next_order_id = 1,
        };
    }

    pub fn deinit(self: *OrderBook) void {
        var bid_it = self.bids.valueIterator();
        while (bid_it.next()) |price_level| {
            price_level.deinit();
        }
        self.bids.deinit();

        var ask_it = self.asks.valueIterator();
        while (ask_it.next()) |price_level| {
            price_level.deinit();
        }
        self.asks.deinit();
    }

    pub fn addOrder(self: *OrderBook, price: f64, size: f64, side: OrderSide, order_type: OrderType) !u64 {
        const order_id = self.next_order_id;
        self.next_order_id += 1;

        const order = Order.init(
            order_id,
            self.currency_pair,
            price,
            size,
            side,
            order_type,
        );

        const book = if (side == .buy) &self.bids else &self.asks;

        var price_level = if (book.getPtr(price)) |level| level else blk: {
            try book.put(price, PriceLevel.init(self.allocator, price));
            break :blk book.getPtr(price).?;
        };

        try price_level.addOrder(order);
        return order_id;
    }

    pub fn removeOrder(self: *OrderBook, order_id: u64, price: f64, side: OrderSide) ?Order {
        const book = if (side == .buy) &self.bids else &self.asks;

        if (book.getPtr(price)) |price_level| {
            return price_level.removeOrder(order_id);
        }

        return null;
    }

    pub fn getBestBid(self: *const OrderBook) ?f64 {
        var best_price: ?f64 = null;
        var it = self.bids.keyIterator();

        while (it.next()) |price| {
            if (best_price == null or price.* > best_price.?) {
                best_price = price.*;
            }
        }

        return best_price;
    }

    pub fn getBestAsk(self: *const OrderBook) ?f64 {
        var best_price: ?f64 = null;
        var it = self.asks.keyIterator();

        while (it.next()) |price| {
            if (best_price == null or price.* < best_price.?) {
                best_price = price.*;
            }
        }

        return best_price;
    }

    pub fn getSpread(self: *const OrderBook) ?f64 {
        const best_bid = self.getBestBid();
        const best_ask = self.getBestAsk();

        if (best_bid != null and best_ask != null) {
            return best_ask.? - best_bid.?;
        }

        return null;
    }

    pub fn getDepth(self: *const OrderBook, levels: usize) !struct { bids: []PriceLevelSummary, asks: []PriceLevelSummary } {
        var bid_levels = try self.allocator.alloc(PriceLevelSummary, @min(levels, self.bids.count()));
        var ask_levels = try self.allocator.alloc(PriceLevelSummary, @min(levels, self.asks.count()));

        var bid_prices = std.ArrayList(f64).init(self.allocator);
        defer bid_prices.deinit();

        var bid_it = self.bids.keyIterator();
        while (bid_it.next()) |price| {
            try bid_prices.append(price.*);
        }

        std.sort.pdq(f64, bid_prices.items, {}, struct {
            fn compare(_: void, a: f64, b: f64) bool {
                return a > b; // Sort in descending order for bids
            }
        }.compare);

        for (0..bid_levels.len) |i| {
            if (i >= bid_prices.items.len) break;
            const price = bid_prices.items[i];
            const level = self.bids.get(price).?;
            bid_levels[i] = .{ .price = price, .size = level.total_size };
        }

        var ask_prices = std.ArrayList(f64).init(self.allocator);
        defer ask_prices.deinit();

        var ask_it = self.asks.keyIterator();
        while (ask_it.next()) |price| {
            try ask_prices.append(price.*);
        }

        std.sort.pdq(f64, ask_prices.items, {}, struct {
            fn compare(_: void, a: f64, b: f64) bool {
                return a < b; // Sort in ascending order for asks
            }
        }.compare);

        for (0..ask_levels.len) |i| {
            if (i >= ask_prices.items.len) break;
            const price = ask_prices.items[i];
            const level = self.asks.get(price).?;
            ask_levels[i] = .{ .price = price, .size = level.total_size };
        }

        return .{ .bids = bid_levels, .asks = ask_levels };
    }
};

pub const MarketData = struct {
    currency_pair: []const u8,
    timestamp: i64,
    bid: f64,
    ask: f64,
    last_price: f64,
    volume_24h: f64,
    high_24h: f64,
    low_24h: f64,

    pub fn init(
        currency_pair: []const u8,
        bid: f64,
        ask: f64,
        last_price: f64,
        volume_24h: f64,
        high_24h: f64,
        low_24h: f64,
    ) MarketData {
        return MarketData{
            .currency_pair = currency_pair,
            .timestamp = std.time.timestamp(),
            .bid = bid,
            .ask = ask,
            .last_price = last_price,
            .volume_24h = volume_24h,
            .high_24h = high_24h,
            .low_24h = low_24h,
        };
    }
};
