local class = require("lib.core.class").class
local things_client = require("__0-things__.client.client") --[[@as things.client]]
local events = require("lib.core.event")
local tlib = require("lib.core.table")
local mode_lib = require("control.mode")
local strace = require("lib.core.strace")

local get_tag = things_client.tags_v1.get_tag
local set_tag = things_client.tags_v1.set_tag
local get_child = things_client.parent_child_v1.get_child
local arm_trigger = things_client.triggers_v1.arm_trigger
local create_circuit_change_detector =
	things_client.triggers_v1.create_circuit_change_detector
local destroy_circuit_change_detector =
	things_client.triggers_v1.destroy_circuit_change_detector
local modes = mode_lib.modes

local EMPTY = tlib.EMPTY
local I_RED = defines.wire_connector_id.combinator_input_red
local I_GREEN = defines.wire_connector_id.combinator_input_green
local O_RED = defines.wire_connector_id.combinator_output_red
local O_GREEN = defines.wire_connector_id.combinator_output_green
local NO_NETWORKS = { red = false, green = false }
local ALWAYS_DECIDER_CONDITIONS = {
	{
		comparator = "=",
		first_signal = nil,
		second_signal = nil,
		compare_type = "or",
		first_signal_networks = NO_NETWORKS,
		second_signal_networks = NO_NETWORKS,
	},
	{
		comparator = "=",
		first_signal = nil,
		second_signal = nil,
		compare_type = "or",
		first_signal_networks = NO_NETWORKS,
		second_signal_networks = NO_NETWORKS,
	},
}

local lib = {}

---@class Metaselector.Combinator
---@field public id things.Id Thing ID of this combinator
---@field public entity ValidEntity The real entity of this combinator
---@field public mode string The current mode of this combinator
---@field public trigger_id? things.Id Things trigger ID if a trigger is associated with this combinator
---@field public dirty? true If `true`, the combinator's inputs need to be re-read.
---@field public inputs? Signal[] The cached input signals of this combinator, if any
---@field public input_counts? table<SignalNumber, int32> The cached input signal counts of this combinator, if any
---@field public outputs_dirty? true If `true`, the combinator's outputs need to be re-written.
---@field public last_read_tick? int64 The last tick at which the inputs were read
---@field public modal_data? Any Mode-specific data for this combinator, if any
Combinator = class("Metaselector.Combinator")
lib.Combinator = Combinator

---@param id things.Id
---@param entity ValidEntity
function Combinator:new(id, entity)
	local o = {}
	setmetatable(o, self)
	o.id = id
	o.entity = entity
	local beh = entity.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]
	beh.parameters = {
		outputs = EMPTY,
		conditions = ALWAYS_DECIDER_CONDITIONS,
		else_outputs = EMPTY,
	}
	o.mode = get_tag(id, "mode") or "none"
	storage.combinators[id] = o
	return o --[[@as Metaselector.Combinator]]
end

function Combinator:set_mode(new_mode, suppress_retag)
	if new_mode == self.mode then return end
	if not modes[new_mode] then return end
	strace.trace("Combinator:set_mode id", self.id, "new_mode", new_mode)
	self.mode = new_mode
	if not suppress_retag then set_tag(self.id, "mode", new_mode) end
	self:check_detector()
	self.inputs = nil
	self.input_counts = nil
	self.outputs_dirty = true
	self.modal_data = nil
	self:direct_write_outputs(EMPTY)
	self:set_inputs_dirty()
end

function Combinator:read_inputs(which, workload)
	local mode = modes[self.mode]
	if not mode.script_inputs then return end

	-- Sanity checks
	-- Don't read invalid entities or ghosts
	local entity = self.entity
	if not entity or not entity.valid then
		self.inputs = nil
		self.dirty = nil
		return
	end
	-- Don't reread if clean
	if not self.dirty then return end
	-- Don't read inputs more than once per tick.
	local now = game.tick
	if now - (self.last_read_tick or 0) < 1 then
		-- Keep the detector armed even when deferring the read to next tick.
		if self.trigger_id then arm_trigger(self.trigger_id, true) end
		return
	end
	self.last_read_tick = now
	self.dirty = nil
	-- Re-arm the circuit change detector if one is attached
	if self.trigger_id then arm_trigger(self.trigger_id, true) end

	local signals = entity.get_signals(I_RED, I_GREEN)
	if signals then
		self.inputs = signals
	else
		self.inputs = {}
	end
	strace.trace("Combinator:read_inputs id", self.id, "inputs", self.inputs)
