local mode_lib = require("control.mode")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local signal_numbers = require("__signal-numbers__.signal-numbers") --[[@as SignalNumbers.Lib]]
local things_client = require("__0-things__.client.client") --[[@as things.client]]
local tlib = require("lib.core.table")
local metadata_lib = require("control.metadata")

local get_tag = things_client.tags_v1.get_tag
local EMPTY = tlib.EMPTY
local signals_to_counts = signal_numbers.signals_to_counts
local number_to_signal = signal_numbers.number_to_signal
local pairs = pairs
local get_machine_metadata = metadata_lib.get_machine_metadata
local can_craft_here = metadata_lib.can_craft_here
local is_researched = metadata_lib.is_researched

---@class Metaselector.I2PState
---@field public machine_sig string
---@field public variant_missing table<integer, integer>
---@field public variant_active table<integer, boolean>
---@field public product_refcount table<SignalNumber, integer>
---@field public changed_keys SignalNumber[]
---@field public changed_variants integer[]
---@field public delta_missing table<integer, integer>

---@param state Metaselector.I2PState
local function clear_scratch(state)
	local changed_keys = state.changed_keys
	for i = 1, #changed_keys do
		changed_keys[i] = nil
	end
	local changed_variants = state.changed_variants
	for i = 1, #changed_variants do
		changed_variants[i] = nil
	end
	local delta_missing = state.delta_missing
	for variant_id in pairs(delta_missing) do
		delta_missing[variant_id] = nil
	end
end

---@param state Metaselector.I2PState
---@param metadata Metaselector.MachineMetadata
---@param input_counts table<SignalNumber, int32>
---@param surface_index integer
---@param force_index integer
local function init_state(
	state,
	metadata,
	input_counts,
	surface_index,
	force_index
)
	clear_scratch(state)
	local variant_missing = state.variant_missing
	local variant_active = state.variant_active
	local product_refcount = state.product_refcount
	for k in pairs(variant_missing) do
		variant_missing[k] = nil
	end
	for k in pairs(variant_active) do
		variant_active[k] = nil
	end
	for k in pairs(product_refcount) do
		product_refcount[k] = nil
	end

	local variants = metadata.variants
	for variant_id = 1, metadata.variant_count do
		local variant = variants[variant_id] --[[@as Metaselector.RecipeVariant]]
		local missing = 0
		local required_keys = variant.required_keys
		local required_amounts = variant.required_amounts
		for i = 1, variant.required_count do
			if (input_counts[required_keys[i]] or 0) < required_amounts[i] then
				missing = missing + 1
			end
		end
		variant_missing[variant_id] = missing
		if missing == 0 then
			local recipe_number = variant.recipe_number
			if
				can_craft_here(surface_index, recipe_number)
				and is_researched(force_index, recipe_number)
			then
				variant_active[variant_id] = true
				local product_number = variant.product_number
				product_refcount[product_number] = (
					product_refcount[product_number] or 0
				) + 1
			else
				variant_active[variant_id] = false
			end
		else
			variant_active[variant_id] = false
		end
	end
end

---@param combinator Metaselector.Combinator
---@param state Metaselector.I2PState
local function write_outputs_from_state(combinator, state)
	---@type DeciderCombinatorOutput[]
	local outputs = {}
	for product_number, refcount in pairs(state.product_refcount) do
		if refcount > 0 then
			local product = number_to_signal(product_number)
			if product then
				outputs[#outputs + 1] = {
					signal = product,
					copy_count_from_input = false,
					constant = 1,
				}
			end
		end
	end
	combinator:direct_write_outputs(outputs)
	combinator.outputs_dirty = nil
end

