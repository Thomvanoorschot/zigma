const pb = @import("protobuf");

// Protobuf utilities
pub const ManagedString = pb.ManagedString;

// WebSocket messages
const ws_message = @import("ws_message.pb.zig");
pub const ServerMessage = ws_message.ServerMessage;
pub const ClientMessage = ws_message.ClientMessage;

// Orderbook types
const orderbook = @import("orderbook.pb.zig");
pub const Orderbook = orderbook.Orderbook;
pub const OrderbookUpdate = orderbook.OrderbookUpdate;
pub const OrderbookLevel = orderbook.OrderbookLevel;
pub const OrderbookInitRequest = orderbook.OrderbookInitRequest;
pub const OrderbookStartRequest = orderbook.OrderbookStartRequest;

// OHLC types
const ohlc = @import("ohlc.pb.zig");
pub const OHLC = ohlc.OHLC;
pub const OHLCUpdate = ohlc.OHLCUpdate;
pub const OHLCList = ohlc.OHLCList;
pub const OHLCInitRequest = ohlc.OHLCInitRequest;
pub const OHLCStartRequest = ohlc.OHLCStartRequest;

// Broker types
const broker = @import("broker.pb.zig");
pub const BrokerType = broker.BrokerType;
pub const BrokerInitRequest = broker.BrokerInitRequest;
pub const BrokerSubscribeRequest = broker.BrokerSubscribeRequest;

// Actor message types
const actor_message = @import("actor_message.pb.zig");
pub const OrderbookActor = actor_message.OrderbookActor;
pub const BrokerActor = actor_message.BrokerActor;
pub const OHLCActor = actor_message.OHLCActor;
pub const ServerActor = actor_message.ServerActor;
pub const ConnectionActor = actor_message.ConnectionActor;

// Connection types
const connection = @import("connection.pb.zig");
pub const SubscribeRequest = connection.SubscribeRequest;
pub const UnsubscribeRequest = connection.UnsubscribeRequest;

// Server types
const server = @import("server.pb.zig");
pub const InitMessage = server.InitMessage;

// Misc types
const misc = @import("misc.pb.zig");
pub const Empty = misc.Empty;
