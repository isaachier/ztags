const std = @import("std");

fn findTags(tree: *std.zig.ast.Tree, node: *std.zig.ast.Node) void {
    if (node.id == std.zig.ast.Node.Id.FnProto) {
        const fn_node = @fieldParentPtr(std.zig.ast.Node.FnProto, "base", node);
        const token_idx = fn_node.name_token.?;
        std.debug.warn("{}\n", tree.tokenSlice(token_idx));
    }

    var child_i: usize = 0;
    while (node.iterate(child_i)) |child| : (child_i += 1) {
        findTags(tree, child);
    }
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

    findTags(&tree, &tree.root_node.base);
}
