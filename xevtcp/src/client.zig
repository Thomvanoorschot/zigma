const std = @import("std");
const xev = @import("xev");
const rb = @import("read_buffer.zig");
const validation = @import("validation.zig");
const cb = @import("callback.zig");
const frm = @import("frame.zig");

const TCP = xev.TCP;
const Loop = xev.Loop;
const Completion = xev.Completion;
const validateMessageCallbacks = validation.validateMessageCallbacks;
const ReadBuffers = rb.ReadBuffers;
const Callbacks = cb.Callbacks;
const Frame = frm.Frame;
const FrameHeader = frm.FrameHeader;
pub const ClientOptions = struct {
    server_addr: std.net.Address,
    keep_alive: bool = false,
};

pub fn Client(
    comptime MessageCallbacksUnion: type,
) type {
    comptime validateMessageCallbacks(MessageCallbacksUnion);

    const ReadBuffersType = ReadBuffers(MessageCallbacksUnion);
    const CallbacksType = Callbacks(MessageCallbacksUnion);
    return struct {
        allocator: std.mem.Allocator,
        options: ClientOptions,

        socket: TCP,
        loop: *Loop,
        connect_completion: Completion = undefined,
        write_completion: Completion = undefined,
        read_completion: Completion = undefined,

        // TODO: For now this works since we only have a single thread and sequential reads
        frame_header_buf: FrameHeader = undefined,
        read_buffers: ReadBuffersType = undefined,
        callback_context: *anyopaque = undefined,
        callbacks: CallbacksType = undefined,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            loop: *Loop,
            options: ClientOptions,
            comptime cbs: CallbacksType,
            callback_context: *anyopaque,
        ) !Self {
            var initialized_buffers: ReadBuffersType = undefined;
            inline for (@typeInfo(ReadBuffersType).@"struct".fields) |field_info| {
                @field(initialized_buffers, field_info.name) = Frame{
                    .payload = undefined,
                };
            }

            return Self{
                .allocator = allocator,
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

            self.socket.write(
                l,
                c,
                .{ .slice = "Connection: keep-alive\r\nstart" },
                Self,
                self,
                writeCallback,
            );
            return .disarm;
        }

        pub fn startReading(self: *Self) void {
            self.socket.read(
                self.loop,
                &self.read_completion,
                .{ .slice = &self.frame_header_buf.header_bytes },
                Self,
                self,
                readHeaderCallback,
            );
        }

        fn writeCallback(
            _: ?*Self,
            _: *xev.Loop,
            _: *xev.Completion,
            _: TCP,
            _: xev.WriteBuffer,
            r: xev.WriteError!usize,
        ) xev.CallbackAction {
            _ = r catch |err| {
                std.debug.print("Callback error: {s}\n", .{@errorName(err)});
                return .disarm;
            };
            std.debug.print("Wrote to server\n", .{});

            return .disarm;
        }

        fn readHeaderCallback(
            self_: ?*Self,
            l: *xev.Loop,
            c: *xev.Completion,
            _: TCP,
            _: xev.ReadBuffer,
            r: xev.ReadError!usize,
        ) xev.CallbackAction {
            const self = self_.?;
            _ = r catch unreachable;

            if (self.read_buffers.orderbook.payload.len > 0) {
                self.allocator.free(self.read_buffers.orderbook.payload);
                self.read_buffers.orderbook.payload = &.{};
            }
            self.read_buffers.orderbook.payload = self.allocator.alloc(
                u8,
                @intCast(self.frame_header_buf.payloadLength()),
            ) catch unreachable;
            self.socket.read(
                l,
                c,
                .{ .slice = self.read_buffers.orderbook.payload },
                Self,
                self,
                readPayloadCallback,
            );
            return .disarm;
        }

        fn readPayloadCallback(
            self_: ?*Self,
            l: *xev.Loop,
            c: *xev.Completion,
            _: TCP,
            _: xev.ReadBuffer,
            r: xev.ReadError!usize,
        ) xev.CallbackAction {
            const self = self_.?;
            _ = r catch unreachable;
            self.callbacks.orderbook(self.callback_context, self.read_buffers.orderbook.payload) catch unreachable;
            self.socket.read(
                l,
                c,
                .{ .slice = &self.frame_header_buf.header_bytes },
                Self,
                self,
                readHeaderCallback,
            );

            return .disarm;
        }
    };
}
