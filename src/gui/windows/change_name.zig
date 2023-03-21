const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:change_name",
	.title = "Change Name",
	.onOpenFn = &onOpen,
	.onCloseFn = &onClose,
	.components = &components,
};
var textComponent: *TextInput = undefined;

const padding: f32 = 8;

fn apply() void {
	const oldName = settings.playerName;
	main.globalAllocator.free(settings.playerName);
	settings.playerName = main.globalAllocator.dupe(u8, textComponent.currentString.items) catch {
		std.log.err("Encountered out of memory in change_name.apply.", .{});
		return;
	};

	gui.closeWindow(&window);
	if(oldName.len == 0) {
		gui.openWindow("cubyz:main") catch |err| {
			std.log.err("Encountered error in change_name.apply: {s}", .{@errorName(err)});
			return;
		};
	}
}

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	if(settings.playerName.len == 0) {
		try list.add(try Label.init(.{0, 0}, width, "Please enter your name!", .center));
	} else {
		try list.add(try Label.init(.{0, 0}, width, "#ff0000Warning: #000000You loose access to your inventory data when changing the name!", .center));
	}
	try list.add(try Label.init(.{0, 0}, width, "Cubyz supports formatting your username using a markdown-like syntax:", .center));
	try list.add(try Label.init(.{0, 0}, width, "\\**italic*\\* \\*\\***bold**\\*\\* \\__underlined_\\_ \\_\\___strike-through__\\_\\_", .center));
	try list.add(try Label.init(.{0, 0}, width, "Even colors are possible, using the hexadecimal color code:", .center));
	try list.add(try Label.init(.{0, 0}, width, "\\##ff0000ff#00000000#00000000#ff0000red#000000 \\##ff0000ff#00770077#00000000#ff7700orange#000000 \\##00000000#00ff00ff#00000000#00ff00green#000000 \\##00000000#00000000#0000ffff#0000ffblue", .center));
	textComponent = try TextInput.init(.{0, 0}, width, 32, "quanturmdoelvloper");
	try list.add(textComponent);
	try list.add(try Button.init(.{0, 0}, 100, "Apply", &apply));
	list.finish(.center);
	components[0] = list.toComponent();
	window.contentSize = components[0].pos() + components[0].size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}