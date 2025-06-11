// Batently copied from https://github.com/karlseguin/zul/blob/master/src/datetime.zig
const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Date = struct {
    year: i16,
    month: u8,
    day: u8,

    pub const Format = enum {
        iso8601,
        rfc3339,
    };

    pub fn init(year: i16, month: u8, day: u8) !Date {
        if (!Date.valid(year, month, day)) {
            return error.InvalidDate;
        }

        return .{
            .year = year,
            .month = month,
            .day = day,
        };
    }

    pub fn valid(year: i16, month: u8, day: u8) bool {
        if (month == 0 or month > 12) {
            return false;
        }

        if (day == 0) {
            return false;
        }

        const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        const max_days = if (month == 2 and (@rem(year, 400) == 0 or (@rem(year, 100) != 0 and @rem(year, 4) == 0))) 29 else month_days[month - 1];
        if (day > max_days) {
            return false;
        }

        return true;
    }

    pub fn parse(input: []const u8, fmt: Format) !Date {
        var parser = Parser.init(input);

        const date = switch (fmt) {
            .rfc3339 => try parser.rfc3339Date(),
            .iso8601 => try parser.iso8601Date(),
        };

        if (parser.unconsumed() != 0) {
            return error.InvalidDate;
        }

        return date;
    }

    pub fn order(a: Date, b: Date) std.math.Order {
        const year_order = std.math.order(a.year, b.year);
        if (year_order != .eq) return year_order;

        const month_order = std.math.order(a.month, b.month);
        if (month_order != .eq) return month_order;

        return std.math.order(a.day, b.day);
    }

    pub fn format(self: Date, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
        var buf: [11]u8 = undefined;
        const n = writeDate(&buf, self);
        try out.writeAll(buf[0..n]);
    }

    pub fn jsonStringify(self: Date, out: anytype) !void {
        // Our goal here isn't to validate the date. It's to write what we have
        // in a YYYY-MM-DD format. If the data in Date isn't valid, that's not
        // our problem and we don't guarantee any reasonable output in such cases.

        // std.fmt.formatInt is difficult to work with. The padding with signs
        // doesn't work and it'll always put a + sign given a signed integer with padding
        // So, for year, we always feed it an unsigned number (which avoids both issues)
        // and prepend the - if we need it.s
        var buf: [13]u8 = undefined;
        const n = writeDate(buf[1..12], self);
        buf[0] = '"';
        buf[n + 1] = '"';
        try out.print("{s}", .{buf[0 .. n + 2]});
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: anytype) !Date {
        _ = options;

        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
            inline .string, .allocated_string => |str| return Date.parse(str, .rfc3339) catch return error.InvalidCharacter,
            else => return error.UnexpectedToken,
        }
    }
};

pub const Time = struct {
    hour: u8,
    min: u8,
    sec: u8,
    micros: u32,

    pub const Format = enum {
        rfc3339,
    };

    pub fn init(hour: u8, min: u8, sec: u8, micros: u32) !Time {
        if (!Time.valid(hour, min, sec, micros)) {
            return error.InvalidTime;
        }

        return .{
            .hour = hour,
            .min = min,
            .sec = sec,
            .micros = micros,
        };
    }

    pub fn valid(hour: u8, min: u8, sec: u8, micros: u32) bool {
        if (hour > 23) {
            return false;
        }

        if (min > 59) {
            return false;
        }

        if (sec > 59) {
            return false;
        }

        if (micros > 999999) {
            return false;
        }

        return true;
    }

    pub fn parse(input: []const u8, fmt: Format) !Time {
        var parser = Parser.init(input);
        const time = switch (fmt) {
            .rfc3339 => try parser.time(),
        };

        if (parser.unconsumed() != 0) {
            return error.InvalidTime;
        }
        return time;
    }

    pub fn order(a: Time, b: Time) std.math.Order {
        const hour_order = std.math.order(a.hour, b.hour);
        if (hour_order != .eq) return hour_order;

        const min_order = std.math.order(a.min, b.min);
        if (min_order != .eq) return min_order;

        const sec_order = std.math.order(a.sec, b.sec);
        if (sec_order != .eq) return sec_order;

        return std.math.order(a.micros, b.micros);
    }

    pub fn format(self: Time, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
        var buf: [15]u8 = undefined;
        const n = writeTime(&buf, self);
        try out.writeAll(buf[0..n]);
    }

    pub fn jsonStringify(self: Time, out: anytype) !void {
        // Our goal here isn't to validate the time. It's to write what we have
        // in a hh:mm:ss.sss format. If the data in Time isn't valid, that's not
        // our problem and we don't guarantee any reasonable output in such cases.
        var buf: [17]u8 = undefined;
        const n = writeTime(buf[1..16], self);
        buf[0] = '"';
        buf[n + 1] = '"';
        try out.print("{s}", .{buf[0 .. n + 2]});
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: anytype) !Time {
        _ = options;

        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
            inline .string, .allocated_string => |str| return Time.parse(str, .rfc3339) catch return error.InvalidCharacter,
            else => return error.UnexpectedToken,
        }
    }
};

