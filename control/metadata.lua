local tlib = require("lib.core.table")
local siglib = require("lib.core.signal")
local strace = require("lib.core.strace")

local ipairs = ipairs
local pairs = pairs
local EMPTY = tlib.EMPTY

local lib = {}

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

---@class Metaselector.MachineMetadata
---@field public recipes table<string, LuaRecipePrototype> Recipes that can be crafted on this machine on this surface
---@field public recipes_by_product table<string, LuaRecipePrototype> Recipe that produces this product. "last" recipe returned by Factorio takes precedence.
---@field public variant_count integer
---@field public variants Metaselector.RecipeVariant[]
---@field public variants_by_ingredient_key table<SignalKey, integer[]>

---@class Metaselector.RecipeVariant
---@field public recipe LuaRecipePrototype
---@field public quality string
---@field public product SignalID
---@field public required_count integer
---@field public required_keys SignalKey[]
---@field public required_amounts integer[]

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

---@type table<string, table<int, Metaselector.MachineMetadata>>
local _machine_metadata = {}

---@param machine_name string?
---@param surface LuaSurface?
---@return Metaselector.MachineMetadata?
function lib.get_machine_metadata(machine_name, surface)
	if not machine_name or not surface then return end
	local surface_index = surface.index
	local by_name = _machine_metadata[machine_name]
	if by_name then
		local by_index = by_name[surface_index]
		if by_index then return by_index end
	else
		by_name = {}
		_machine_metadata[machine_name] = by_name
	end

	local recipes = {}
	local recipes_by_product = {}
	---@type Metaselector.RecipeVariant[]
	local variants = {}
	---@type table<SignalKey, integer[]>
	local variants_by_ingredient_key = {}
	---@type Metaselector.MachineMetadata
	local metadata = {
		recipes = recipes,
		recipes_by_product = recipes_by_product,
		variant_count = 0,
		variants = variants,
		variants_by_ingredient_key = variants_by_ingredient_key,
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
		if not can_craft_here(surface, recipe) then goto continue end
		recipes[name] = recipe
		local main_product = recipe.main_product
		if main_product then recipes_by_product[main_product.name] = recipe end

		local ingredients = recipe.ingredients or EMPTY
		if main_product and #ingredients > 0 then
			local product_type = main_product.type or "item"
			for _, quality_name in ipairs(quality_names) do
				---@type SignalID
				local product = {
					type = product_type,
					name = main_product.name,
					quality = product_type == "item" and quality_name or "normal",
				}

				---@type SignalKey[]
				local required_keys = {}
				---@type integer[]
				local required_amounts = {}
				for _, ingredient in ipairs(ingredients) do
					local ingredient_type = ingredient.type or "item"
					required_keys[#required_keys + 1] = siglib.encode_signal_key(
						ingredient.name,
						ingredient_type,
						ingredient_type == "item" and quality_name or "normal"
					)
					required_amounts[#required_amounts + 1] = math.ceil(ingredient.amount)
				end

				local variant_id = #variants + 1
				variants[variant_id] = {
					recipe = recipe,
					quality = quality_name,
					product = product,
					required_count = #required_keys,
					required_keys = required_keys,
					required_amounts = required_amounts,
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

	metadata.variant_count = #variants

	by_name[surface_index] = metadata
	return metadata
end

return lib
