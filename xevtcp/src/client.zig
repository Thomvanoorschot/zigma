const std = @import("std");
const xev = @import("xev");
const frm = @import("frame.zig");
const TCP = xev.TCP;
const Loop = xev.Loop;
const Completion = xev.Completion;
const frameHeader = frm.frameHeader;

pub const ClientOptions = struct {
    server_addr: std.net.Address,
    keep_alive: bool = false,
};

fn CallbackDispatchTable(comptime MsgType: type, comptime CbCtx: type) type {
    const union_info = @typeInfo(MsgType).@"union";
    var fields_array: [union_info.fields.len]std.builtin.Type.StructField = undefined;

    inline for (union_info.fields, 0..) |field, i| {
        const MessagePayloadType = @TypeOf(@field((@as(MsgType, undefined)), field.name)); // Get type of the union field
        const CallbackType = *const fn (*CbCtx, MessagePayloadType) anyerror!void;

        fields_array[i] = .{
            .name = field.name,
            .type = CallbackType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(CallbackType),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields_array,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn ReadBuffersStruct(comptime U: type) type {
    const union_fields = @typeInfo(U).@"union".fields;
    var fields_array: [union_fields.len]std.builtin.Type.StructField = undefined;

    inline for (union_fields, 0..) |field, i| {
        fields_array[i] = .{
            .name = field.name,
            .type = [20000]u8,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf([4096]u8),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields_array,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub fn Client(
    comptime MessageTypeUnion: type,
    comptime CallbackContext: type,
) type {
    const info = @typeInfo(MessageTypeUnion);
    comptime if (info != .@"union") {
        @compileError("MessageTypeUnion must be a union");
    };
    comptime if (info.@"union".tag_type == null) {
        @compileError("MessageTypeUnion must be a tagged union");
    };

    const CallbackDispatchTableType = CallbackDispatchTable(MessageTypeUnion, CallbackContext);
    const ReadBuffersType = ReadBuffersStruct(MessageTypeUnion);

    return struct {
        options: ClientOptions,

        socket: TCP,
        loop: *Loop,
        connect_completion: Completion = undefined,
        write_completion: Completion = undefined,
        read_completion: Completion = undefined,

        read_buffers: ReadBuffersType = undefined,
        callback_dispatch_table: CallbackDispatchTableType = undefined,
        callback_context: *CallbackContext = undefined,

        const Self = @This();

        pub fn init(
            loop: *Loop,
            options: ClientOptions,
            comptime callback_dispatch_table: CallbackDispatchTableType,
            callback_context: *CallbackContext,
        ) !Self {
            var initialized_buffers: ReadBuffersType = undefined;

            inline for (@typeInfo(ReadBuffersType).@"struct".fields) |field_info| {
                @field(initialized_buffers, field_info.name) = undefined;
            }
            return Self{
                .loop = loop,
                .socket = try TCP.init(options.server_addr),
                .options = options,
                .read_buffers = initialized_buffers,
                .callback_dispatch_table = callback_dispatch_table,
                .callback_context = callback_context,
            };
        }

        pub fn connect(self: *Self) void {
            self.socket.connect(
                self.loop,
                &self.connect_completion,
                self.options.server_addr,
                Self,
                self,
                connectCallback,
            );
        }

        pub fn write(self: *Self, data: []const u8) void {
            self.socket.write(
                self.loop,
                &self.write_completion,
                .{ .slice = data },
                Self,
                self,
                writeCallback,
            );
        }
        fn connectCallback(
            self_: ?*Self,
            l: *xev.Loop,
            c: *xev.Completion,
            _: TCP,
            r: xev.ConnectError!void,
        ) xev.CallbackAction {
            const self = self_.?;

            r catch |err| {
                std.debug.print("Callback error: {s}\n", .{@errorName(err)});
                return .disarm;
            };

            std.debug.print("Connected to server\n", .{});

            self.socket.write(l, c, .{ .slice = "Connection: keep-alive\r\nstart" }, Self, self, writeCallback);
            return .disarm;
        }

        fn startReading(self: *Self) void {
            self.socket.read(self.loop, &self.read_completion, .{ .slice = &self.read_buf }, Self, self, readCallback);
        }

        fn writeCallback(
            self_: ?*Self,
            l: *xev.Loop,
            _: *xev.Completion,
            _: TCP,
            _: xev.WriteBuffer,
            r: xev.WriteError!usize,
        ) xev.CallbackAction {
            const self = self_.?;
            _ = r catch |err| {
                std.debug.print("Callback error: {s}\n", .{@errorName(err)});
                return .disarm;
            };
            std.debug.print("Wrote to server\n", .{});

            self.socket.read(l, &self.read_completion, .{ .slice = &self.read_buffers.orderbook }, Self, self, readCallback);

            return .disarm;
        }

        // fn readCallback(
        //     self_: ?*Self,
        //     l: *xev.Loop,
        //     c: *xev.Completion,
        //     _: TCP,
        //     buf: xev.ReadBuffer,
        //     r: xev.ReadError!usize,
        // ) xev.CallbackAction {
        //     const self = self_.?;
        //     const n = r catch |err| {
        //         std.debug.print("Read error: {s}\n", .{@errorName(err)});
        //         return .disarm;
        //     };

        //     const received_data = buf.slice[0..n];
        //     const ohlc_list = parseOHLCList(self.allocator, received_data) catch unreachable;
        //     self.ohlc_list = ohlc_list;

        //     self.socket.read(l, c, .{ .slice = &self.read_buf }, Self, self, readCallback);
        //     return .disarm;
        // }

        fn readCallback(
            self_: ?*Self,
            l: *xev.Loop,
            c: *xev.Completion,
            _: TCP,
            buf: xev.ReadBuffer,
            r: xev.ReadError!usize,
        ) xev.CallbackAction {
            const self = self_.?;
            // // _ = l;
            // _ = c;
            // _ = buf;
            _ = r catch unreachable;

            // TODO: Read from the buffer, look at the frame header, and call the appropriate callback

            self.callback_dispatch_table.orderbook(self.callback_context, buf.slice) catch unreachable;
            self.socket.read(l, c, .{ .slice = &self.read_buffers.orderbook }, Self, self, readCallback);

            return .disarm;
        }
    };
}

// pub fn Client(comptime message_types: []type) type {
//     return struct {
//         allocator: std.mem.Allocator,
//         socket: TCP,
//         loop: Loop,
//         connect_completion: Completion = undefined,
//         write_completion: Completion = undefined,
//         read_completion: Completion = undefined,
//         options: ClientOptions,
//         message_types: []const type,
//         const Self = @This();
//         pub fn init(
//             allocator: std.mem.Allocator,
//             loop: Loop,
//             options: ClientOptions,
//             comptime message_types: []type,
//         ) !Client {
//             return Client{
//                 .allocator = allocator,
//                 .loop = loop,
//                 .socket = try TCP.init(options.server_addr),
//                 .options = options,
//                 .frame_types = message_types,
//             };
//         }

//         pub fn connect(self: *Client) void {
//             self.socket.connect(
//                 self.loop,
//                 &self.connect_completion,
//                 self.server_addr,
//                 Client,
//                 self,
//                 connectCallback,
//             );
//         }

//         pub fn write(self: *Client, data: []const u8) void {
//             self.socket.write(
//                 self.loop,
//                 &self.write_completion,
//                 .{ .slice = data },
//                 Client,
//                 self,
//                 writeCallback,
//             );
//         }
//         fn connectCallback(
//             self_: ?*Self,
//             l: *xev.Loop,
//             c: *xev.Completion,
//             _: TCP,
//             r: xev.ConnectError!void,
//         ) xev.CallbackAction {
//             const self = self_.?;

//             r catch |err| {
//                 std.debug.print("Callback error: {s}\n", .{@errorName(err)});
//                 return .disarm;
//             };

//             std.debug.print("Connected to server\n", .{});

//             self.socket.write(l, c, .{ .slice = "Connection: keep-alive\r\nstart" }, Self, self, writeCallback);
//             return .disarm;
//         }

//         fn writeCallback(
//             self_: ?*Self,
//             l: *xev.Loop,
//             _: *xev.Completion,
//             _: TCP,
//             _: xev.WriteBuffer,
//             r: xev.WriteError!usize,
//         ) xev.CallbackAction {
//             const self = self_.?;
//             _ = r catch |err| {
//                 std.debug.print("Callback error: {s}\n", .{@errorName(err)});
//                 return .disarm;
//             };
//             std.debug.print("Wrote to server\n", .{});

//             self.socket.read(l, &self.read_completion, .{ .slice = &self.read_buf }, Self, self, readCallback);

//             return .disarm;
//         }

//         // fn readCallback(
//         //     self_: ?*Self,
//         //     l: *xev.Loop,
//         //     c: *xev.Completion,
//         //     _: TCP,
//         //     buf: xev.ReadBuffer,
//         //     r: xev.ReadError!usize,
//         // ) xev.CallbackAction {
//         //     const self = self_.?;
//         //     const n = r catch |err| {
//         //         std.debug.print("Read error: {s}\n", .{@errorName(err)});
//         //         return .disarm;
//         //     };

//         //     const received_data = buf.slice[0..n];
//         //     const ohlc_list = parseOHLCList(self.allocator, received_data) catch unreachable;
//         //     self.ohlc_list = ohlc_list;

//         //     self.socket.read(l, c, .{ .slice = &self.read_buf }, Self, self, readCallback);
//         //     return .disarm;
//         // }

//         fn readCallback(
//             self_: ?*Self,
//             l: *xev.Loop,
//             c: *xev.Completion,
//             _: TCP,
//             buf: xev.ReadBuffer,
//             r: xev.ReadError!usize,
//         ) xev.CallbackAction {
//             const self = self_.?;
//             const n = r catch |err| {
//                 std.debug.print("Read error: {s}\n", .{@errorName(err)});
//                 return .disarm;
//             };
//             const received_data = buf.slice[0..n];
//             const ob = parseOrderbook(self.allocator, received_data) catch |err| {
//                 std.log.err("Failed to parse orderbook data: {s}", .{@errorName(err)});
//                 return .disarm;
//             };
//             self.orderbook = ob;
//             self.socket.read(l, c, .{ .slice = &self.read_buf }, Self, self, readCallback);
//             return .disarm;
//         }
//     };
// }