pub const DateTime = struct {
    micros: i64,

    const MICROSECONDS_IN_A_DAY = 86_400_000_000;
    const MICROSECONDS_IN_AN_HOUR = 3_600_000_000;
    const MICROSECONDS_IN_A_MIN = 60_000_000;
    const MICROSECONDS_IN_A_SEC = 1_000_000;

    pub const Format = enum {
        rfc3339,
    };

    pub const TimestampPrecision = enum {
        seconds,
        milliseconds,
        microseconds,
    };

    pub const TimeUnit = enum {
        days,
        hours,
        minutes,
        seconds,
        milliseconds,
        microseconds,
    };

    // https://blog.reverberate.org/2020/05/12/optimizing-date-algorithms.html
    pub fn initUTC(year: i16, month: u8, day: u8, hour: u8, min: u8, sec: u8, micros: u32) !DateTime {
        if (Date.valid(year, month, day) == false) {
            return error.InvalidDate;
        }

        if (Time.valid(hour, min, sec, micros) == false) {
            return error.InvalidTime;
        }

        const year_base = 4800;
        const month_adj = @as(i32, @intCast(month)) - 3; // March-based month
        const carry: u8 = if (month_adj < 0) 1 else 0;
        const adjust: u8 = if (carry == 1) 12 else 0;
        const year_adj: i64 = year + year_base - carry;
        const month_days = @divTrunc(((month_adj + adjust) * 62719 + 769), 2048);
        const leap_days = @divTrunc(year_adj, 4) - @divTrunc(year_adj, 100) + @divTrunc(year_adj, 400);

        const date_micros: i64 = (year_adj * 365 + leap_days + month_days + (day - 1) - 2472632) * MICROSECONDS_IN_A_DAY;
        const time_micros = (@as(i64, @intCast(hour)) * MICROSECONDS_IN_AN_HOUR) + (@as(i64, @intCast(min)) * MICROSECONDS_IN_A_MIN) + (@as(i64, @intCast(sec)) * MICROSECONDS_IN_A_SEC) + micros;

        return fromUnix(date_micros + time_micros, .microseconds);
    }

    pub fn fromUnix(value: i64, precision: TimestampPrecision) !DateTime {
        switch (precision) {
            .seconds => {
                if (value < -210863520000 or value > 253402300799) {
                    return error.OutsideJulianPeriod;
                }
                return .{ .micros = value * 1_000_000 };
            },
            .milliseconds => {
                if (value < -210863520000000 or value > 253402300799999) {
                    return error.OutsideJulianPeriod;
                }
                return .{ .micros = value * 1_000 };
            },
            .microseconds => {
                if (value < -210863520000000000 or value > 253402300799999999) {
                    return error.OutsideJulianPeriod;
                }
                return .{ .micros = value };
            },
        }
    }

    pub fn now() DateTime {
        return .{
            .micros = std.time.microTimestamp(),
        };
    }

    pub fn parse(input: []const u8, fmt: Format) !DateTime {
        switch (fmt) {
            .rfc3339 => return parseRFC3339(input),
        }
    }

    pub fn parseRFC3339(input: []const u8) !DateTime {
        var parser = Parser.init(input);

        const dt = try parser.rfc3339Date();

        const year = dt.year;
        if (year < -4712 or year > 9999) {
            return error.OutsideJulianPeriod;
        }

        // Per the spec, it can be argued thatt 't' and even ' ' should be allowed,
        // but certainly not encouraged.
        if (parser.consumeIf('T') == false) {
            return error.InvalidDateTime;
        }

        const tm = try parser.time();

        switch (parser.unconsumed()) {
            0 => return error.InvalidDateTime,
            1 => if (parser.consumeIf('Z') == false) {
                return error.InvalidDateTime;
            },
            6 => {
                const suffix = parser.rest();
                if (suffix[0] != '+' and suffix[0] != '-') {
                    return error.InvalidDateTime;
                }
                if (std.mem.eql(u8, suffix[1..], "00:00") == false) {
                    return error.NonUTCNotSupported;
                }
            },
            else => return error.InvalidDateTime,
        }

        return initUTC(dt.year, dt.month, dt.day, tm.hour, tm.min, tm.sec, tm.micros);
    }

    pub fn add(dt: DateTime, value: i64, unit: TimeUnit) !DateTime {
        const micros = dt.micros;
        switch (unit) {
            .days => return fromUnix(micros + value * MICROSECONDS_IN_A_DAY, .microseconds),
            .hours => return fromUnix(micros + value * MICROSECONDS_IN_AN_HOUR, .microseconds),
            .minutes => return fromUnix(micros + value * MICROSECONDS_IN_A_MIN, .microseconds),
            .seconds => return fromUnix(micros + value * MICROSECONDS_IN_A_SEC, .microseconds),
            .milliseconds => return fromUnix(micros + value * 1_000, .microseconds),
            .microseconds => return fromUnix(micros + value, .microseconds),
        }
    }

    // https://git.musl-libc.org/cgit/musl/tree/src/time/__secs_to_tm.c?h=v0.9.15
    pub fn date(dt: DateTime) Date {
        // 2000-03-01 (mod 400 year, immediately after feb29
        const leap_epoch = 946684800 + 86400 * (31 + 29);
        const days_per_400y = 365 * 400 + 97;
        const days_per_100y = 365 * 100 + 24;
        const days_per_4y = 365 * 4 + 1;

        // march-based
        const month_days = [_]u8{ 31, 30, 31, 30, 31, 31, 30, 31, 30, 31, 31, 29 };

        const secs = @divTrunc(dt.micros, 1_000_000) - leap_epoch;

        var days = @divTrunc(secs, 86400);
        if (@rem(secs, 86400) < 0) {
            days -= 1;
        }

        var qc_cycles = @divTrunc(days, days_per_400y);
        var rem_days = @rem(days, days_per_400y);
        if (rem_days < 0) {
            rem_days += days_per_400y;
            qc_cycles -= 1;
        }

        var c_cycles = @divTrunc(rem_days, days_per_100y);
        if (c_cycles == 4) {
            c_cycles -= 1;
        }
        rem_days -= c_cycles * days_per_100y;

        var q_cycles = @divTrunc(rem_days, days_per_4y);
        if (q_cycles == 25) {
            q_cycles -= 1;
        }
        rem_days -= q_cycles * days_per_4y;

        var rem_years = @divTrunc(rem_days, 365);
        if (rem_years == 4) {
            rem_years -= 1;
        }
        rem_days -= rem_years * 365;

        var year = rem_years + 4 * q_cycles + 100 * c_cycles + 400 * qc_cycles + 2000;

        var month: u8 = 0;
        while (month_days[month] <= rem_days) : (month += 1) {
            rem_days -= month_days[month];
        }

        month += 2;
        if (month >= 12) {
            year += 1;
            month -= 12;
        }

        return .{
            .year = @intCast(year),
            .month = month + 1,
            .day = @intCast(rem_days + 1),
        };
    }

    pub fn time(dt: DateTime) Time {
        const micros = @mod(dt.micros, MICROSECONDS_IN_A_DAY);

        return .{
            .hour = @intCast(@divTrunc(micros, MICROSECONDS_IN_AN_HOUR)),
            .min = @intCast(@divTrunc(@rem(micros, MICROSECONDS_IN_AN_HOUR), MICROSECONDS_IN_A_MIN)),
            .sec = @intCast(@divTrunc(@rem(micros, MICROSECONDS_IN_A_MIN), MICROSECONDS_IN_A_SEC)),
            .micros = @intCast(@rem(micros, MICROSECONDS_IN_A_SEC)),
        };
    }

    pub fn unix(self: DateTime, precision: TimestampPrecision) i64 {
        const micros = self.micros;
        return switch (precision) {
            .seconds => @divTrunc(micros, 1_000_000),
            .milliseconds => @divTrunc(micros, 1_000),
            .microseconds => micros,
        };
    }

    pub fn order(a: DateTime, b: DateTime) std.math.Order {
        return std.math.order(a.micros, b.micros);
    }

    pub fn format(self: DateTime, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
        var buf: [28]u8 = undefined;
        const n = self.bufWrite(&buf);
        try out.writeAll(buf[0..n]);
    }

    pub fn jsonStringify(self: DateTime, out: anytype) !void {
        var buf: [30]u8 = undefined;
        buf[0] = '"';
        const n = self.bufWrite(buf[1..]);
        buf[n + 1] = '"';
        try out.print("{s}", .{buf[0 .. n + 2]});
    }

    pub fn jsonParse(allocator: Allocator, source: anytype, options: anytype) !DateTime {
        _ = options;

        switch (try source.nextAlloc(allocator, .alloc_if_needed)) {
            inline .string, .allocated_string => |str| return parseRFC3339(str) catch return error.InvalidCharacter,
            else => return error.UnexpectedToken,
        }
    }

    fn bufWrite(self: DateTime, buf: []u8) usize {
        const date_n = writeDate(buf, self.date());

        buf[date_n] = 'T';

        const time_start = date_n + 1;
        const time_n = writeTime(buf[time_start..], self.time());

        const time_stop = time_start + time_n;
        buf[time_stop] = 'Z';

        return time_stop + 1;
    }
};

