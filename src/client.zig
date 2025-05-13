const std = @import("std");
const xev = @import("xev");
const tcp = @import("tcp.zig");
const wss = @import("wss.zig");
const core_types = @import("core_types.zig");

// ... other consts ...

const ClientConfig = struct {
    // ... existing fields ...
};

pub const Client = struct {
    loop: *xev.Loop,
    socket: xev.TCP,
    allocator: std.mem.Allocator,
    config: ClientConfig,
    address: std.net.Address,

    connect_completion: xev.Completion = undefined,
    read_completion: xev.Completion = undefined,
    close_completion: xev.Completion = undefined,
    ping_completion: xev.Completion = undefined,

    connection_state: ConnectionState = .initial,
    read_buf: [1024]u8 = undefined, // Used for individual socket reads

    delayed_write_index: usize = 0,
    delayed_writes: [1028]*DelayedWrite = undefined,
    write_queue: xev.WriteQueue,
    queued_write_pool: std.heap.MemoryPool(QueuedWrite),

    callback_context: *anyopaque,
    read_callback: *const fn (
        context: *anyopaque,
        payload: []const u8,
    ) anyerror!void,

    receive_buffer: std.ArrayList(u8), // For application message reassembly
    fragment_buffer: std.ArrayList(u8), // For websocket fragment reassembly
    handshake_header_buffer: std.ArrayList(u8), // Buffer for HTTP upgrade header

    pub fn init(
        allocator: std.mem.Allocator,
        loop: *xev.Loop,
        config: ClientConfig,
        comptime read_callback: *const fn (
            context: *anyopaque,
            payload: []const u8,
        ) anyerror!void,
        callback_context: *anyopaque,
    ) !Client {
        const receive_buffer = std.ArrayList(u8).init(allocator);
        const fragment_buffer = std.ArrayList(u8).init(allocator);
        const handshake_header_buffer = std.ArrayList(u8).init(allocator); // Init the new buffer
        const address = try std.net.Address.parseIp4(config.host, config.port);
        return .{
            .allocator = allocator,
            .loop = loop,
            .address = address,
            .socket = try xev.TCP.init(address),
            .config = config,
            .receive_buffer = receive_buffer,
            .fragment_buffer = fragment_buffer,
            .handshake_header_buffer = handshake_header_buffer, // Assign it

            .read_callback = read_callback,
            .callback_context = callback_context,

            .write_queue = xev.WriteQueue{},
            .queued_write_pool = std.heap.MemoryPool(QueuedWrite).init(allocator),
        };
    }

    pub fn deinit(client: *Client) void {
        if (client.connection_state != .closed and client.connection_state != .closing) {
            // Attempt graceful close if not already closing/closed
            // Note: This might need adjustment based on xev's close guarantees
            client.socket.close(client.loop, &client.close_completion, Client, client, tcp.closeCallback);
        }
        client.receive_buffer.deinit();
        client.fragment_buffer.deinit();
        client.handshake_header_buffer.deinit(); // Deinit the new buffer
        client.queued_write_pool.deinit();
        // Consider freeing delayed_writes if they were allocated
    }

    // ... rest of Client methods (connect, read, write) ...
};
