const std = @import("std");
const gremlin = @import("gremlin");

// structs
const WsMessageWire = struct {
    const ORDERBOOK_WIRE: gremlin.ProtoWireNumber = 1;
};

pub const WsMessage = struct {
    // fields
    orderbook: ?Orderbook = null,

    pub fn calcProtobufSize(self: *const WsMessage) usize {
        var res: usize = 0;
        if (self.orderbook) |v| {
            const size = v.calcProtobufSize();
            res += gremlin.sizes.sizeWireNumber(WsMessageWire.ORDERBOOK_WIRE) + gremlin.sizes.sizeUsize(size) + size;
        }
        return res;
    }

    pub fn encode(self: *const WsMessage, allocator: std.mem.Allocator) gremlin.Error![]const u8 {
        const size = self.calcProtobufSize();
        if (size == 0) {
            return &[_]u8{};
        }
        const buf = try allocator.alloc(u8, self.calcProtobufSize());
        var writer = gremlin.Writer.init(buf);
        self.encodeTo(&writer);
        return buf;
    }


    pub fn encodeTo(self: *const WsMessage, target: *gremlin.Writer) void {
        if (self.orderbook) |v| {
            const size = v.calcProtobufSize();
            target.appendBytesTag(WsMessageWire.ORDERBOOK_WIRE, size);
            v.encodeTo(target);
        }
    }
};

pub const WsMessageReader = struct {
    _orderbook_buf: ?[]const u8 = null,

    pub fn init(_: std.mem.Allocator, src: []const u8) gremlin.Error!WsMessageReader {
        var buf = gremlin.Reader.init(src);
        var res = WsMessageReader{};
        if (buf.buf.len == 0) {
            return res;
        }
        var offset: usize = 0;
        while (buf.hasNext(offset, 0)) {
            const tag = try buf.readTagAt(offset);
            offset += tag.size;
            switch (tag.number) {
                WsMessageWire.ORDERBOOK_WIRE => {
                  const result = try buf.readBytes(offset);
                  offset += result.size;
                  res._orderbook_buf = result.value;
                },
                else => {
                    offset = try buf.skipData(offset, tag.wire);
                }
            }
        }
        return res;
    }
    pub fn deinit(_: *const WsMessageReader) void { }
    
    pub fn getOrderbook(self: *const WsMessageReader, allocator: std.mem.Allocator) gremlin.Error!OrderbookReader {
        if (self._orderbook_buf) |buf| {
            return try OrderbookReader.init(allocator, buf);
        }
        return try OrderbookReader.init(allocator, &[_]u8{});
    }
};

const LevelWire = struct {
    const PRICE_WIRE: gremlin.ProtoWireNumber = 1;
    const QUANTITY_WIRE: gremlin.ProtoWireNumber = 2;
};

pub const Level = struct {
    // fields
    price: f64 = 0.0,
    quantity: f64 = 0.0,

    pub fn calcProtobufSize(self: *const Level) usize {
        var res: usize = 0;
        if (self.price != 0.0) { res += gremlin.sizes.sizeWireNumber(LevelWire.PRICE_WIRE) + gremlin.sizes.sizeDouble(self.price); }
        if (self.quantity != 0.0) { res += gremlin.sizes.sizeWireNumber(LevelWire.QUANTITY_WIRE) + gremlin.sizes.sizeDouble(self.quantity); }
        return res;
    }

    pub fn encode(self: *const Level, allocator: std.mem.Allocator) gremlin.Error![]const u8 {
        const size = self.calcProtobufSize();
        if (size == 0) {
            return &[_]u8{};
        }
        const buf = try allocator.alloc(u8, self.calcProtobufSize());
        var writer = gremlin.Writer.init(buf);
        self.encodeTo(&writer);
        return buf;
    }


    pub fn encodeTo(self: *const Level, target: *gremlin.Writer) void {
        if (self.price != 0.0) { target.appendFloat64(LevelWire.PRICE_WIRE, self.price); }
        if (self.quantity != 0.0) { target.appendFloat64(LevelWire.QUANTITY_WIRE, self.quantity); }
    }
};

