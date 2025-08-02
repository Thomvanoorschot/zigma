pub const OHLCUpdate = struct {
    ticker: []const u8,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    trades: u64,
    volume: f64,
    interval: u64,
    timestamp: []const u8,
};