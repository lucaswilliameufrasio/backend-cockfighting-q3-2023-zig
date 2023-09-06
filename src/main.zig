const std = @import("std");
const zap = @import("zap");
const Connection = @import("pgz").Connection;

var routes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;

fn not_found_response(r: zap.SimpleRequest) void {
    var json_to_send: []const u8 = "{\"message\":\"not found\"}";
    r.setStatus(zap.StatusCode.not_found);
    r.setContentType(.JSON) catch return;
    r.sendBody(json_to_send) catch return;
}

fn internal_server_error_response(r: zap.SimpleRequest) void {
    var json_to_send: []const u8 = "{\"message\":\"internal server error\"}";
    r.setStatus(zap.StatusCode.internal_server_error);
    r.setContentType(.JSON) catch return;
    r.sendBody(json_to_send) catch return;
}

// dont look at it xd
// all zap performance was drowned here
fn on_request(r: zap.SimpleRequest) void {
    if (r.path) |the_path| {
        if (r.method) |the_method| {
            std.log.info("{?s} {s}", .{ the_method, the_path });

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const route_path = std.fmt.allocPrint(arena.allocator(), "{s} {s}", .{ the_method, the_path }) catch return;

            if (routes.get(route_path)) |handler| {
                handler(r);
                return;
            }

            // i need to implement a router to handle those cases...
            if (std.mem.startsWith(u8, the_path, "/pessoas/")) {
                find_person(r);
                return;
            }
        }
    }

    not_found_response(r);
}

var connection: Connection = undefined;

fn health_check(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

fn create_person(r: zap.SimpleRequest) void {
    var result = connection.query("SELECT 1 as number;", struct { number: ?[]const u8 }) catch {
        internal_server_error_response(r);
        return;
    };
    defer result.deinit();
    std.io.getStdOut().writer().print("number = {s}\n", .{result.data[0].number.?}) catch {
        internal_server_error_response(r);
        return;
    };

    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.created);
    r.setHeader("Location", "/pessoas/1") catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

fn load_people(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.ok);
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

// I need a router, for sure
fn find_person(r: zap.SimpleRequest) void {
    if (!std.mem.eql(u8, r.method.?, "GET")) {
        not_found_response(r);
        return;
    }

    // It should be handle on 'on_request' method, i know...
    // it is just a non ortodoxy solution :)
    if (r.path) |the_path| {
        var person_id: []const u8 = "";

        var it = std.mem.split(u8, the_path, "/pessoas/");
        while (it.next()) |x| {
            if (x.len <= 0) {
                continue;
            }

            person_id = x;
            std.debug.print("{s}\n", .{x});
        }

        if (person_id.len > 0) {
            std.log.info("Person id = {s}", .{person_id});
        } else {
            std.log.info("Person id not found", .{});
        }
    }

    not_found_response(r);
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
    try routes.put("GET /health-check", health_check);
    try routes.put("GET /pessoas", load_people);
    try routes.put("POST /pessoas", create_person);

    std.debug.print("\nListening on 0.0.0.0:9999\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 16,
        .workers = 2,
    });

    // show potential memory leaks when ZAP is shut down
    const has_leaked = gpa.detectLeaks();
    std.log.debug("Has leaked: {}\n", .{has_leaked});
}
