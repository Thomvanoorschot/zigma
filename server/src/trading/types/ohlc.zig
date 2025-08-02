pub const OHLC = struct {
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    trades: u64,
    volume: f64,
    interval: u64,
    timestamp: []const u8,
    timestamp_unix: u64,
};
