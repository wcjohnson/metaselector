local events = require("lib.core.event")

---@class Metaselector.Storage
---@field public combinators table<things.Id, Metaselector.Combinator>
---@field public recipe_enabled table<int, table<SignalNumber, boolean>>
---@field public can_craft_here table<int, table<SignalNumber, boolean>>
storage = {}

---@param k any
---@param v any?
local function init_storage_key(k, v)
	if not storage[k] then storage[k] = v or {} end
end

local function init_storage()
	if not storage then storage = {} end
	init_storage_key("combinators")
	init_storage_key("recipe_enabled")
	init_storage_key("can_craft_here")
end
_G.init_storage = init_storage

events.bind("on_startup", function() init_storage() end)
