const std = @import("std");

pub const Envelope = struct {
    senderID: ?[]const u8,
    payload: []const u8,

    // Maximum reasonable sizes to prevent overflow and excessive memory usage
    const MAX_SENDER_ID_LEN: usize = 65535; // u16 max
    const MAX_PAYLOAD_LEN: usize = std.math.maxInt(u32) - 1024; // Leave some headroom
    const MAX_REMAINING_LEN: usize = std.math.maxInt(u32);

    pub fn init(senderID: ?[]const u8, payload: []const u8) Envelope {
        return Envelope{
            .senderID = senderID,
            .payload = payload,
        };
    }

    /// Serializes envelope to bytes. Caller must free the returned buffer.
    pub fn toBytes(self: *const Envelope, allocator: std.mem.Allocator) ![]u8 {
        const HeaderType = u32;
        const lenFieldSize = @sizeOf(HeaderType); // 4
        const idLenSize = @sizeOf(u16); // 2

        const senderIDLen: usize = if (self.senderID) |idSlice| idSlice.len else 0;
        const payloadLen: usize = self.payload.len;

        // Validate input sizes
        if (senderIDLen > MAX_SENDER_ID_LEN) {
            return error.SenderIDTooLarge;
        }
        if (payloadLen > MAX_PAYLOAD_LEN) {
            return error.PayloadTooLarge;
        }

        const remainingLen = idLenSize + senderIDLen + payloadLen;
        if (remainingLen > MAX_REMAINING_LEN) {
            return error.MessageTooLarge;
        }

        const totalSize = lenFieldSize + remainingLen;

        var buf: []u8 = try allocator.alloc(u8, totalSize);
        errdefer allocator.free(buf);

        var idx: usize = 0;

        // Write remaining length (safe cast after validation)
        std.mem.writeInt(HeaderType, @ptrCast(buf[idx .. idx + lenFieldSize]), @intCast(remainingLen), std.builtin.Endian.big);
        idx += lenFieldSize;

        // Write sender ID length (safe cast after validation)
        std.mem.writeInt(u16, @ptrCast(buf[idx .. idx + idLenSize]), @intCast(senderIDLen), std.builtin.Endian.big);
        idx += idLenSize;

        // Write sender ID if present
        if (self.senderID) |idSlice| {
            @memcpy(buf[idx .. idx + senderIDLen], idSlice);
            idx += senderIDLen;
        }

        // Write payload
        @memcpy(buf[idx .. idx + payloadLen], self.payload);
        idx += payloadLen;

        // Sanity check
        if (idx != totalSize) {
            return error.UnexpectedFrameSize;
        }

        return buf;
    }

    pub fn fromBytes(frameBuf: []const u8) !Envelope {
        const HeaderType = u32;
        const lenFieldSize = @sizeOf(HeaderType); // 4
        const idLenSize = @sizeOf(u16); // 2

        // Check minimum frame size
        if (frameBuf.len < lenFieldSize + idLenSize) {
            return error.TruncatedFrame;
        }

        // Read and validate remaining length
        const remainingLen = std.mem.readInt(HeaderType, @ptrCast(frameBuf[0..lenFieldSize]), std.builtin.Endian.big);
        if (remainingLen + lenFieldSize != frameBuf.len) {
            return error.InvalidLength;
        }

        // Read sender ID length
        const rawIDLen = std.mem.readInt(u16, @ptrCast(frameBuf[lenFieldSize .. lenFieldSize + idLenSize]), std.builtin.Endian.big);
        const senderIDLen: usize = rawIDLen;

        // Validate frame has enough bytes for sender ID
        if (frameBuf.len < lenFieldSize + idLenSize + senderIDLen) {
            return error.TruncatedFrame;
        }

        // Extract sender ID
        var senderID_out: ?[]const u8 = null;
        if (senderIDLen > 0) {
            senderID_out = frameBuf[(lenFieldSize + idLenSize)..(lenFieldSize + idLenSize + senderIDLen)];
        }

        // Extract payload (everything remaining)
        const payloadStart = lenFieldSize + idLenSize + senderIDLen;
        const payload_out = frameBuf[payloadStart..];

        // Additional validation: ensure we consumed exactly the right amount
        const expectedPayloadLen = remainingLen - idLenSize - senderIDLen;
        if (payload_out.len != expectedPayloadLen) {
            return error.InvalidFrameStructure;
        }

        return Envelope{
            .senderID = senderID_out,
            .payload = payload_out,
        };
    }
};
