const std = @import("std");
const xev = @import("xev");
const rb = @import("read_buffer.zig");
const cb = @import("callback.zig");
const frm = @import("frame.zig");

const TCP = xev.TCP;
const Loop = xev.Loop;
const Completion = xev.Completion;
const ReadBuffers = rb.ReadBuffers;
const Callbacks = cb.Callbacks;
const Frame = frm.Frame;
const FrameHeader = frm.FrameHeader;
pub const ClientOptions = struct {
    server_addr: std.net.Address,
    keep_alive: bool = false,
};

pub fn Client(
    comptime MessageTypes: type,
) type {
    const ReadBuffersType = ReadBuffers(MessageTypes);
    const CallbacksType = Callbacks(MessageTypes);
    return struct {
        allocator: std.mem.Allocator,
        options: ClientOptions,

        socket: TCP,
        loop: *Loop,
        connect_completion: Completion = undefined,
        write_completion: Completion = undefined,
        read_completion: Completion = undefined,

        // TODO: For now this works since we only have a single thread and sequential reads
        frame_header: FrameHeader = undefined,
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
                .{ .slice = &self.frame_header.header_bytes },
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

            const message_type: MessageTypes = @enumFromInt(self.frame_header.messageType());
            inline for (@typeInfo(MessageTypes).@"enum".fields) |field_info| {
                if (std.mem.eql(u8, @tagName(message_type), field_info.name)) {
                    var read_buffer = &@field(self.read_buffers, field_info.name);

                    if (read_buffer.payload.len > 0) {
                        self.allocator.free(read_buffer.payload);
                        read_buffer.payload = &.{};
                    }
                    read_buffer.payload = self.allocator.alloc(
                        u8,
                        @intCast(self.frame_header.payloadLength()),
                    ) catch unreachable;
                    self.socket.read(
                        l,
                        c,
                        .{ .slice = read_buffer.payload },
                        Self,
                        self,
                        readPayloadCallback,
                    );
                    return .disarm;
                }
            }
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

            const message_type: MessageTypes = @enumFromInt(self.frame_header.messageType());
            inline for (@typeInfo(MessageTypes).@"enum".fields) |field_info| {
                if (std.mem.eql(u8, @tagName(message_type), field_info.name)) {
                    const callback_fn = @field(self.callbacks, field_info.name);
                    const buffer_frame = @field(self.read_buffers, field_info.name);
                    callback_fn(self.callback_context, buffer_frame.payload) catch |err| {
                        std.log.err("Callback error for message type '{s}': {s}", .{ field_info.name, @errorName(err) });
                    };
                    break;
                } else {
                    std.log.err("readPayloadCallback: Unknown message type or enum issue for tag {any}\\n", .{self.frame_header.messageType()});
                }
            }
            self.socket.read(
                l,
                c,
                .{ .slice = &self.frame_header.header_bytes },
                Self,
                self,
                readHeaderCallback,
            );

            return .disarm;
        }
    };
}