fn writeDate(into: []u8, date: Date) u8 {
    var buf: []u8 = undefined;
    // cast year to a u16 so it doesn't insert a sign
    // we don't want the + sign, ever
    // and we don't even want it to insert the - sign, because it screws up
    // the padding (we need to do it ourselfs)
    const year = date.year;
    if (year < 0) {
        _ = std.fmt.formatIntBuf(into[1..], @as(u16, @intCast(year * -1)), 10, .lower, .{ .width = 4, .fill = '0' });
        into[0] = '-';
        buf = into[5..];
    } else {
        _ = std.fmt.formatIntBuf(into, @as(u16, @intCast(year)), 10, .lower, .{ .width = 4, .fill = '0' });
        buf = into[4..];
    }

    buf[0] = '-';
    buf[1..3].* = paddingTwoDigits(date.month);
    buf[3] = '-';
    buf[4..6].* = paddingTwoDigits(date.day);

    // return the length of the string. 10 for positive year, 11 for negative
    return if (year < 0) 11 else 10;
}

fn writeTime(into: []u8, time: Time) u8 {
    into[0..2].* = paddingTwoDigits(time.hour);
    into[2] = ':';
    into[3..5].* = paddingTwoDigits(time.min);
    into[5] = ':';
    into[6..8].* = paddingTwoDigits(time.sec);

    const micros = time.micros;
    if (micros == 0) {
        return 8;
    }

    if (@rem(micros, 1000) == 0) {
        into[8] = '.';
        _ = std.fmt.formatIntBuf(into[9..12], micros / 1000, 10, .lower, .{ .width = 3, .fill = '0' });
        return 12;
    }

    into[8] = '.';
    _ = std.fmt.formatIntBuf(into[9..15], micros, 10, .lower, .{ .width = 6, .fill = '0' });
    return 15;
}

