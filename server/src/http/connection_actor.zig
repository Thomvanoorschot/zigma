// const std = @import("std");
// const backstage = @import("backstage");
// const async_zocket = @import("async_zocket");
// const type_utils = @import("../utils/type_utils.zig");

// const xev = backstage.xev;
// const Context = backstage.Context;
// const Envelope = backstage.Envelope;
// const ActorInterface = backstage.ActorInterface;
// const ClientConnection = async_zocket.ClientConnection;
// const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

// // @generate-proxy
// pub const ConnectionActor = struct {
//     allocator: std.mem.Allocator,
//     ctx: *Context = undefined,
//     client_conn: *ClientConnection = undefined,

//     const Self = @This();
//     pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
//         const self = try allocator.create(Self);
//         errdefer allocator.destroy(self);

//         self.* = .{
//             .ctx = ctx,
//             .allocator = allocator,
//         };
//         return self;
//     }

//     pub fn setup(self: *Self, client_conn: *ClientConnection) void {
//         self.client_conn = client_conn;
//         self.client_conn.setCloseCallback(@ptrCast(self), closeCallback);
//         self.client_conn.setReadCallback(@ptrCast(self), readCallback);
//         self.client_conn.read();
//     }

//     pub fn deinit(self: *Self) !void {
//         try self.ctx.poisonPill();
//     }

//     pub fn orderbookUpdated(self: *Self, orderbook: Orderbook) !void {
//         const str = try ServerMessage.encode(ServerMessage{
//             .message = .{ .orderbook = orderbook },
//         }, self.allocator);
//         defer self.allocator.free(str);
//         try self.write(str);
//     }

//     pub fn ohlcUpdated(self: *Self, ohlc: OHLCActorMessage) !void {
//         const str = try ServerMessage.encode(ServerMessage{
//             .message = .{ .ohlc = ohlc },
//         }, self.allocator);
//         defer self.allocator.free(str);
//         try self.write(str);
//     }

//     fn readCallback(
//         self_: ?*anyopaque,
//         payload: []const u8,
//     ) !void {
//         const self = unsafeAnyOpaqueCast(Self, self_);

//         const client_msg: ClientMessage = try ClientMessage.decode(payload, self.allocator);
//         if (client_msg.message == null) {
//             return error.InvalidMessage;
//         }
//         switch (client_msg.message.?) {
//             .subscribe => |m| {
//                 var actor_id_buf: [40]u8 = undefined;

//                 const actor_id = switch (m.subscription_type) {
//                     .ORDERBOOK => blk: {
//                         break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_orderbook_actor", .{m.ticker.Owned.str});
//                     },
//                     .OHLC => blk: {
//                         break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_ohlc_actor", .{m.ticker.Owned.str});
//                     },
//                     else => unreachable,
//                 };
//                 try self.ctx.subscribeToActor(actor_id);
//             },
//             .unsubscribe => |m| {
//                 var actor_id_buf: [40]u8 = undefined;
//                 const actor_id = switch (m.subscription_type) {
//                     .ORDERBOOK => blk: {
//                         break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_orderbook_actor", .{m.ticker.Owned.str});
//                     },
//                     .OHLC => blk: {
//                         break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_ohlc_actor", .{m.ticker.Owned.str});
//                     },
//                     else => unreachable,
//                 };
//                 try self.ctx.unsubscribeFromActor(actor_id);
//             },
//         }
//     }

//     pub fn write(self: *Self, buf: []const u8) !void {
//         try self.client_conn.write(.binary, buf);
//     }

//     fn closeCallback(
//         self_: ?*anyopaque,
//     ) !void {
//         const self = unsafeAnyOpaqueCast(Self, self_);

//         try self.deinit();
//     }
// };
