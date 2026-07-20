local tlib = require("lib.core.table")
local strace = require("lib.core.strace")
local events = require("lib.core.event")

local signal_numbers = require("__signal-numbers__.signal-numbers") --[[@as SignalNumbers.Lib]]

local ipairs = ipairs
local pairs = pairs
local EMPTY = tlib.EMPTY
local exploded_signal_to_number = signal_numbers.exploded_signal_to_number
local number_to_signal = signal_numbers.number_to_signal
local JUST_NORMAL = { "normal" }

local lib = {}

---@class Metaselector.MachineMetadata
---@field public recipes table<string, LuaRecipePrototype> Recipes that can be crafted on this machine on this surface
---@field public recipes_by_product table<string, LuaRecipePrototype> Recipe that produces this product. "last" recipe returned by Factorio takes precedence.
---@field public variant_count integer
---@field public variants Metaselector.RecipeVariant[]
---@field public variants_by_ingredient_key table<SignalNumber, integer[]>
---@field public variants_by_pivot_key table<SignalNumber, integer[]>

---@class Metaselector.RecipeVariant
---@field public recipe LuaRecipePrototype
---@field public recipe_number SignalNumber
---@field public quality string
---@field public product SignalID
---@field public product_number SignalNumber
---@field public required_count integer
---@field public required_keys SignalNumber[]
---@field public required_amounts integer[]
---@field public pivot_key SignalNumber

-- XXX: MP SAFETY: Pure function of prototypes
---@type string[]?
local _quality_names

