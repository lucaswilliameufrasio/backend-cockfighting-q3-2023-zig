const std = @import("std");
const zap = @import("zap");
const Connection = @import("pgz").Connection;

var routes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;

fn on_request(r: zap.SimpleRequest) void {
    // if (!std.mem.eql(u8, r.method.?, "GET"))
    //     return;

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

var connection: Connection = undefined;

fn health_check(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

fn create_person() !void {
    var result = try connection.query("SELECT 1 as number;", struct { number: ?[]const u8 });
    defer result.deinit();
    try std.io.getStdOut().writer().print("number = {s}\n", .{result.data[0].number.?});
}

fn people_routes(r: zap.SimpleRequest) void {
    if (std.mem.eql(u8, r.method.?, "POST")) {
        create_person() catch return;
        r.setContentType(.JSON) catch return;
        r.setStatus(zap.StatusCode.created);
        r.sendJson("{\"message\":\"ok\"}") catch return;
        return;
    }

    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.not_found);
    r.sendJson("{\"message\":\"not found\"}") catch return;
}

pub fn main() !void {
    var dsn = try std.Uri.parse("postgres://postgres:fight@127.0.0.1:5458/fight");
    connection = try Connection.init(std.heap.page_allocator, dsn);
    defer connection.deinit();

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
    try routes.put("/pessoas", people_routes);

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
