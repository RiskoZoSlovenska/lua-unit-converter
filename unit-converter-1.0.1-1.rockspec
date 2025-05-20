package = "unit-converter"
version = "1.0.1-1"
source = {
	url = "git://github.com/RiskoZoSlovenska/lua-unit-converter",
	tag = "v1.0.1",
}
description = {
	summary = "A small Lua unit conversion library",
	detailed = "A small Lua unit conversion library.",
	homepage = "https://github.com/RiskoZoSlovenska/lua-unit-converter",
	license = "MIT",
}
dependencies = {
	"lua >= 5.1",
}
build = {
	type = "builtin",
	modules = {
		["unit-converter"] = "unit-converter.lua",
	},
}
