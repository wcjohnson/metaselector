-- UI for metaselector combinator

local tlib = require("lib.core.table")
local event = require("lib.core.event")
local relm = require("lib.core.relm.relm")
local ultros = require("lib.core.relm.ultros")
local relm_util = require("lib.core.relm.util")
local things_client = require("__0-things__.client.client") --[[@as things.client]]

local modes_lib = require("control.mode")
local sorted_modes = modes_lib.sorted_modes
local modes = modes_lib.modes

local Pr = relm.Primitive

local ModePicker = relm.define("ModePicker", function(props)
	local thing = things_client.represent(props.thing_id)
	local desired_mode = relm.use_result(function()
		return thing:get_tag("mode") or "none"
	end)

	local options = tlib.map(sorted_modes, function(mode)
		return { caption = mode.caption, key = mode.name }
	end)

	return ultros.Dropdown({
		options = options,
		horizontally_stretchable = true,
		value = desired_mode,
		on_change = function(me, new_mode)
			if new_mode == desired_mode then return end
			if not modes[new_mode] then return end
			thing:set_tag("mode", new_mode)
		end,
	})
end)

local ModeSettings = relm.define("ModeSettings", function(props)
	local thing = things_client.represent(props.thing_id)
	local mode_name = relm.use_result(function()
		return thing:get_tag("mode") or "none"
	end)
	local mode = modes[mode_name]
	if not mode then return ultros.Label("Invalid mode: " .. mode_name) end
	return relm.element(mode.settings_element, { thing_id = props.thing_id })
end)

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
		if ev.thing.id ~= thing_id then return end
		relm.paint(me)
	end)

	return ultros.WindowFrame({caption = "Metaselector", on_close = close_me}, {Pr({
			type = "frame",
			style = "inside_shallow_frame",
			direction = "vertical",
			vertically_stretchable = true,
			width = 400,
			minimal_height = 600,
		}, {
			Pr({
				type = "scroll-pane",
				direction = "vertical",
				vertically_stretchable = true,
				vertical_scroll_policy = "always",
				horizontal_scroll_policy = "never",
				extra_top_padding_when_activated = 0,
				extra_left_padding_when_activated = 0,
				extra_right_padding_when_activated = 0,
				extra_bottom_padding_when_activated = 0,
			}, {
				ultros.WellSection(
					{ caption = "Mode" },
					{ ModePicker({ thing_id = thing_id }) }
				),
				ModeSettings({ thing_id = thing_id }),
			}),
		})})
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
