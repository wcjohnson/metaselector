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
local signal_to_key = siglib.signal_to_key
local signals_to_counts = siglib.signals_to_counts
local ipairs = ipairs
local pairs = pairs

mode_lib.register_mode({
	name = "ingredients-to-products",
	caption = { "metaselector-ingredients-to-products.caption" },
	settings_element = "Settings.IngredientsToProducts",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator)
			local profiler = helpers.create_profiler()
			local id = combinator.id
			local inputs = (combinator.inputs or EMPTY) --[[@as Signal[] ]]
			local machine_sig = get_tag(id, "machine") --[[@as string?]]
			local metadata =
				get_machine_metadata(machine_sig, combinator.entity.surface)
			if not metadata then
				combinator:direct_write_outputs(EMPTY)
				return
			end
			local variants = metadata.variants
			local variants_by_pivot_key = metadata.variants_by_pivot_key

			---@type SignalCounts
			local input_counts = signals_to_counts(inputs)

			local prof_1 = helpers.create_profiler()
			---@type integer[]
			local candidates = {}
			for key in pairs(input_counts) do
				local variant_ids = variants_by_pivot_key[key]
				if variant_ids then
					for i = 1, #variant_ids do
						candidates[#candidates + 1] = variant_ids[i]
					end
				end
			end
			local candidate_count = #candidates
			prof_1.stop()
			log({
				"",
				"ingredients-to-products: pivot candidate collection took ",
				prof_1,
				" for hits ",
				candidate_count,
			})

			local prof_2 = helpers.create_profiler()
			---@type table<SignalKey, boolean>
			local seen_outputs = {}
			---@type DeciderCombinatorOutput[]
			local outputs = {}
			for i = 1, candidate_count do
				local variant = variants[candidates[i]] --[[@as Metaselector.RecipeVariant]]
				local can_make = true
				for j = 1, variant.required_count do
					local key = variant.required_keys[j]
					if (input_counts[key] or 0) < variant.required_amounts[j] then
						can_make = false
						break
					end
				end

				if can_make then
					local product_key = signal_to_key(variant.product)
					if not seen_outputs[product_key] then
						seen_outputs[product_key] = true
						outputs[#outputs + 1] = {
							signal = variant.product,
							copy_count_from_input = false,
							constant = 1,
						}
					end
				end
			end
			prof_2.stop()
			log({
				"",
				"ingredients-to-products: output generation took ",
				prof_2,
				" for outputs ",
				#outputs,
			})

			profiler.stop()
			---@diagnostic disable-next-line: param-type-mismatch
			log({ "", "ingredients-to-products took ", profiler })
			combinator:direct_write_outputs(outputs)
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
