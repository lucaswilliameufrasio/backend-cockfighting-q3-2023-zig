const std = @import("std");
const zap = @import("zap");
const Connection = @import("pgz").Connection;
const UUID = @import("uuid").UUID;

const SimpleHttpRequestFnWithRouteParams = *const fn (zap.SimpleRequest, ?std.StringHashMap([]const u8)) void;

var getRoutes: std.StringHashMap(SimpleHttpRequestFnWithRouteParams) = undefined;
var postRoutes: std.StringHashMap(SimpleHttpRequestFnWithRouteParams) = undefined;

fn unprocessable_content_response(r: zap.SimpleRequest) void {
    var json_to_send: []const u8 = "{\"message\":\"invalid content\"}";
    r.setStatusNumeric(422);
    r.setContentType(.JSON) catch return;
    r.sendBody(json_to_send) catch return;
}

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

pub const CreatePersonRequestBody = struct {
    apelido: []const u8,
    nome: []const u8,
    nascimento: []const u8,
    stack: ?[][]const u8,
};

// dont look at it xd
// all zap performance was drowned here
fn on_request(r: zap.SimpleRequest) void {
    if (r.path) |the_path| {
        if (r.method) |the_method| {
            const method = std.meta.stringToEnum(RequestMethodsAllowed, the_method) orelse return;

            switch (method) {
                .GET => {
                    if (getRoutes.get(the_path)) |handler| {
                        handler(r, null);
                        return;
                    } else {
                        var getRoutesIterator = getRoutes.iterator();
                        var pathPartsIterator = std.mem.split(u8, the_path, "/");
                        var currentPathPart: []const u8 = "";
                        var thereAreMoreParts: bool = true;
                        var thereAreMoreRouteParts: bool = true;
                        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                        defer arena.deinit();
                        var routeParams: std.StringHashMap([]const u8) = std.StringHashMap([]const u8).init(arena.allocator());

                        // no radix tree, no regex, no linear lookup, just the slowest algorithm you've ever seen
                        anotha_one: while (getRoutesIterator.next()) |route| {
                            var the_route = route.key_ptr.*;
                            var routePathPartsIterator = std.mem.split(u8, the_route, "/");

                            route_path_part_loop: while (routePathPartsIterator.next()) |route_path_part| {
                                if (route_path_part.len == 0) {
                                    continue;
                                }

                                var hasRouteParam = std.mem.startsWith(u8, route_path_part, ":");

                                thereAreMoreRouteParts = routePathPartsIterator.peek() != null and routePathPartsIterator.peek().?.len > 0;
                                path_part_loop: while (pathPartsIterator.next()) |path_part| {
                                    if (path_part.len == 0) {
                                        continue :path_part_loop;
                                    }
                                    thereAreMoreParts = pathPartsIterator.peek() != null and pathPartsIterator.peek().?.len > 0;

                                    if (!hasRouteParam and !std.mem.eql(u8, route_path_part, path_part)) {
                                        pathPartsIterator.reset();
                                        routePathPartsIterator.reset();
                                        continue :anotha_one;
                                    }

                                    currentPathPart = path_part;

                                    if (thereAreMoreRouteParts and !hasRouteParam and std.mem.eql(u8, route_path_part, path_part)) {
                                        continue :route_path_part_loop;
                                    }
                                }

                                if (!thereAreMoreParts and !thereAreMoreRouteParts and std.mem.eql(u8, route_path_part, currentPathPart)) {
                                    route.value_ptr.*(r, routeParams);
                                    return;
                                }

                                if (!thereAreMoreParts and !thereAreMoreRouteParts and hasRouteParam) {
                                    if (hasRouteParam) {
                                        routeParams.put(route_path_part, currentPathPart) catch return;
                                    }
                                    route.value_ptr.*(r, routeParams);
                                    return;
                                }
                            }
                        }
                    }
                },
                .POST => {
                    if (postRoutes.get(the_path)) |handler| {
                        handler(r, null);
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

fn health_check(r: zap.SimpleRequest, params: ?std.StringHashMap([]const u8)) void {
    _ = params;
    r.setContentType(.JSON) catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

fn create_person(r: zap.SimpleRequest, params: ?std.StringHashMap([]const u8)) void {
    _ = params;

    r.parseBody() catch {
        internal_server_error_response(r);
        return;
    };

    if (r.body == null) {
        unprocessable_content_response(r);
        return;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var arenaAllocator = arena.allocator();
    var maybe_person: std.json.Parsed(CreatePersonRequestBody) = std.json.parseFromSlice(CreatePersonRequestBody, arenaAllocator, r.body.?, .{}) catch |err| {
        std.debug.print("Failed to parse body {any}", .{err});
        unprocessable_content_response(r);
        return;
    };
    defer maybe_person.deinit();

    var findPersonStatement = connection.prepare("SELECT people.id AS id FROM people WHERE people.nickname = $1;") catch |err| {
        std.debug.print("\nFailed to prepare statement for finding person {any}\n", .{err});
        internal_server_error_response(r);
        return;
    };

    var personFound = findPersonStatement.query(struct { id: ?[]const u8 }, .{maybe_person.value.apelido}) catch |err| {
        std.debug.print("\nFailed to execute statement for finding person {any}\n", .{err});
        internal_server_error_response(r);
        return;
    };

    if (personFound.data.len > 0) {
        unprocessable_content_response(r);
        return;
    }

    var stacks: []const u8 = "";

    if (maybe_person.value.stack) |stacks_from_body| {
        for (stacks_from_body) |stack_from_body| {
            if (stacks.len == 0) {
                stacks = stack_from_body;
                continue;
            }

            stacks = std.fmt.allocPrint(arenaAllocator, "{s},{s}", .{ stacks, stack_from_body }) catch {
                internal_server_error_response(r);
                return;
            };
        }
    }

    var statement = connection.prepare(
        \\ INSERT INTO people (id, nickname, name, birth_date, stack) 
        \\ VALUES ($1, $2, $3, $4, $5)
        \\ ON CONFLICT DO NOTHING;
        ,
    ) catch |err| {
        std.debug.print("\noxi {any}\n", .{err});
        internal_server_error_response(r);
        return;
    };

    const uuid = std.fmt.allocPrint(arenaAllocator, "{s}", .{UUID.init()}) catch {
        internal_server_error_response(r);
        return;
    };

    statement.exec(.{ uuid, maybe_person.value.apelido, maybe_person.value.nome, maybe_person.value.nascimento, stacks }) catch |err| {
        std.debug.print("Failed to execute query to insert a new person {any}", .{err});
        internal_server_error_response(r);
        return;
    };

    var location = std.fmt.allocPrint(arenaAllocator, "/pessoas/{s}", .{uuid}) catch {
        internal_server_error_response(r);
        return;
    };

    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.created);
    r.setHeader("Location", location) catch return;
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

fn load_people(r: zap.SimpleRequest, params: ?std.StringHashMap([]const u8)) void {
    _ = params;
    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.ok);
    r.sendJson("{\"message\":\"ok\"}") catch return;
}

pub const FindPersonResponseBody = struct {
    id: []const u8,
    apelido: []const u8,
    nome: []const u8,
    nascimento: []const u8,
    stack: ?[][]const u8,
};

fn find_person(r: zap.SimpleRequest, params: ?std.StringHashMap([]const u8)) void {
    if (params == null) {
        not_found_response(r);
        return;
    }

    var id = params.?.get(":id");

    if (id == null or id.?.len != 36) {
        not_found_response(r);
        return;
    }

    var findPersonStatement = connection.prepare("SELECT people.id, people.nickname, people.name, people.birth_date, people.stack FROM people WHERE people.id = $1;") catch |err| {
        std.debug.print("\nFailed to prepare statement for finding person {any}\n", .{err});
        internal_server_error_response(r);
        return;
    };

    var personFound = findPersonStatement.query(struct { id: []const u8, nickname: []const u8, name: []const u8, birth_date: []const u8, stack: []const u8 }, .{id}) catch |err| {
        std.debug.print("\nFailed to execute statement for finding person {any}\n", .{err});
        internal_server_error_response(r);
        return;
    };

    if (personFound.data.len == 0) {
        not_found_response(r);
        return;
    }

    var buffer: [2000]u8 = undefined;
    var json_to_send: []const u8 = undefined;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var arenaAllocator = arena.allocator();

    var stacksList = std.ArrayList([]const u8).init(arenaAllocator);
    defer stacksList.deinit();
    var stacksIterator = std.mem.split(u8, personFound.data[0].stack, ",");

    while (stacksIterator.next()) |stack| {
        stacksList.append(stack) catch continue;
    }

    var person = FindPersonResponseBody{
        .id = personFound.data[0].id,
        .apelido = personFound.data[0].nickname,
        .nome = personFound.data[0].name,
        .nascimento = personFound.data[0].birth_date,
        .stack = stacksList.items,
    };

    if (zap.stringifyBuf(&buffer, person, .{})) |json| {
        json_to_send = json;
    } else {
        internal_server_error_response(r);
        return;
    }

    r.setContentType(.JSON) catch return;
    r.setStatus(zap.StatusCode.ok);
    r.sendJson(json_to_send) catch return;
    return;
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
        .max_body_size = 1 * 1024,
    });

    try listener.listen();

    getRoutes = std.StringHashMap(SimpleHttpRequestFnWithRouteParams).init(allocator);
    postRoutes = std.StringHashMap(SimpleHttpRequestFnWithRouteParams).init(allocator);
    try getRoutes.put("/health-check", health_check);
    try getRoutes.put("/pessoas", load_people);
    try getRoutes.put("/pessoas/:id", find_person);

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
