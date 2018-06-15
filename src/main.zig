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
    WriteError,
};

const ParseArgs = struct {
    allocator: *std.mem.Allocator,
    tree: *std.zig.ast.Tree,
    node: *std.zig.ast.Node,
    path: []const u8,
    scope_field_name: []const u8,
    scope: []const u8,
    tags_file_stream: *std.io.FileOutStream.Stream,
};

fn findTags(args: *const ParseArgs) ErrorSet!void {
    var token_index : ?std.zig.ast.TokenIndex = null;
    switch (args.node.id) {
        std.zig.ast.Node.Id.StructField => {
            const struct_field = args.node.cast(std.zig.ast.Node.StructField).?;
            token_index = struct_field.name_token;
        },
        std.zig.ast.Node.Id.UnionTag => {
            const union_tag = args.node.cast(std.zig.ast.Node.UnionTag).?;
            token_index = union_tag.name_token;
        },
        std.zig.ast.Node.Id.EnumTag => {
            const enum_tag = args.node.cast(std.zig.ast.Node.EnumTag).?;
            token_index = enum_tag.name_token;
        },
        std.zig.ast.Node.Id.FnProto => {
            const fn_node = args.node.cast(std.zig.ast.Node.FnProto).?;
            if (fn_node.name_token) |name_index| {
                token_index = name_index;
            }
        },
        std.zig.ast.Node.Id.VarDecl => blk: {
            const var_node = args.node.cast(std.zig.ast.Node.VarDecl).?;
            token_index = var_node.name_token;

            if (var_node.init_node) |init_node| {
                if (init_node.id == std.zig.ast.Node.Id.ContainerDecl) {
                    const container_node = init_node.cast(std.zig.ast.Node.ContainerDecl).?;
                    const container_kind = args.tree.tokenSlice(container_node.kind_token);
                    const container_name = args.tree.tokenSlice(token_index.?);
                    const delim = ".";
                    var sub_scope : []u8 = undefined;
                    if (args.scope.len > 0) {
                        sub_scope = try args.allocator.alloc(u8, args.scope.len + delim.len + container_name.len);
                        std.mem.copy(u8, sub_scope[0..args.scope.len], args.scope);
                        std.mem.copy(u8, sub_scope[args.scope.len..args.scope.len+delim.len], delim);
                        std.mem.copy(u8, sub_scope[args.scope.len+delim.len..], container_name);
                    } else {
                        sub_scope = try std.mem.dupe(args.allocator, u8, container_name);
                    }
                    defer args.allocator.free(sub_scope);
                    var it = container_node.fields_and_decls.iterator(0);
                    while (it.next()) |child| {
                        const child_args = ParseArgs{
                            .allocator = args.allocator,
                            .tree = args.tree,
                            .node = child.*,
                            .path = args.path,
                            .scope_field_name = container_kind,
                            .scope = sub_scope,
                            .tags_file_stream = args.tags_file_stream,
                        };
                        try findTags(&child_args);
                    }
                }
            }
        },
        else => {},
    }

    if (token_index == null) {
        return;
    }

    const name = args.tree.tokenSlice(token_index.?);
    const location = args.tree.tokenLocation(0, token_index.?);
    const line = args.tree.source[location.line_start..location.line_end];
    const escaped_line = try escapeString(args.allocator, line);
    defer args.allocator.free(escaped_line);

    args.tags_file_stream.print(
        "{}\t{}\t/^{}$/;\"\t{c}",
        name,
        args.path,
        escaped_line,
        tagKind(args.tree, args.node)) catch return ErrorSet.WriteError;
    if (args.scope.len > 0) {
        args.tags_file_stream.print("\t{}:{}", args.scope_field_name, args.scope) catch return ErrorSet.WriteError;
    }
    args.tags_file_stream.print("\n") catch return ErrorSet.WriteError;
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

    var stdout_file = try std.io.getStdOut();
    var stdout_file_stream = std.io.FileOutStream.init(&stdout_file);
    const stdout = &stdout_file_stream.stream;

    const node = &tree.root_node.base;
    var child_i: usize = 0;
    while (node.iterate(child_i)) |child| : (child_i += 1) {
        const child_args = ParseArgs{
            .allocator = allocator,
            .tree = &tree,
            .node = child,
            .path = path,
            .scope_field_name = "",
            .scope = "",
            .tags_file_stream = stdout,
        };
        try findTags(&child_args);
    }
}
