const std = @import("std");
const zap = @import("zap");

var routes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;

fn on_request(r: zap.SimpleRequest) void {
    if (!std.mem.eql(u8, r.method.?, "GET"))
        return;

    if (r.path) |the_path| {
        if (routes.get(the_path)) |handler| {
            handler(r);
            return;
        }

        var json_to_send: []const u8 = "null";
        // std.debug.print("<< json: {s}\n", .{json_to_send});
        r.setContentType(.JSON) catch return;
        r.sendBody(json_to_send) catch return;
    }
}

fn health_check(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }){};
    var allocator = gpa.allocator();

    var listener = zap.SimpleHttpListener.init(.{
        .port = 9999,
        .on_request = on_request,
        .log = false,
    });

    try listener.listen();

    routes = std.StringHashMap(zap.SimpleHttpRequestFn).init(allocator);
    try routes.put("/health-check", health_check);

    std.debug.print("Listening on 0.0.0.0:9999\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 16,
        .workers = 2,
    });

    // show potential memory leaks when ZAP is shut down
    const has_leaked = gpa.detectLeaks();
    std.log.debug("Has leaked: {}\n", .{has_leaked});
}
