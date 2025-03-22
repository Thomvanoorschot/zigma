const std = @import("std");
const backstage = @import("backstage");
const concurrency = backstage.concurrency;
const Context = backstage.Context;
const Coroutine = concurrency.Coroutine;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const httpz = @import("httpz");

pub const ServerMessage = union(enum) {
    listen: ServerListenRequest,
};

pub const ServerListenRequest = struct {};

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: httpz.Server(void),

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        var server = try httpz.Server(void).init(allocator, .{ .port = 8080 }, {});
        var router = try server.router(.{});
        router.get("/api/stream", handler, .{});
        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .server = server,
        };

        return self;
    }
    pub fn deinit(self: *Self) void {
        self.server.stop();
        self.server.deinit();
    }
    pub fn receive(self: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .listen => |_| {
                _ = try self.server.listenInNewThread();
            },
        }
    }
    fn handler(_: *httpz.Request, res: *httpz.Response) !void {
        try res.startEventStream(StreamContext{}, StreamContext.handle);
    }
    const StreamContext = struct {
        fn handle(_: StreamContext, s: std.net.Stream) void {
            s.li
            // var allocator = std.heap.GeneralPurposeAllocator(.{}){};
            // defer _ = allocator.deinit();
            // const alloc = allocator.allocator();

            while (true) {
                // some event loop
                std.debug.print("event loop\n", .{});
                // const test_struct = TestStruct{ .firstname = "John", .lastname = "Doe", .age = 30, .address = Address{ .street = "123 Main St", .city = "Anytown", .state = "CA" } };

                // var json_string = std.ArrayList(u8).init(alloc);
                // defer json_string.deinit();

                // std.json.stringify(test_struct, .{}, json_string.writer()) catch break;
                // stream.writeAll(json_string.items) catch break;
            }
        }
    };
};

//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     defer _ = gpa.deinit();
//     const alloc = gpa.allocator();

//     var server = try httpz.Server(void).init(alloc, .{ .port = 8080 }, {});
//     defer {
//         // clean shutdown, finishes serving any live request
//         server.stop();
//         server.deinit();
//     }

//     var router = try server.router(.{});
//     router.get("/api/user/:id", getUser, .{});
//     router.get("/api/stream", handler, .{});
//     try server.listen();

// fn getUser(req: *httpz.Request, res: *httpz.Response) !void {
//     res.status = 200;
//     try res.json(.{ .id = req.param("id").?, .name = "Teg" }, .{});
// }

// fn handler(_: *httpz.Request, res: *httpz.Response) !void {
//     try res.startEventStream(StreamContext{}, StreamContext.handle);
// }

// pub const TestStruct = struct {
//     firstname: []const u8,
//     lastname: []const u8,
//     age: u8,
//     address: Address,
// };

// pub const Address = struct {
//     street: []const u8,
//     city: []const u8,
//     state: []const u8,
// };

// const StreamContext = struct {
//     fn handle(_: StreamContext, stream: std.net.Stream) void {
//         var allocator = std.heap.GeneralPurposeAllocator(.{}){};
//         defer _ = allocator.deinit();
//         const alloc = allocator.allocator();

//         while (true) {
//             // some event loop
//             std.debug.print("event loop\n", .{});
//             const test_struct = TestStruct{ .firstname = "John", .lastname = "Doe", .age = 30, .address = Address{ .street = "123 Main St", .city = "Anytown", .state = "CA" } };

//             var json_string = std.ArrayList(u8).init(alloc);
//             defer json_string.deinit();

//             std.json.stringify(test_struct, .{}, json_string.writer()) catch break;
//             stream.writeAll(json_string.items) catch break;
//         }
//     }
// };
