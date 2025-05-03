const std = @import("std");
const xev = @import("xev");
const frm = @import("frame.zig");
const rb = @import("read_buffer.zig");
const validation = @import("validation.zig");
const cb = @import("callback.zig");

const TCP = xev.TCP;
const Loop = xev.Loop;
const Completion = xev.Completion;
const frameHeader = frm.frameHeader;
const validateMessageCallbacks = validation.validateMessageCallbacks;
const ReadBuffers = rb.ReadBuffers;
const Callbacks = cb.Callbacks;

pub const ClientOptions = struct {
    server_addr: std.net.Address,
    keep_alive: bool = false,
};

pub fn Client(
    comptime MessageCallbacksUnion: type,
) type {
    comptime validateMessageCallbacks(MessageCallbacksUnion);

    const ReadBuffersType = ReadBuffers(MessageCallbacksUnion);

    return struct {
        options: ClientOptions,

        socket: TCP,
        loop: *Loop,
        connect_completion: Completion = undefined,
        write_completion: Completion = undefined,
        read_completion: Completion = undefined,

        read_buffers: ReadBuffersType = undefined,
        callback_context: *anyopaque = undefined,
        callbacks: Callbacks(MessageCallbacksUnion) = undefined,

        const Self = @This();

        pub fn init(
            loop: *Loop,
            options: ClientOptions,
            comptime cbs: Callbacks(MessageCallbacksUnion),
            callback_context: *anyopaque,
        ) !Self {
            var initialized_buffers: ReadBuffersType = undefined;
            inline for (@typeInfo(ReadBuffersType).@"struct".fields) |field_info| {
                @field(initialized_buffers, field_info.name) = undefined;
            }
            // var initialized_callbacks: Callbacks(MessageCallbacksUnion) = undefined;
            // inline for (@typeInfo(Callbacks(MessageCallbacksUnion)).@"struct".fields) |field_info| {
            //     @field(initialized_callbacks, field_info.name) = undefined;
            // }
            return Self{
                .loop = loop,
                .socket = try TCP.init(options.server_addr),
                .options = options,
                .read_buffers = initialized_buffers,
                .callback_context = callback_context,
                .callbacks = cbs,
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

            self.callbacks.orderbook(self.callback_context, buf.slice) catch unreachable;
            self.socket.read(l, c, .{ .slice = &self.read_buffers.orderbook }, Self, self, readCallback);

            return .disarm;
        }
    };
}
