local tlib = require("lib.core.table")
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
	---@type Metaselector.MachineMetadata
	local metadata =
		{ recipes = recipes, recipes_by_product = recipes_by_product }

	local mproto = prototypes.entity[machine_name]
	if not mproto then return end

	local filters = {}
	for category in pairs(mproto.crafting_categories or EMPTY) do
		filters[#filters + 1] = { filter = "category", category = category }
	end

	local fr = prototypes.get_recipe_filtered(filters)
	for name, recipe in pairs(fr) do
		if not can_craft_here(surface, recipe) then goto continue end
		recipes[name] = recipe
		local main_product = recipe.main_product
		if main_product then recipes_by_product[main_product.name] = recipe end
		::continue::
	end

	by_name[surface_index] = metadata
	return metadata
end

return lib
