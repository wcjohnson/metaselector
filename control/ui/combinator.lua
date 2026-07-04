-- UI for metaselector combinator

local event = require("lib.core.event")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")

relm.define("MetaselectorUi", function(props)
	local root_id = props.root_id
	local player_index = props.player_index
	local thing_id = props.thing_id

	-- Window management
	local function close_me() relm.root_destroy(root_id) end
	ultros.use_auto_center_on_open()
	ultros.use_close_on_gui_closed(player_index, close_me, false)
	ultros.use_player_opened(player_index)

	-- Repaint
	relm_util.use_event_handler("metaselector-on_tags_changed", function(me, _, ev)
		if ev.thing_id ~= thing_id then return end
		relm.paint(me)
	end)

	return ultros.WindowFrame({caption = "Metaselector", on_close = close_me}, {})
end)

---@param player LuaPlayer
---@param thing_id uint
function open_combinator_ui(player, thing_id)
	-- Already open
	if player.gui.screen["MetaselectorUi"] then return end
	relm.root_create(
		player.gui.screen,
		"MetaselectorUi",
		"MetaselectorUi",
		{ thing_id = thing_id }
	)
end

event.bind(defines.events.on_gui_opened, function(ev)
	local player = game.get_player(ev.player_index)
	if not player then return end

	local selected = ev.entity --[[@as LuaEntity?]]
	if not selected then return end
	if selected.name ~= "metaselector-combinator" then return end

	-- Close any existing ui
	player.opened = nil

	local _, thing_id = remote.call("things", "get_thing_id", selected)
	if not thing_id then return end

	open_combinator_ui(player, thing_id)
end)
