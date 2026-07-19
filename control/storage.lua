local events = require("lib.core.event")

---@class Metaselector.Storage
---@field public combinators table<things.Id, Metaselector.Combinator>
storage = {}

---@param k any
---@param v any?
local function init_storage_key(k, v)
	if not storage[k] then storage[k] = v or {} end
end

local function init_storage()
	if not storage then storage = {} end
	init_storage_key("combinators")
end
_G.init_storage = init_storage

events.bind("on_startup", function() init_storage() end)