pub const LevelReader = struct {
    _price: f64 = 0.0,
    _quantity: f64 = 0.0,

    pub fn init(_: std.mem.Allocator, src: []const u8) gremlin.Error!LevelReader {
        var buf = gremlin.Reader.init(src);
        var res = LevelReader{};
        if (buf.buf.len == 0) {
            return res;
        }
        var offset: usize = 0;
        while (buf.hasNext(offset, 0)) {
            const tag = try buf.readTagAt(offset);
            offset += tag.size;
            switch (tag.number) {
                LevelWire.PRICE_WIRE => {
                  const result = try buf.readFloat64(offset);
                  offset += result.size;
                  res._price = result.value;
                },
                LevelWire.QUANTITY_WIRE => {
                  const result = try buf.readFloat64(offset);
                  offset += result.size;
                  res._quantity = result.value;
                },
                else => {
                    offset = try buf.skipData(offset, tag.wire);
                }
            }
        }
        return res;
    }
    pub fn deinit(_: *const LevelReader) void { }
    
    pub inline fn getPrice(self: *const LevelReader) f64 { return self._price; }
    pub inline fn getQuantity(self: *const LevelReader) f64 { return self._quantity; }
};

const OrderbookWire = struct {
    const BIDS_WIRE: gremlin.ProtoWireNumber = 1;
    const ASKS_WIRE: gremlin.ProtoWireNumber = 2;
    const MAX_DEPTH_WIRE: gremlin.ProtoWireNumber = 3;
    const EXCHANGE_WIRE: gremlin.ProtoWireNumber = 4;
    const TICKER_WIRE: gremlin.ProtoWireNumber = 5;
};

pub const Orderbook = struct {
    // fields
    bids: ?[]const ?Level = null,
    asks: ?[]const ?Level = null,
    max_depth: u32 = 0,
    exchange: ?[]const u8 = null,
    ticker: ?[]const u8 = null,

    pub fn calcProtobufSize(self: *const Orderbook) usize {
        var res: usize = 0;
        if (self.bids) |arr| {
            for (arr) |maybe_v| {
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.BIDS_WIRE);
                if (maybe_v) |v| {
                    const size = v.calcProtobufSize();
                    res += gremlin.sizes.sizeUsize(size) + size;
                } else {
                    res += gremlin.sizes.sizeUsize(0);
                }
            }
        }
        if (self.asks) |arr| {
            for (arr) |maybe_v| {
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.ASKS_WIRE);
                if (maybe_v) |v| {
                    const size = v.calcProtobufSize();
                    res += gremlin.sizes.sizeUsize(size) + size;
                } else {
                    res += gremlin.sizes.sizeUsize(0);
                }
            }
        }
        if (self.max_depth != 0) { res += gremlin.sizes.sizeWireNumber(OrderbookWire.MAX_DEPTH_WIRE) + gremlin.sizes.sizeU32(self.max_depth); }
        if (self.exchange) |v| { res += gremlin.sizes.sizeWireNumber(OrderbookWire.EXCHANGE_WIRE) + gremlin.sizes.sizeUsize(v.len) + v.len; }
        if (self.ticker) |v| { res += gremlin.sizes.sizeWireNumber(OrderbookWire.TICKER_WIRE) + gremlin.sizes.sizeUsize(v.len) + v.len; }
        return res;
    }

    pub fn encode(self: *const Orderbook, allocator: std.mem.Allocator) gremlin.Error![]const u8 {
        const size = self.calcProtobufSize();
        if (size == 0) {
            return &[_]u8{};
        }
        const buf = try allocator.alloc(u8, self.calcProtobufSize());
        var writer = gremlin.Writer.init(buf);
        self.encodeTo(&writer);
        return buf;
    }


    pub fn encodeTo(self: *const Orderbook, target: *gremlin.Writer) void {
        if (self.bids) |arr| {
            for (arr) |maybe_v| {
                if (maybe_v) |v| {
                    const size = v.calcProtobufSize();
                    target.appendBytesTag(OrderbookWire.BIDS_WIRE, size);
                    v.encodeTo(target);
                } else {
                    target.appendBytesTag(OrderbookWire.BIDS_WIRE, 0);
                }
            }
        }
        if (self.asks) |arr| {
            for (arr) |maybe_v| {
                if (maybe_v) |v| {
                    const size = v.calcProtobufSize();
                    target.appendBytesTag(OrderbookWire.ASKS_WIRE, size);
                    v.encodeTo(target);
                } else {
                    target.appendBytesTag(OrderbookWire.ASKS_WIRE, 0);
                }
            }
        }
        if (self.max_depth != 0) { target.appendUint32(OrderbookWire.MAX_DEPTH_WIRE, self.max_depth); }
        if (self.exchange) |v| { target.appendBytes(OrderbookWire.EXCHANGE_WIRE, v); }
        if (self.ticker) |v| { target.appendBytes(OrderbookWire.TICKER_WIRE, v); }
    }
};