end

---Directly replace the combinator's raw outputs.
---@param outputs DeciderCombinatorOutput[]
function Combinator:direct_write_outputs(outputs)
	local entity = self.entity
	if not entity or not entity.valid then return end
	local beh = entity.get_or_create_control_behavior() --[[@as LuaDeciderCombinatorControlBehavior]]
	local param = beh.parameters
	if not param then
		param = {
			outputs = outputs,
			conditions = ALWAYS_DECIDER_CONDITIONS,
			else_outputs = EMPTY,
		}
	else
		param.outputs = outputs
	end
	beh.parameters = param
end

function Combinator:check_detector()
	local id = self.id
	local entity = self.entity
	self.dirty = true
	local child = get_child(id, "_trigger")
	local mode = modes[self.mode]

	if mode.script_inputs then
		if child then
			strace.trace(
				"Combinator:check_detector id",
				id,
				"detector already exists"
			)
			local trigger_id = child
				.entity--[[@cast -?]]
				.unit_number
			arm_trigger(trigger_id, true)
			self.trigger_id = trigger_id
			return
		end

		local r_comb_in = entity.get_wire_connector(I_RED, true)
		local g_comb_in = entity.get_wire_connector(I_GREEN, true)
		local trigger_id =
			create_circuit_change_detector(id, "", r_comb_in, g_comb_in)
		self.trigger_id = trigger_id
		strace.trace(
			"Combinator:check_detector id",
			id,
			"detector created with trigger_id",
			trigger_id
		)
	else
		destroy_circuit_change_detector(id, "")
		self.trigger_id = nil
	end
end

function Combinator:set_inputs_dirty()
	local mode = modes[self.mode]
	if not mode.script_inputs then return end
	strace.trace("Combinator:set_inputs_dirty id", self.id)
	self.dirty = true
	self:read_inputs()
	local su = mode.script_update
	if su then su(self) end
end

function Combinator:script_update()
	local mode = modes[self.mode]
	if not mode.script_inputs then return end
	local su = mode.script_update
	if su then su(self) end
end

function Combinator:destroy() storage.combinators[self.id] = nil end

events.bind(
	"metaselector-on_tags_changed",
	---@param ev things.EventData.on_tags_changed
	function(ev)
		local comb = storage.combinators[ev.thing.id]
		if not comb then return end
		comb:set_mode(ev.new_tags.mode or "none", true)
		comb:script_update()
	end
)

events.bind(
	"metaselector-on_initialized",
	---@param ev things.EventData.on_initialized
	function(ev)
		strace.trace("Combinator:on_initialized", ev)
		if ev.status == "real" then
			local comb = Combinator:new(ev.id, ev.entity --[[@as ValidEntity]])
			comb:check_detector()
			comb:set_inputs_dirty()
		end
	end
)

events.bind(
	"metaselector-on_status",
	---@param ev things.EventData.on_status
	function(ev)
		strace.trace("Combinator:on_status", ev)
		if ev.new_status == "real" then
			local comb = storage.combinators[ev.thing.id]
			if comb then
				comb.entity = ev.thing.entity --[[@as ValidEntity]]
			else
				comb =
					Combinator:new(ev.thing.id, ev.thing.entity --[[@as ValidEntity]])
			end
			comb:check_detector()
			comb:set_inputs_dirty()
		elseif ev.old_status == "real" then
			local comb = storage.combinators[ev.thing.id]
			if comb then comb:destroy() end
		end
	end
)

events.bind(
	"metaselector-on_trigger",

	---@param event things.EventData.on_trigger
	function(event)
		strace.trace("Combinator:on_trigger", event)
		local thing_id = event.thing_id
		local combinator = storage.combinators[thing_id]
		if not combinator then return end
		-- Suppress trigger till cleaned
		arm_trigger(event.trigger_id, false)
		-- Mark dirty
		combinator:set_inputs_dirty()
	end
)

return lib
