const std = @import("std");

fn tagKind(id: std.zig.ast.Node.Id) u8 {
    return switch (id) {
        std.zig.ast.Node.Id.FnProto => 'f',
        std.zig.ast.Node.Id.VarDecl => 'v',
        else => u8(0),
    };
}

fn escapeString(allocator: *std.mem.Allocator, line: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    // Max length of escaped string is twice the length of the original line.
    try result.ensureCapacity(line.len * 2);
    for (line) |ch| {
        switch (ch) {
            '/', '\\' => {
                try result.append('\\');
                try result.append(ch);
            },
            else => {
                try result.append(ch);
            },
        }
    }
    return result.toOwnedSlice();
}

fn findTags(allocator: *std.mem.Allocator, tree: *std.zig.ast.Tree, node: *std.zig.ast.Node, path: []const u8) !void {
    std.debug.warn("{}\n", @tagName(node.id));
    var token_index : ?std.zig.ast.TokenIndex = null;
    switch (node.id) {
        std.zig.ast.Node.Id.FnProto => {
            const fn_node = node.cast(std.zig.ast.Node.FnProto).?;
            if (fn_node.name_token) |name_index| {
                token_index = name_index;
            }
        },
        std.zig.ast.Node.Id.VarDecl => {
            const var_node = node.cast(std.zig.ast.Node.VarDecl).?;
            token_index = var_node.name_token;
        },
        else => {},
    }

    if (token_index == null) {
        return;
    }

    const name = tree.tokenSlice(token_index.?);
    const location = tree.tokenLocation(0, token_index.?);
    const line = tree.source[location.line_start..location.line_end];
    const escaped_line = try escapeString(allocator, line);
    defer allocator.free(escaped_line);

    std.debug.warn("{}\t{}\t/^{}$/\";\t{c}\n", name, path, escaped_line, tagKind(node.id));
}

pub fn main() !void {
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();
    const allocator = &direct_allocator.allocator;
    var args_it = std.os.args();
    _ = args_it.skip();  // Discard program name
    const path = try args_it.next(allocator).?;
    defer allocator.free(path);
    const source = try std.io.readFileAlloc(allocator, path);
    defer allocator.free(source);
    var tree = try std.zig.parse(allocator, source);
    defer tree.deinit();

    const node = &tree.root_node.base;
    var child_i: usize = 0;
    while (node.iterate(child_i)) |child| : (child_i += 1) {
        try findTags(allocator, &tree, child, path);
    }
}
