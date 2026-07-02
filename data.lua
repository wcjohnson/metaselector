-- Bootstrap Relm data phase
_G.__RELM_GRAPHICS_PATH__ = "__metaselector__/lib/core/relm/graphics/"
require("lib.core.relm.relm_data")

local data_util = require("lib.core.data-util")
local things = require("__0-things__.client.client") --[[@as things.client]]

--------------------------------------------------------------------------------
-- Entity
--------------------------------------------------------------------------------

---@type data.ArithmeticCombinatorPrototype
local combinator = data_util.copy_prototype(
	data.raw["arithmetic-combinator"]["arithmetic-combinator"],
	"metaselector-combinator"
)

---@diagnostic disable-next-line: need-check-nil
combinator.sprites.east.layers[1].filename = "__metaselector__/graphics/metaselector-combinator.png"
combinator.sprites.west.layers[1].filename = "__metaselector__/graphics/metaselector-combinator.png"
---@diagnostic disable-next-line: need-check-nil
combinator.sprites.north.layers[1].filename = "__metaselector__/graphics/metaselector-combinator.png"
combinator.sprites.south.layers[1].filename = "__metaselector__/graphics/metaselector-combinator.png"
combinator.icon = "__metaselector__/graphics/metaselector-icon.png"

data:extend({
	{ type = "custom-event", name = "metaselector-on_tags_changed" },
	{ type = "custom-event", name = "metaselector-on_initialized" },
	{ type = "custom-event", name = "metaselector-on_status" },
})

things.register({
	name = "metaselector-combinator",
	intercept_construction = true,
	custom_events = {
		on_tags_changed ="metaselector-on_tags_changed",
		on_initialized = "metaselector-on_initialized",
		on_status = "metaselector-on_status",
	},
})

--------------------------------------------------------------------------------
-- Combinator item
--------------------------------------------------------------------------------

---@type data.ItemPrototype
local item = data_util.copy_prototype(
	data.raw.item["selector-combinator"],
	"metaselector-combinator"
)
item.place_result = "metaselector-combinator"
item.icon = "__metaselector__/graphics/metaselector-icon.png"

data:extend({ item })

--------------------------------------------------------------------------------
-- Combinator recipe
--------------------------------------------------------------------------------

---@type data.RecipePrototype
local recipe = {
	type = "recipe",
	name = "metaselector-combinator",
	hidden = false,
	enabled = false,
	energy_required = 30,
	ingredients = {
		{ type = "item", name = "electronic-circuit", amount = 10 },
		{ type = "item", name = "copper-cable", amount = 5 },
	},
	results = {
		{ type = "item", name = "metaselector-combinator", amount = 1 },
	},
}

data:extend({ recipe })

--------------------------------------------------------------------------------
-- Combinator tech
--------------------------------------------------------------------------------

data_util.unlock_recipe_with_technology(
	"metaselector-combinator",
	"advanced-combinators"
)