---@return string[]
local function get_quality_names()
	if _quality_names then return _quality_names end
	---@type string[]
	local quality_names = {}
	for quality_name in pairs(prototypes.quality or EMPTY) do
		quality_names[#quality_names + 1] = quality_name
	end
	if #quality_names == 0 then quality_names[1] = "normal" end
	table.sort(quality_names)
	_quality_names = quality_names
	return quality_names
end

-- XXX: MP SAFETY: Pure function of prototypes
---@type table<string, Metaselector.MachineMetadata>
local _machine_metadata = {}

---@param machine_name string?
---@return Metaselector.MachineMetadata?
function lib.get_machine_metadata(machine_name)
	if not machine_name then return end
	local by_name = _machine_metadata[machine_name]
	if by_name then return by_name end

	local recipes = {}
	local recipes_by_product = {}
	---@type Metaselector.RecipeVariant[]
	local variants = {}
	---@type table<SignalNumber, integer[]>
	local variants_by_ingredient_key = {}
	---@type table<SignalNumber, integer[]>
	local variants_by_pivot_key = {}
	---@type Metaselector.MachineMetadata
	local metadata = {
		recipes = recipes,
		recipes_by_product = recipes_by_product,
		variant_count = 0,
		variants = variants,
		variants_by_ingredient_key = variants_by_ingredient_key,
		variants_by_pivot_key = variants_by_pivot_key,
	}

	local mproto = prototypes.entity[machine_name]
	if not mproto then return end

	local filters = {}
	for category in pairs(mproto.crafting_categories or EMPTY) do
		filters[#filters + 1] = { filter = "category", category = category }
	end

	local fr = prototypes.get_recipe_filtered(filters)
	local quality_names = get_quality_names()
	for name, recipe in pairs(fr) do
		if recipe.hidden then goto continue end
		local recipe_number = exploded_signal_to_number("recipe", name) --[[@as SignalNumber]]
		recipes[name] = recipe
		local main_product = recipe.main_product
		if main_product then recipes_by_product[main_product.name] = recipe end

		local ingredients = recipe.ingredients or EMPTY
		if main_product and #ingredients > 0 then
			local product_type = main_product.type or "item"
			local iter_quality_names = (
				recipe.can_set_quality and quality_names or JUST_NORMAL
			) --[[@as string[] ]]
			for _, quality_name in ipairs(iter_quality_names) do
				local product_quality = product_type == "item" and quality_name
					or "normal"
				---@type SignalID
				local product = {
					type = product_type,
					name = main_product.name,
					quality = product_quality,
				}
				local product_number = exploded_signal_to_number(
					product_type,
					main_product.name,
					product_quality
				) --[[@as SignalNumber]]

				---@type SignalNumber[]
				local required_keys = {}
				---@type integer[]
				local required_amounts = {}
				for _, ingredient in ipairs(ingredients) do
					local ingredient_type = ingredient.type or "item"
					required_keys[#required_keys + 1] = exploded_signal_to_number(
						ingredient_type,
						ingredient.name,
						ingredient_type == "item" and quality_name or "normal"
					)
					required_amounts[#required_amounts + 1] = math.ceil(ingredient.amount)
				end

				local variant_id = #variants + 1
				variants[variant_id] = {
					recipe = recipe,
					recipe_name = name,
					recipe_number = recipe_number,
					quality = quality_name,
					product = product,
					product_number = product_number,
					required_count = #required_keys,
					required_keys = required_keys,
					required_amounts = required_amounts,
					pivot_key = required_keys[1] --[[@as SignalNumber]],
				}
				for i = 1, #required_keys do
					local key = required_keys[i]
					local recipe_ids = variants_by_ingredient_key[key]
					if recipe_ids then
						recipe_ids[#recipe_ids + 1] = variant_id
					else
						variants_by_ingredient_key[key] = { variant_id }
					end
				end
			end
		end
		::continue::
	end

	for variant_id = 1, #variants do
		local variant = variants[variant_id]
		local required_keys = variant.required_keys
		local required_amounts = variant.required_amounts

		-- Reorder checks to fail fast: larger required amounts first, then rarer keys.
		for i = 1, variant.required_count - 1 do
			local best = i
			local best_amount = required_amounts[i]
			local best_len = #(variants_by_ingredient_key[required_keys[i]] or EMPTY)
			for j = i + 1, variant.required_count do
				local amount = required_amounts[j]
				if amount > best_amount then
					best = j
					best_amount = amount
					best_len = #(variants_by_ingredient_key[required_keys[j]] or EMPTY)
				elseif amount == best_amount then
					local key_len = #(
						variants_by_ingredient_key[required_keys[j]] or EMPTY
					)
					if key_len < best_len then
						best = j
						best_len = key_len
					end
				end
			end
			if best ~= i then
				required_keys[i], required_keys[best] =
					required_keys[best], required_keys[i]
				required_amounts[i], required_amounts[best] =
					required_amounts[best], required_amounts[i]
			end
		end

		local pivot_key = required_keys[1]
		local pivot_len = #(variants_by_ingredient_key[pivot_key] or EMPTY)
		for i = 2, variant.required_count do
			local key = required_keys[i]
			local key_len = #(variants_by_ingredient_key[key] or EMPTY)
			if key_len < pivot_len then
				pivot_key = key
				pivot_len = key_len
			end
		end
		variant.pivot_key = pivot_key
		local pivot_variants = variants_by_pivot_key[pivot_key]
		if pivot_variants then
			pivot_variants[#pivot_variants + 1] = variant_id
		else
			variants_by_pivot_key[pivot_key] = { variant_id }
		end
	end

	metadata.variant_count = #variants

	_machine_metadata[machine_name] = metadata
	return metadata
end

--------------------------------------------------------------------------------
-- SURFACE CONDITIONS
--------------------------------------------------------------------------------

---@param surface LuaSurface
---@param recipe LuaRecipePrototype
local function can_craft_here(surface, recipe)
	if surface.ignore_surface_conditions then return true end
	for _, sc in ipairs(recipe.surface_conditions or EMPTY) do
		local value = surface.get_property(sc.property) or 0
		if value < sc.min or value > sc.max then return false end
	end
	return true
end

---@param surface_index integer
---@param recipe_number SignalNumber
---@return boolean
function lib.can_craft_here(surface_index, recipe_number)
	-- Cache hit
	local cache = storage.can_craft_here[surface_index]
	if not cache then
		cache = {}
		storage.can_craft_here[surface_index] = cache
	end
	local cached = cache[recipe_number]
	if cached ~= nil then return cached end

	-- Cache miss
	local surface = game.get_surface(surface_index)
	if not surface then return false end
	local recipe = number_to_signal(recipe_number)
	if not recipe then
		error(
			"LOGIC ERROR: signal number "
				.. recipe_number
				.. " does not correspond to a recipe prototype"
		)
		return false
	end
	local recipe_proto = prototypes.recipe[recipe.name]
	if not recipe_proto then
		error(
			"LOGIC ERROR: signal number "
				.. recipe_number
				.. " does not correspond to a recipe prototype"
		)
		return false
	end
	local result = can_craft_here(surface, recipe_proto)
	cache[recipe_number] = result
	return result
end

--------------------------------------------------------------------------------
-- RESEARCH
--------------------------------------------------------------------------------

events.bind(
	defines.events.on_technology_effects_reset,
	---@param ev EventData.on_technology_effects_reset
	function(ev) storage.recipe_enabled[ev.force.index] = {} end
)

events.bind(
	defines.events.on_force_reset,
	function(ev) storage.recipe_enabled[ev.force.index] = {} end
)

events.bind(
	defines.events.on_research_finished,
	---@param ev EventData.on_research_finished
	function(ev)
		local force = ev.research.force --[[@as LuaForce]]
		local force_index = force.index
		storage.recipe_enabled[force_index] = {}
	end
)

events.bind(defines.events.on_research_reversed, function(ev)
	local force = ev.research.force --[[@as LuaForce]]
	local force_index = force.index
	storage.recipe_enabled[force_index] = {}
end)

function lib.is_researched(force_index, recipe_number)
	local cache = storage.recipe_enabled[force_index]
	if not cache then
		cache = {}
		storage.recipe_enabled[force_index] = cache
	end
	local cached = cache[recipe_number]
	if cached ~= nil then return cached end

	local force = game.forces[force_index] --[[@as LuaForce]]
	if not force then return false end
	local recipe = number_to_signal(recipe_number)
	if not recipe then return false end
	local researched = force.recipes[recipe.name].enabled
	cache[recipe_number] = researched
	return researched
end

return lib
