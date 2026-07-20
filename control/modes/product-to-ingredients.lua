local mode_lib = require("control.mode")
local siglib = require("lib.core.signal")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local things_client = require("__0-things__.client.client") --[[@as things.client]]
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local metadata_lib = require("control.metadata")
local signal_numbers = require("__signal-numbers__.signal-numbers") --[[@as SignalNumbers.Lib]]

local VF = ultros.VFlow
local get_tag = things_client.tags_v1.get_tag
local EMPTY = tlib.EMPTY
local get_machine_metadata = metadata_lib.get_machine_metadata
local can_craft_here = metadata_lib.can_craft_here
local is_researched = metadata_lib.is_researched
local exploded_signal_to_number = signal_numbers.exploded_signal_to_number

mode_lib.register_mode({
	name = "product-to-ingredients",
	caption = { "metaselector-product-to-ingredients.caption" },
	settings_element = "Settings.ProductToIngredients",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator)
			local id = combinator.id
			local input = (combinator.inputs or EMPTY)[1]
			local machine_sig = get_tag(id, "machine") --[[@as string?]]
			local metadata = get_machine_metadata(machine_sig)
			if not input or not metadata then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local combinator_entity = combinator.entity
			local force = combinator_entity.force --[[@as LuaForce]]
			local item = input.signal.name or ""
			local recipe = metadata.recipes_by_product[item]
			if not recipe then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local recipe_number = exploded_signal_to_number("recipe", recipe.name) --[[@as SignalNumber]]
			local researched = is_researched(force.index, recipe_number)
			if not researched then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			if not can_craft_here(combinator_entity.surface_index, recipe_number) then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local quality = input.signal.quality or "normal"
			---@type DeciderCombinatorOutput[]
			local ingsigs = {}
			for _, ingredient in ipairs(recipe.ingredients or EMPTY) do
				local ingtype = ingredient.type or "item"
				ingsigs[#ingsigs + 1] = {
					signal = {
						type = ingtype,
						name = ingredient.name,
						quality = ingtype == "item" and quality or "normal",
					},
					copy_count_from_input = false,
					constant = math.ceil(ingredient.amount),
				}
			end
			combinator:direct_write_outputs(ingsigs)
		end,
})

relm.define("Settings.ProductToIngredients", function(props)
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
				"metaselector-product-to-ingredients.help-richtext",
			}),
		}),
	}
end)
