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
	name = "product-to-ingredients",
	caption = "Product to Ingredients",
	settings_element = "Settings.ProductToIngredients",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator)
			local id = combinator.id
			local input = (combinator.inputs or EMPTY)[1]
			local machine_sig = get_tag(id, "machine") --[[@as string?]]
			strace.trace(
				"product-to-ingredients:script_update id",
				id,
				"input",
				input,
				"machine_sig",
				machine_sig
			)
			local metadata =
				get_machine_metadata(machine_sig, combinator.entity.surface)
			if not input or not metadata then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local item = input.signal.name or ""
			local recipe = metadata.recipes_by_product[item]
			if not recipe then
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
			caption = "Settings",
		}, {
			ultros.Labeled({ caption = "Machine" }, {
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
		ultros.WellSection({ caption = "Help" }, {
			ultros.RtMultilineLabel(
				"[font=default-bold]This mode is scripted.[/font]\n\nFor the given machine, the first input item signal representing something the machine can craft will cause an output signal equal to the ingredients of a single craft of that item.\n\nThe value of input signal is ignored, and the output signals are always the ingredients for a single craft of the input item.\n\nIf the machine is not set, or if the input item is not craftable by that machine, no output signals will be produced."
			),
		}),
	}
end)
