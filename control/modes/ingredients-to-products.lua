local mode_lib = require("control.mode")
local siglib = require("lib.core.signal")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local things_client = require("__0-things__.client.client") --[[@as things.client]]
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local get_machine_metadata = require("control.metadata").get_machine_metadata

local VF = ultros.VFlow
local get_tag = things_client.tags_v1.get_tag
local EMPTY = tlib.EMPTY

mode_lib.register_mode({
	name = "ingredients-to-products",
	caption = { "metaselector-ingredients-to-products.caption" },
	settings_element = "Settings.IngredientsToProducts",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator) end,
})

relm.define("Settings.IngredientsToProducts", function(props)
	local thing = things_client.represent(props.thing_id)
	local machine = relm.use_result(
		function() return thing:get_tag("machine") end
	) --[[@as string?]]

	return {
		ultros.WellSection({
			caption = { "metaselector-general.settings" },
		}, {
			ultros.Labeled({ caption = { "metaselector-general.machine" } }, {
				ultros.SignalPicker({
					value = machine,
					elem_filters = { { filter = "crafting-machine" } },
					elem_type = "entity",
					on_change = function(me, new_machine)
						if new_machine == machine then return end
						thing:set_tag("machine", new_machine)
					end,
				}),
			}),
		}),
		ultros.WellSection({ caption = { "metaselector-general.help" } }, {
			ultros.RtMultilineLabel({
				"metaselector-ingredients-to-products.help-richtext",
			}),
		}),
	}
end)
