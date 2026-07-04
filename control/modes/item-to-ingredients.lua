local mode_lib = require("control.mode")
local siglib = require("lib.core.signal")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local things_client = require("__0-things__.client.client") --[[@as things.client]]

local VF = ultros.VFlow

mode_lib.register_mode({
	name = "item-to-ingredients",
	caption = "Item to Ingredients",
	settings_element = "Settings.ItemToIngredients",
	compile = function(thing, tags)

	end,
})

relm.define("Settings.ItemToIngredients", function(props)
	local thing = things_client.represent(props.thing_id)
	local machine = relm.use_result(function()
		return thing:get_tag("machine")
	end) --[[@as SignalKey?]]

	return {
		ultros.WellSection({
			caption = "Settings",
		}, {
			ultros.Labeled({caption = "Machine"}, {
				ultros.SignalPicker({
					value = machine,
					elem_filters = { { filter = "crafting-machine" } },
					elem_type = "entity",
					on_change = function(me, new_machine)
						if new_machine == machine then return end
						thing:set_tag("machine", new_machine)
					end,
				}),
			})
		}),
		ultros.WellSection({ caption = "Help"}, {
			ultros.RtMultilineLabel("For the given machine, any input item signal representing something the machine can craft will cause an output signal equal to the ingredients of a single craft of that item.\n\nThe value of input signals is ignored, and the output signals are always the ingredients for a single craft of the input item.\n\nIf the machine is not set, or if the input item is not craftable by that machine, no output signals will be produced."
			),
		})
	}
end)
