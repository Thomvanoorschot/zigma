const pb = @import("protobuf");
const ws_message = @import("ws_message.pb.zig");

pub const ManagedString = pb.ManagedString;

pub const WsMessage = ws_message.WsMessage;

const ob = @import("orderbook.pb.zig");
pub const Orderbook = ob.Orderbook;
pub const Level = ob.Level;

const ohlc = @import("ohlc.pb.zig");
pub const OHLC = ohlc.OHLC;
pub const OHLCList = ohlc.OHLCList;