pub const OrderbookReader = struct {
    allocator: std.mem.Allocator,
    buf: gremlin.Reader,
    _bids_bufs: ?std.ArrayList([]const u8) = null,
    _asks_bufs: ?std.ArrayList([]const u8) = null,
    _max_depth: u32 = 0,
    _exchange: ?[]const u8 = null,
    _ticker: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) gremlin.Error!OrderbookReader {
        var buf = gremlin.Reader.init(src);
        var res = OrderbookReader{.allocator = allocator, .buf = buf};
        if (buf.buf.len == 0) {
            return res;
        }
        var offset: usize = 0;
        while (buf.hasNext(offset, 0)) {
            const tag = try buf.readTagAt(offset);
            offset += tag.size;
            switch (tag.number) {
                OrderbookWire.BIDS_WIRE => {
                    const result = try buf.readBytes(offset);
                    offset += result.size;
                    if (res._bids_bufs == null) {
                        res._bids_bufs = std.ArrayList([]const u8).init(allocator);
                    }
                    try res._bids_bufs.?.append(result.value);
                },
                OrderbookWire.ASKS_WIRE => {
                    const result = try buf.readBytes(offset);
                    offset += result.size;
                    if (res._asks_bufs == null) {
                        res._asks_bufs = std.ArrayList([]const u8).init(allocator);
                    }
                    try res._asks_bufs.?.append(result.value);
                },
                OrderbookWire.MAX_DEPTH_WIRE => {
                  const result = try buf.readUInt32(offset);
                  offset += result.size;
                  res._max_depth = result.value;
                },
                OrderbookWire.EXCHANGE_WIRE => {
                  const result = try buf.readBytes(offset);
                  offset += result.size;
                  res._exchange = result.value;
                },
                OrderbookWire.TICKER_WIRE => {
                  const result = try buf.readBytes(offset);
                  offset += result.size;
                  res._ticker = result.value;
                },
                else => {
                    offset = try buf.skipData(offset, tag.wire);
                }
            }
        }
        return res;
    }
    pub fn deinit(self: *const OrderbookReader) void {
        if (self._bids_bufs) |arr| {
            arr.deinit();
        }
        if (self._asks_bufs) |arr| {
            arr.deinit();
        }
    }
    pub fn getBids(self: *const OrderbookReader, allocator: std.mem.Allocator) gremlin.Error![]LevelReader {
        if (self._bids_bufs) |bufs| {
            var result = try std.ArrayList(LevelReader).initCapacity(allocator, bufs.items.len);
            for (bufs.items) |buf| {
                try result.append(try LevelReader.init(allocator, buf));
            }
            return result.toOwnedSlice();
        }
        return &[_]LevelReader{};
    }
    pub fn getAsks(self: *const OrderbookReader, allocator: std.mem.Allocator) gremlin.Error![]LevelReader {
        if (self._asks_bufs) |bufs| {
            var result = try std.ArrayList(LevelReader).initCapacity(allocator, bufs.items.len);
            for (bufs.items) |buf| {
                try result.append(try LevelReader.init(allocator, buf));
            }
            return result.toOwnedSlice();
        }
        return &[_]LevelReader{};
    }
    pub inline fn getMaxDepth(self: *const OrderbookReader) u32 { return self._max_depth; }
    pub inline fn getExchange(self: *const OrderbookReader) []const u8 { return self._exchange orelse &[_]u8{}; }
    pub inline fn getTicker(self: *const OrderbookReader) []const u8 { return self._ticker orelse &[_]u8{}; }
};