fn paddingTwoDigits(value: usize) [2]u8 {
    std.debug.assert(value < 61);
    const digits = "0001020304050607080910111213141516171819" ++
        "2021222324252627282930313233343536373839" ++
        "4041424344454647484950515253545556575859" ++
        "60";
    return digits[value * 2 ..][0..2].*;
}

const Parser = struct {
    input: []const u8,
    pos: usize,

    fn init(input: []const u8) Parser {
        return .{
            .pos = 0,
            .input = input,
        };
    }

    fn unconsumed(self: *const Parser) usize {
        return self.input.len - self.pos;
    }

    fn rest(self: *const Parser) []const u8 {
        return self.input[self.pos..];
    }

    // unsafe, assumes caller has checked remaining first
    fn peek(self: *const Parser) u8 {
        return self.input[self.pos];
    }

    // unsafe, assumes caller has checked remaining first
    fn consumeIf(self: *Parser, c: u8) bool {
        const pos = self.pos;
        if (self.input[pos] != c) {
            return false;
        }
        self.pos = pos + 1;
        return true;
    }

    fn nanoseconds(self: *Parser) ?usize {
        const start = self.pos;
        const input = self.input[start..];

        var len = input.len;
        if (len == 0) {
            return null;
        }

        var value: usize = 0;
        for (input, 0..) |b, i| {
            const n = b -% '0'; // wrapping subtraction
            if (n > 9) {
                len = i;
                break;
            }
            value = value * 10 + n;
        }

        if (len > 9) {
            return null;
        }

        self.pos = start + len;
        return value * std.math.pow(usize, 10, 9 - len);
    }

    fn paddedInt(self: *Parser, comptime T: type, size: u8) ?T {
        const pos = self.pos;
        const end = pos + size;
        const input = self.input;

        if (end > input.len) {
            return null;
        }

        var value: T = 0;
        for (input[pos..end]) |b| {
            const n = b -% '0'; // wrapping subtraction
            if (n > 9) return null;
            value = value * 10 + n;
        }
        self.pos = end;
        return value;
    }

    fn time(self: *Parser) !Time {
        const len = self.unconsumed();
        if (len < 5) {
            return error.InvalidTime;
        }

        const hour = self.paddedInt(u8, 2) orelse return error.InvalidTime;
        if (self.consumeIf(':') == false) {
            return error.InvalidTime;
        }

        const min = self.paddedInt(u8, 2) orelse return error.InvalidTime;
        if (len == 5 or self.consumeIf(':') == false) {
            return Time.init(hour, min, 0, 0);
        }

        const sec = self.paddedInt(u8, 2) orelse return error.InvalidTime;
        if (len == 8 or self.consumeIf('.') == false) {
            return Time.init(hour, min, sec, 0);
        }

        const nanos = self.nanoseconds() orelse return error.InvalidTime;
        return Time.init(hour, min, sec, @intCast(nanos / 1000));
    }

    fn iso8601Date(self: *Parser) !Date {
        const len = self.unconsumed();
        if (len < 8) {
            return error.InvalidDate;
        }

        const negative = self.consumeIf('-');
        const year = self.paddedInt(i16, 4) orelse return error.InvalidDate;

        var with_dashes = false;
        if (self.consumeIf('-')) {
            if (len < 10) {
                return error.InvalidDate;
            }
            with_dashes = true;
        }

        const month = self.paddedInt(u8, 2) orelse return error.InvalidDate;
        if (self.consumeIf('-') == !with_dashes) {
            return error.InvalidDate;
        }

        const day = self.paddedInt(u8, 2) orelse return error.InvalidDate;
        return Date.init(if (negative) -year else year, month, day);
    }

    fn rfc3339Date(self: *Parser) !Date {
        const len = self.unconsumed();
        if (len < 10) {
            return error.InvalidDate;
        }

        const negative = self.consumeIf('-');
        const year = self.paddedInt(i16, 4) orelse return error.InvalidDate;

        if (self.consumeIf('-') == false) {
            return error.InvalidDate;
        }

        const month = self.paddedInt(u8, 2) orelse return error.InvalidDate;

        if (self.consumeIf('-') == false) {
            return error.InvalidDate;
        }

        const day = self.paddedInt(u8, 2) orelse return error.InvalidDate;
        return Date.init(if (negative) -year else year, month, day);
    }
};
