const std = @import("std");
const app = @import("visualization/app.zig");

const App = app.App;
pub fn main() !void {
    App.init(800, 500, "Market Visualization");
}



// QUIC:            
// QUIC offers low latency, built-in encryption, and efficient multiplexing
// without head‐of‐line blocking. This makes it well-suited for streaming
// multiple data feeds concurrently, which is critical for real-time trading data.

// Simple Binary Encoding (SBE):
// SBE is specifically designed for high-frequency trading environments.
// Its fixed-layout binary format minimizes overhead and enables near
// zero-copy parsing, making it ideal for streaming orderbook data and
// candlesticks. SBE’s efficiency and predictable performance have led
// to its adoption in many trading systems.
