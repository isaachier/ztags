const std = @import("std");

fn findTags(node: *std.zig.ast.Node) void {
    std.debug.warn("{}\n", @tagName(node.id));
    var child_i: usize = 0;
    while (node.iterate(child_i)) |child| : (child_i += 1) {
        findTags(child);
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
    var ast = try std.zig.parse(allocator, source);
    defer ast.deinit();

    findTags(&ast.root_node.base);
}
