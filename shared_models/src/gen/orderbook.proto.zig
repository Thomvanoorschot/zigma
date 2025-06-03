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

const OrderbookWire = struct {
    const BIDS_WIRE: gremlin.ProtoWireNumber = 1;
    const ASKS_WIRE: gremlin.ProtoWireNumber = 2;
    const MAX_DEPTH_WIRE: gremlin.ProtoWireNumber = 3;
    const EXCHANGE_WIRE: gremlin.ProtoWireNumber = 4;
    const TICKER_WIRE: gremlin.ProtoWireNumber = 5;
};

pub const Orderbook = struct {
    // fields
    bids: ?[]const f64 = null,
    asks: ?[]const f64 = null,
    max_depth: u32 = 0,
    exchange: ?[]const u8 = null,
    ticker: ?[]const u8 = null,

    pub fn calcProtobufSize(self: *const Orderbook) usize {
        var res: usize = 0;
        if (self.bids) |arr| {
            if (arr.len == 0) {
            } else if (arr.len == 1) {
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.BIDS_WIRE) + gremlin.sizes.sizeDouble(arr[0]);
            } else {
                var packed_size: usize = 0;
                for (arr) |v| {
                    packed_size += gremlin.sizes.sizeDouble(v);
                }
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.BIDS_WIRE) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
            }
        }
        if (self.asks) |arr| {
            if (arr.len == 0) {
            } else if (arr.len == 1) {
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.ASKS_WIRE) + gremlin.sizes.sizeDouble(arr[0]);
            } else {
                var packed_size: usize = 0;
                for (arr) |v| {
                    packed_size += gremlin.sizes.sizeDouble(v);
                }
                res += gremlin.sizes.sizeWireNumber(OrderbookWire.ASKS_WIRE) + gremlin.sizes.sizeUsize(packed_size) + packed_size;
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
            if (arr.len == 0) {
            } else if (arr.len == 1) {
                target.appendFloat64(OrderbookWire.BIDS_WIRE, arr[0]);
            } else {
                var packed_size: usize = 0;
                for (arr) |v| {
                    packed_size += gremlin.sizes.sizeDouble(v);
                }
                target.appendBytesTag(OrderbookWire.BIDS_WIRE, packed_size);
                for (arr) |v| {
                    target.appendFloat64WithoutTag(v);
                }
            }
        }
        if (self.asks) |arr| {
            if (arr.len == 0) {
            } else if (arr.len == 1) {
                target.appendFloat64(OrderbookWire.ASKS_WIRE, arr[0]);
            } else {
                var packed_size: usize = 0;
                for (arr) |v| {
                    packed_size += gremlin.sizes.sizeDouble(v);
                }
                target.appendBytesTag(OrderbookWire.ASKS_WIRE, packed_size);
                for (arr) |v| {
                    target.appendFloat64WithoutTag(v);
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
    _bids_offsets: ?std.ArrayList(usize) = null,
    _bids_wires: ?std.ArrayList(gremlin.ProtoWireType) = null,
    _asks_offsets: ?std.ArrayList(usize) = null,
    _asks_wires: ?std.ArrayList(gremlin.ProtoWireType) = null,
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
                    if (res._bids_offsets == null) {
                        res._bids_offsets = std.ArrayList(usize).init(allocator);
                        res._bids_wires = std.ArrayList(gremlin.ProtoWireType).init(allocator);
                    }
                    try res._bids_offsets.?.append(offset);
                    try res._bids_wires.?.append(tag.wire);
                    if (tag.wire == gremlin.ProtoWireType.bytes) {
                        const length_result = try buf.readVarInt(offset);
                        offset += length_result.size + length_result.value;
                    } else {
                        const result = try buf.readFloat64(offset);
                        offset += result.size;
                    }
                },
                OrderbookWire.ASKS_WIRE => {
                    if (res._asks_offsets == null) {
                        res._asks_offsets = std.ArrayList(usize).init(allocator);
                        res._asks_wires = std.ArrayList(gremlin.ProtoWireType).init(allocator);
                    }
                    try res._asks_offsets.?.append(offset);
                    try res._asks_wires.?.append(tag.wire);
                    if (tag.wire == gremlin.ProtoWireType.bytes) {
                        const length_result = try buf.readVarInt(offset);
                        offset += length_result.size + length_result.value;
                    } else {
                        const result = try buf.readFloat64(offset);
                        offset += result.size;
                    }
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
        if (self._bids_offsets) |arr| {
            arr.deinit();
        }
        if (self._bids_wires) |arr| {
            arr.deinit();
        }
        if (self._asks_offsets) |arr| {
            arr.deinit();
        }
        if (self._asks_wires) |arr| {
            arr.deinit();
        }
    }
    pub fn getBids(self: *const OrderbookReader, allocator: std.mem.Allocator) gremlin.Error![]f64 {
        if (self._bids_offsets) |offsets| {
            if (offsets.items.len == 0) return &[_]f64{};
    
            var result = std.ArrayList(f64).init(allocator);
            errdefer result.deinit();
    
            for (offsets.items, self._bids_wires.?.items) |start_offset, wire_type| {
                if (wire_type == .bytes) {
                    const length_result = try self.buf.readVarInt(start_offset);
                    var offset = start_offset + length_result.size;
                    const end_offset = offset + length_result.value;
    
                    while (offset < end_offset) {
                        const value_result = try self.buf.readFloat64(offset);
                        try result.append(value_result.value);
                        offset += value_result.size;
                    }
                } else {
                    const value_result = try self.buf.readFloat64(start_offset);
                    try result.append(value_result.value);
                }
            }
            return result.toOwnedSlice();
        }
        return &[_]f64{};
    }
    pub fn getAsks(self: *const OrderbookReader, allocator: std.mem.Allocator) gremlin.Error![]f64 {
        if (self._asks_offsets) |offsets| {
            if (offsets.items.len == 0) return &[_]f64{};
    
            var result = std.ArrayList(f64).init(allocator);
            errdefer result.deinit();
    
            for (offsets.items, self._asks_wires.?.items) |start_offset, wire_type| {
                if (wire_type == .bytes) {
                    const length_result = try self.buf.readVarInt(start_offset);
                    var offset = start_offset + length_result.size;
                    const end_offset = offset + length_result.value;
    
                    while (offset < end_offset) {
                        const value_result = try self.buf.readFloat64(offset);
                        try result.append(value_result.value);
                        offset += value_result.size;
                    }
                } else {
                    const value_result = try self.buf.readFloat64(start_offset);
                    try result.append(value_result.value);
                }
            }
            return result.toOwnedSlice();
        }
        return &[_]f64{};
    }
    pub inline fn getMaxDepth(self: *const OrderbookReader) u32 { return self._max_depth; }
    pub inline fn getExchange(self: *const OrderbookReader) []const u8 { return self._exchange orelse &[_]u8{}; }
    pub inline fn getTicker(self: *const OrderbookReader) []const u8 { return self._ticker orelse &[_]u8{}; }
};