mode_lib.register_mode({
	name = "ingredients-to-products",
	caption = { "metaselector-ingredients-to-products.caption" },
	settings_element = "Settings.IngredientsToProducts",
	script_inputs = true,
	script_update =
		---@param combinator Metaselector.Combinator
		function(combinator)
			local id = combinator.id
			local inputs = (combinator.inputs or EMPTY) --[[@as Signal[] ]]
			local combinator_entity = combinator.entity
			local surface_index = combinator_entity.surface_index
			local force_index = combinator_entity.force_index
			local machine_sig = get_tag(id, "machine") --[[@as string?]]
			local metadata = get_machine_metadata(machine_sig)
			if not metadata then
				combinator:direct_write_outputs(EMPTY)
				combinator.outputs_dirty = nil
				combinator.modal_data = nil
				combinator.input_counts = nil
				return
			end

			---@type table<SignalNumber, int32>
			local input_counts = signals_to_counts(inputs)
			local old_counts = combinator.input_counts
			combinator.input_counts = input_counts

			local state = combinator.modal_data --[[@as Metaselector.I2PState?]]
			if not state or state.machine_sig ~= machine_sig or not old_counts then
				state = {
					machine_sig = machine_sig or "",
					variant_missing = {},
					variant_active = {},
					product_refcount = {},
					changed_keys = {},
					changed_variants = {},
					delta_missing = {},
				}
				combinator.modal_data = state
				init_state(state, metadata, input_counts, surface_index, force_index)
				combinator.outputs_dirty = true
				write_outputs_from_state(combinator, state)
				return
			end

			clear_scratch(state)
			local changed_keys = state.changed_keys
			for key, new_count in pairs(input_counts) do
				if (old_counts[key] or 0) ~= new_count then
					changed_keys[#changed_keys + 1] = key
				end
			end
			for key in pairs(old_counts) do
				if input_counts[key] == nil then
					changed_keys[#changed_keys + 1] = key
				end
			end

			if #changed_keys == 0 then return end

			local requirements_by_key = metadata.requirements_by_key
			local delta_missing = state.delta_missing
			local changed_variants = state.changed_variants
			for i = 1, #changed_keys do
				local key = changed_keys[i]
				local old_count = old_counts[key] or 0
				local new_count = input_counts[key] or 0
				if old_count ~= new_count then
					local req_entries = requirements_by_key[key]
					if req_entries then
						for j = 1, #req_entries do
							local req = req_entries[j]
							local req_amount = req.req_amount
							local old_met = old_count >= req_amount
							local new_met = new_count >= req_amount
							if old_met ~= new_met then
								local variant_id = req.variant_id
								local d = delta_missing[variant_id]
								if d == nil then
									changed_variants[#changed_variants + 1] = variant_id
									delta_missing[variant_id] = old_met and 1 or -1
								else
									delta_missing[variant_id] = d + (old_met and 1 or -1)
								end
							end
						end
					end
				end
			end

			if #changed_variants == 0 then return end

			local variants = metadata.variants
			local variant_missing = state.variant_missing
			local variant_active = state.variant_active
			local product_refcount = state.product_refcount
			local output_changed = false

			for i = 1, #changed_variants do
				local variant_id = changed_variants[i]
				local delta = delta_missing[variant_id]
				if delta and delta ~= 0 then
					local variant = variants[variant_id] --[[@as Metaselector.RecipeVariant]]
					local old_missing = variant_missing[variant_id]
						or variant.required_count
					local new_missing = old_missing + delta
					variant_missing[variant_id] = new_missing

					local was_active = variant_active[variant_id] == true
					local is_active = new_missing == 0
					if is_active ~= was_active then
						if is_active then
							local recipe_number = variant.recipe_number
							if
								not can_craft_here(surface_index, recipe_number)
								or not is_researched(force_index, recipe_number)
							then
								variant_active[variant_id] = false
							else
								variant_active[variant_id] = true
								local product_number = variant.product_number
								local ref = product_refcount[product_number] or 0
								product_refcount[product_number] = ref + 1
								if ref == 0 then output_changed = true end
							end
						else
							variant_active[variant_id] = false
							local product_number = variant.product_number
							local ref = (product_refcount[product_number] or 0) - 1
							if ref <= 0 then
								product_refcount[product_number] = nil
								output_changed = true
							else
								product_refcount[product_number] = ref
							end
						end
					end
				end
			end

			if output_changed then combinator.outputs_dirty = true end
			if combinator.outputs_dirty then
				write_outputs_from_state(combinator, state)
			end
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
