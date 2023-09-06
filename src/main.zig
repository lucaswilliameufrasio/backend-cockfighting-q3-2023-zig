const std = @import("std");
const zap = @import("zap");
const Connection = @import("pgz").Connection;

var getRoutes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;
var postRoutes: std.StringHashMap(zap.SimpleHttpRequestFn) = undefined;

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

const RequestMethodsAllowed = enum { GET, POST, PUT, DELETE, HEAD, OPTIONS };

// dont look at it xd
// all zap performance was drowned here
fn on_request(r: zap.SimpleRequest) void {
    if (r.path) |the_path| {
        if (r.method) |the_method| {
            std.log.info("{?s} {s}", .{ the_method, the_path });

            const method = std.meta.stringToEnum(RequestMethodsAllowed, the_method) orelse return;

            switch (method) {
                .GET => {
                    if (getRoutes.get(the_path)) |handler| {
                        handler(r);
                        return;
                    } else {
                        var getRoutesIterator = getRoutes.iterator();
                        var pathPartsIterator = std.mem.split(u8, the_path, "/");
                        var currentPathPart: []const u8 = "";
                        var numberOfParts: usize = 0;
                        var thereAreMoreParts: bool = true;
                        var thereAreMoreRouteParts: bool = true;

                        anotha_one: while (getRoutesIterator.next()) |route| {
                            var the_route = route.key_ptr.*;
                            std.log.info("\n\nRoute {s}", .{the_route});
                            var routePathPartsIterator = std.mem.split(u8, the_route, "/");
                            var numberOfRoutePathParts: usize = 0;
                            route_path_part_loop: while (routePathPartsIterator.next()) |route_path_part| {
                                if (route_path_part.len == 0) {
                                    continue;
                                }

                                numberOfRoutePathParts = numberOfRoutePathParts + 1;

                                var hasRouteParam = std.mem.startsWith(u8, route_path_part, ":");
                                std.log.info("Route path part {s}", .{route_path_part});
                                std.log.info("has route param {any}", .{hasRouteParam});

                                thereAreMoreRouteParts = routePathPartsIterator.peek() != null and routePathPartsIterator.peek().?.len > 0;
                                std.log.info("uai {}", .{thereAreMoreRouteParts});
                                std.log.info("Route Path part peek {?s}", .{routePathPartsIterator.peek()});
                                path_part_loop: while (pathPartsIterator.next()) |path_part| {
                                    thereAreMoreParts = pathPartsIterator.peek() != null and pathPartsIterator.peek().?.len > 0;

                                    if (path_part.len == 0) {
                                        std.log.info("oxi {s}", .{path_part});

                                        continue :path_part_loop;
                                    }

                                    currentPathPart = path_part;
                                    numberOfParts = numberOfParts + 1;

                                    std.log.info("Path part peek {?s}", .{pathPartsIterator.peek()});
                                }

                                if (currentPathPart.len > 0) {
                                    std.log.info("Current path part {s}", .{currentPathPart});
                                } else {
                                    std.log.info("There is the b.o on current path part", .{});
                                }

                                std.log.info("There are more path part {any} {any}", .{ thereAreMoreParts, thereAreMoreRouteParts });
                                std.log.info("Number of path parts {any} {any}", .{ numberOfParts, numberOfRoutePathParts });

                                if (thereAreMoreRouteParts and (hasRouteParam or std.mem.eql(u8, route_path_part, currentPathPart))) {
                                    continue :route_path_part_loop;
                                }

                                if (!hasRouteParam and !std.mem.eql(u8, route_path_part, currentPathPart)) {
                                    numberOfParts = 0;
                                    pathPartsIterator.reset();
                                    continue :route_path_part_loop;
                                }

                                if (numberOfParts != numberOfRoutePathParts) {
                                    numberOfParts = 0;
                                    pathPartsIterator.reset();
                                    continue :anotha_one;
                                }

                                if (!thereAreMoreParts and !thereAreMoreRouteParts and std.mem.eql(u8, route_path_part, currentPathPart)) {
                                    std.log.info("Route used without param on last part {s}", .{route.key_ptr.*});
                                    std.log.info("foi aqui? {s} {s}", .{ currentPathPart, route_path_part });
                                    route.value_ptr.*(r);
                                    return;
                                }

                                if (!thereAreMoreParts and !thereAreMoreRouteParts and hasRouteParam) {
                                    std.log.info("Route used with param on last part {s}", .{route.key_ptr.*});
                                    route.value_ptr.*(r);
                                    return;
                                }
                            }
                        }
                    }
                },
                .POST => {
                    if (postRoutes.get(the_path)) |handler| {
                        handler(r);
                        return;
                    }
                },
                else => not_found_response(r),
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

fn wrong_one(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.bad_request);
    r.sendJson("{\"message\":\"wrong\"}") catch return;
}

fn correct_one(r: zap.SimpleRequest) void {
    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.ok);
    r.sendJson("{\"message\":\"got it\"}") catch return;
}

// I need a router, for sure
fn find_person(r: zap.SimpleRequest) void {
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
            r.setContentType(.JSON) catch return;
            r.setStatus(zap.StatusCode.ok);
            r.sendJson("{\"message\":\"ok\"}") catch return;
            return;
        }

        std.log.info("Person id not found", .{});
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

    getRoutes = std.StringHashMap(zap.SimpleHttpRequestFn).init(allocator);
    postRoutes = std.StringHashMap(zap.SimpleHttpRequestFn).init(allocator);
    try getRoutes.put("/health-check", health_check);
    try getRoutes.put("/pessoas", load_people);
    try getRoutes.put("/pessoas/:id", find_person);
    try getRoutes.put("/teste/:id", wrong_one);
    try getRoutes.put("/teste/:id/abc", correct_one);
    try getRoutes.put("/teste/:id/abc/:denovo/efg/oia", correct_one);
    try getRoutes.put("/teste/:id/abc/:denovo/efg", correct_one);
    try postRoutes.put("/pessoas", create_person);

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
