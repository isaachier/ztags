const std = @import("std");

fn tagKind(tree: *std.zig.ast.Tree, node: *std.zig.ast.Node) u8 {
    return switch (node.id) {
        std.zig.ast.Node.Id.FnProto => 'f',
        std.zig.ast.Node.Id.VarDecl => blk: {
            const var_decl_node = node.cast(std.zig.ast.Node.VarDecl).?;
            if (var_decl_node.init_node) |init_node| {
                if (init_node.id == std.zig.ast.Node.Id.ContainerDecl) {
                    const container_node = init_node.cast(std.zig.ast.Node.ContainerDecl).?;
                    break :blk switch (tree.tokens.at(container_node.kind_token).id) {
                        std.zig.Token.Id.Keyword_struct => 's',
                        std.zig.Token.Id.Keyword_union => 'u',
                        std.zig.Token.Id.Keyword_enum => 'e',
                        else => u8(0),
                    };
                }
            }
            break :blk 'v';
        },
        std.zig.ast.Node.Id.StructField,
        std.zig.ast.Node.Id.UnionTag,
        std.zig.ast.Node.Id.EnumTag => 'm',
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

const ErrorSet = error {
    OutOfMemory,
};

fn findTags(allocator: *std.mem.Allocator, tree: *std.zig.ast.Tree, node: *std.zig.ast.Node, path: []const u8, scope_field_name: []const u8, scope: []const u8) ErrorSet!void {
    var token_index : ?std.zig.ast.TokenIndex = null;
    switch (node.id) {
        std.zig.ast.Node.Id.StructField => {
            const struct_field = node.cast(std.zig.ast.Node.StructField).?;
            token_index = struct_field.name_token;
        },
        std.zig.ast.Node.Id.UnionTag => {
            const union_tag = node.cast(std.zig.ast.Node.UnionTag).?;
            token_index = union_tag.name_token;
        },
        std.zig.ast.Node.Id.EnumTag => {
            const enum_tag = node.cast(std.zig.ast.Node.EnumTag).?;
            token_index = enum_tag.name_token;
        },
        std.zig.ast.Node.Id.FnProto => {
            const fn_node = node.cast(std.zig.ast.Node.FnProto).?;
            if (fn_node.name_token) |name_index| {
                token_index = name_index;
            }
        },
        std.zig.ast.Node.Id.VarDecl => blk: {
            const var_node = node.cast(std.zig.ast.Node.VarDecl).?;
            token_index = var_node.name_token;

            if (var_node.init_node) |init_node| {
                if (init_node.id == std.zig.ast.Node.Id.ContainerDecl) {
                    const container_node = init_node.cast(std.zig.ast.Node.ContainerDecl).?;
                    const container_kind = tree.tokenSlice(container_node.kind_token);
                    const container_name = tree.tokenSlice(token_index.?);
                    const delim = ".";
                    var sub_scope : []u8 = undefined;
                    if (scope.len > 0) {
                        sub_scope = try allocator.alloc(u8, scope.len + delim.len + container_name.len);
                        std.mem.copy(u8, sub_scope[0..scope.len], scope);
                        std.mem.copy(u8, sub_scope[scope.len..scope.len+delim.len], delim);
                        std.mem.copy(u8, sub_scope[scope.len+delim.len..], container_name);
                    } else {
                        sub_scope = try std.mem.dupe(allocator, u8, container_name);
                    }
                    defer allocator.free(sub_scope);
                    var it = container_node.fields_and_decls.iterator(0);
                    while (it.next()) |child| {
                        try findTags(allocator, tree, child.*, path, container_kind, sub_scope);
                    }
                }
            }
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

    std.debug.warn("{}\t{}\t/^{}$/\";\t{c}",
        name,
        path,
        escaped_line,
        tagKind(tree, node));
    if (scope.len > 0) {
        std.debug.warn("\t{}:{}", scope_field_name, scope);
    }
    std.debug.warn("\n");
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
        try findTags(allocator, &tree, child, path, "", "");
    }
}
