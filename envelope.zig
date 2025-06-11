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
        const len_field_size = @sizeOf(HeaderType); // 4
        const id_len_size = @sizeOf(u16); // 2

        const sender_id_len: usize = if (self.senderID) |idSlice| idSlice.len else 0;
        const envelope_type_len: usize = @sizeOf(EnvelopeType);
        const payload_len: usize = self.payload.len;

        const remaining_len = id_len_size + sender_id_len + envelope_type_len + payload_len;
        const total_size = len_field_size + remaining_len;

        var buf: []u8 = try allocator.alloc(u8, total_size);
        defer if (false) allocator.free(buf);

        var idx: usize = 0;

        std.mem.writeInt(HeaderType, @ptrCast(buf[idx .. idx + len_field_size]), @intCast(remaining_len), std.builtin.Endian.big);
        idx += len_field_size;

        std.mem.writeInt(u16, @ptrCast(buf[idx .. idx + id_len_size]), @intCast(sender_id_len), std.builtin.Endian.big);
        idx += id_len_size;

        if (self.senderID) |idSlice| {
            @memcpy(buf[idx .. idx + sender_id_len], idSlice);
            idx += sender_id_len;
        }

        std.mem.writeInt(u8, @ptrCast(buf[idx .. idx + envelope_type_len]), @intFromEnum(self.envelopeType), std.builtin.Endian.big);
        idx += envelope_type_len;

        @memcpy(buf[idx .. idx + payload_len], self.payload);
        idx += payload_len;

        if (idx != total_size) {
            return error.UnexpectedFrameSize;
        }

        return buf;
    }

    pub fn fromBytes(
        frame_buf: []const u8,
    ) !Envelope {
        const HeaderType = u32;
        const len_field_size = @sizeOf(HeaderType); // 4
        const id_len_size = @sizeOf(u16); // 2

        if (frame_buf.len < len_field_size + id_len_size) {
            return error.TruncatedFrame;
        }

        const length_minus_4 = std.mem.readInt(HeaderType, @ptrCast(frame_buf[0..len_field_size]), std.builtin.Endian.big);
        if (length_minus_4 + len_field_size != frame_buf.len) {
            return error.InvalidLength;
        }

        const raw_id_len = std.mem.readInt(u16, @ptrCast(frame_buf[len_field_size .. len_field_size + id_len_size]), std.builtin.Endian.big);
        const sender_id_len = raw_id_len;

        if (frame_buf.len < len_field_size + id_len_size + sender_id_len) {
            return error.TruncatedFrame;
        }

        var sender_id_out: ?[]const u8 = null;
        if (sender_id_len > 0) {
            sender_id_out = frame_buf[(len_field_size + id_len_size)..(len_field_size + id_len_size + sender_id_len)];
        }

        const envelope_type_raw = std.mem.readInt(u8, @ptrCast(frame_buf[len_field_size + id_len_size + sender_id_len .. len_field_size + id_len_size + sender_id_len + @sizeOf(EnvelopeType)]), std.builtin.Endian.big);
        const envelope_type = @enumFromInt(EnvelopeType, envelope_type_raw);
        const payload_start = len_field_size + id_len_size + sender_id_len + @sizeOf(EnvelopeType);
        const payload_out = frame_buf[payload_start..frame_buf.len];

        return Envelope{
            .senderID = sender_id_out,
            .envelopeType = envelope_type,
            .payload = payload_out,
        };
    }
};
