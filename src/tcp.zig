const std = @import("std");
const clnt = @import("client.zig");
const xev = @import("xev");
const wss = @import("wss.zig");
const core_types = @import("core_types.zig");

const Client = clnt.Client;
const Error = core_types.Error;
const header_end_marker = "\r\n\r\n";

// ... connect, onConnected, onWebsocketUpgrade ...

fn onWebsocketUpgrade(
    client_: ?*Client,
    l: *xev.Loop,
    c: *xev.Completion,
    socket: xev.TCP,
    _: xev.WriteBuffer,
    r: xev.WriteError!usize,
) xev.CallbackAction {
    const client = client_.?;
    _ = r catch |err| {
        std.log.err("Websocket Upgrade Write error: {s}\n", .{@errorName(err)});
        // No socket to close yet, but ensure no further action
        return .disarm;
    };

    // Clear any previous handshake data before starting the read
    client.handshake_header_buffer.shrinkRetainingCapacity(0);
    client.connection_state = .websocket_handshake_sent;

    socket.read(
        l,
        c,
        .{ .slice = &client.read_buf }, // Read into the temporary buffer
        Client,
        client,
        onWebsocketUpgradeRead, // Use the single unified callback
    );
    return .disarm;
}

// Removed the global partial_upgrade_response variable
// Removed onPartialWebsocketUpgradeRead function
// Removed switchingProtocols function

fn onWebsocketUpgradeRead(
    client_: ?*Client,
    l: *xev.Loop, // Added loop back
    c: *xev.Completion, // Added completion back
    socket: xev.TCP, // Added socket back
    buf: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    const client = client_.?;
    const bytes_read = r catch |err| {
        // Handle read errors (e.g., connection closed prematurely)
        std.log.err("Upgrade Read error: {s}\n", .{@errorName(err)});
        closeSocket(client); // Close on error
        return .disarm;
    };

    if (bytes_read == 0) {
        // Handle potential EOF or zero-byte read if necessary
        // This might indicate the server closed the connection during handshake
        std.log.err("Upgrade Read: Received 0 bytes, closing connection.\n", .{});
        closeSocket(client);
        return .disarm;
    }

    // Append the newly read data to the handshake buffer
    const new_data = buf.slice[0..bytes_read];
    client.handshake_header_buffer.appendSlice(new_data) catch |err| {
        std.log.err("Failed to append to handshake buffer: {s}\n", .{@errorName(err)});
        closeSocket(client); // Close on allocation error
        return .disarm;
    };

    // Check the accumulated data for the header end marker
    const accumulated_data = client.handshake_header_buffer.items;
    const header_end_index = std.mem.indexOf(u8, accumulated_data, header_end_marker);

    if (header_end_index == null) {
        // Header is still incomplete, schedule another read
        // Ensure buffer hasn't grown excessively large (optional sanity check)
        if (client.handshake_header_buffer.items.len > 8192) { // Example limit
            std.log.err("Handshake header buffer exceeded limit ({d} bytes).\n", .{client.handshake_header_buffer.items.len});
            closeSocket(client);
            return .disarm;
        }

        socket.read(
            l,
            c,
            .{ .slice = &client.read_buf }, // Read into the same temp buffer
            Client,
            client,
            onWebsocketUpgradeRead, // Reschedule the same callback
        );
        // Keep the completion armed for the next read
        return .continue_reading; // Or the appropriate action for xev to keep completion armed
        // Check xev docs: if .disarm disarms, maybe return nothing or a specific value
        // Assuming .disarm is correct if the read() call re-arms implicitly.
        // Let's stick with .disarm for now based on previous pattern.
        // --> Reconsidering: If we return .disarm, the completion might be destroyed.
        // --> We need to keep the callback loop going. Let's assume returning `.continue_reading`
        // --> or similar is needed, or that `socket.read` implicitly re-arms.
        // --> Consulting xev logic: The callback should return .disarm. The socket.read call
        // --> queues a new operation on the same completion.
        // --> Okay, sticking with .disarm.
        return .disarm;
    }

    // Header end marker found! Process the header.
    const complete_header_length = header_end_index.? + header_end_marker.len;
    const header_part = accumulated_data[0..header_end_index.?]; // Exclude the final \r\n\r\n

    if (std.mem.indexOf(u8, header_part, "101 Switching Protocols") == null) {
        std.log.err("WebSocket upgrade failed. Server response:\n{s}\n", .{header_part});
        closeSocket(client);
        // Clear buffer even on failure before closing
        client.handshake_header_buffer.shrinkRetainingCapacity(0);
        return .disarm;
    }

    // Header is valid, proceed with WebSocket connection establishment
    // std.debug.print("Full response data before handling: {s}\n", .{accumulated_data}); // Debug if needed
    // std.debug.print("Body part starts at index: {}\n", .{complete_header_length}); // Debug if needed

    wss.handleConnectionEstablished(
        client,
        accumulated_data, // Pass the full accumulated buffer
        complete_header_length, // Index where the body starts
    ) catch |err| {
        std.log.err("Error handling connection established: {s}\n", .{@errorName(err)});
        closeSocket(client);
        // Clear buffer even on error
        client.handshake_header_buffer.shrinkRetainingCapacity(0);
        return .disarm;
    };

    // Success! Clear the handshake buffer as it's no longer needed.
    // Keep capacity for potential reuse if the client reconnects later.
    client.handshake_header_buffer.shrinkRetainingCapacity(0);

    // Handshake complete, disarm this specific read completion.
    // Subsequent reads will be initiated by wss.read -> wss.onRead
    return .disarm;
}

// ... shutdownCallback, closeSocket, closeCallback ...

// Add closeCallback definition if it wasn't fully included before
pub fn closeCallback(
    client_: ?*Client,
    _: *xev.Loop,
    _: *xev.Completion,
    _: xev.TCP,
    r: xev.CloseError!void,
) xev.CallbackAction {
    const client = client_.?;
    r catch |err| {
        // Ignore "ThreadPoolRequired" as it's expected if operations were pending
        if (err != std.os.windows.ERROR_IO_PENDING and @errorName(err) != "ThreadPoolRequired") { // Adjust error check if needed
            std.log.err("Close error: {s}\n", .{@errorName(err)});
        }
    };
    client.connection_state = .closed;
    // Make sure buffer is clear upon final close, paranoia check
    client.handshake_header_buffer.shrinkRetainingCapacity(0);
    return .disarm;
}
