local mode_lib = require("control.mode")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local signal_numbers = require("__signal-numbers__.signal-numbers") --[[@as SignalNumbers.Lib]]
local things_client = require("__0-things__.client.client") --[[@as things.client]]
local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local metadata_lib = require("control.metadata")

local VF = ultros.VFlow
local get_tag = things_client.tags_v1.get_tag
local EMPTY = tlib.EMPTY
local signals_to_counts = signal_numbers.signals_to_counts
local number_to_signal = signal_numbers.number_to_signal
local ipairs = ipairs
local pairs = pairs
local get_machine_metadata = metadata_lib.get_machine_metadata
local can_craft_here = metadata_lib.can_craft_here
local is_researched = metadata_lib.is_researched

mode_lib.register_mode({
	name = "ingredients-to-products",
	caption = { "metaselector-ingredients-to-products.caption" },
	settings_element = "Settings.IngredientsToProducts",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator)
			local profiler = helpers.create_profiler()
			local prof_0 = helpers.create_profiler()
			local id = combinator.id
			local inputs = (combinator.inputs or EMPTY) --[[@as Signal[] ]]
			local combinator_entity = combinator.entity
			local surface_index = combinator_entity.surface_index
			local force_index = combinator_entity.force_index
			local machine_sig = get_tag(id, "machine") --[[@as string?]]
			local metadata = get_machine_metadata(machine_sig)
			if not metadata then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local variants = metadata.variants
			local variants_by_pivot_key = metadata.variants_by_pivot_key
			prof_0.stop()
			---@diagnostic disable-next-line: param-type-mismatch
			log({
				"",
				"ingredients-to-products: metadata load took ",
				prof_0,
				" for variants ",
				#variants,
			})

			local prof_1 = helpers.create_profiler()
			---@type SignalNumberCounts
			local input_counts = signals_to_counts(inputs)

			---@type table<SignalNumber, boolean>
			local seen_outputs = {}
			---@type DeciderCombinatorOutput[]
			local outputs = {}
			for key in pairs(input_counts) do
				local variant_ids = variants_by_pivot_key[key]
				if variant_ids then
					for i = 1, #variant_ids do
						local variant = variants[variant_ids[i]] --[[@as Metaselector.RecipeVariant]]
						local variant_recipe_number = variant.recipe_number
						if not can_craft_here(surface_index, variant_recipe_number) then
							goto next_variant
						end
						if not is_researched(force_index, variant_recipe_number) then
							goto next_variant
						end
						local variant_required_keys = variant.required_keys
						local variant_required_amounts = variant.required_amounts
						local can_make = true
						for j = 1, variant.required_count do
							local req_key = variant_required_keys[j]
							if (input_counts[req_key] or 0) < variant_required_amounts[j] then
								can_make = false
								break
							end
						end

						if can_make then
							local product_number = variant.product_number
							if not seen_outputs[product_number] then
								seen_outputs[product_number] = true
								outputs[#outputs + 1] = {
									signal = variant.product,
									copy_count_from_input = false,
									constant = 1,
								}
							end
						end
						::next_variant::
					end
				end
			end
			prof_1.stop()
			---@diagnostic disable-next-line: param-type-mismatch
			log({
				"",
				"ingredients-to-products: candidate collection took ",
				prof_1,
			})

			local prof_3 = helpers.create_profiler()
			combinator:direct_write_outputs(outputs)
			prof_3.stop()
			---@diagnostic disable-next-line: param-type-mismatch
			log({
				"",
				"ingredients-to-products: output write took ",
				prof_3,
			})

			profiler.stop()
			---@diagnostic disable-next-line: param-type-mismatch
			log({ "", "ingredients-to-products took ", profiler })
		end,
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
