local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")

local lib = {}

---@class (exact) Metaselector.ModeRegistration
---@field name string
---@field caption LocalisedString
---@field script_inputs? true
---@field settings_element string
---@field compile? function
---@field script_update? fun(Metaselector.Combinator)

---@type table<string, Metaselector.ModeRegistration>
local modes = {}
lib.modes = modes

---@type Metaselector.ModeRegistration[]
local sorted_modes = {}
lib.sorted_modes = sorted_modes

---@param mode Metaselector.ModeRegistration
function lib.register_mode(mode)
	modes[mode.name] = mode
	table.insert(sorted_modes, mode)
end

lib.register_mode({
	name = "none",
	caption = "None",
	settings_element = "Settings.None",
	compile = function() end,
})

relm.define(
	"Settings.None",
	function(props) return ultros.Label("No mode selected.") end
)

return lib
