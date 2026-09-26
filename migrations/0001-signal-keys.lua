-- Invalidate persisted data that depends on SignalKey encoding.
-- This migration runs once for saves that have not applied it.

if not storage then return end

-- These are pure caches keyed by SignalKey; they repopulate on cache miss.
storage.recipe_enabled = {}
storage.can_craft_here = {}

-- Per-combinator incremental state also stores SignalKey-indexed maps.
-- Clear only the affected fields so state is rebuilt on next script update.
local combinators = storage.combinators
if combinators then
	for _, combinator in pairs(combinators) do
		combinator.input_counts = nil
		combinator.modal_data = nil
	end
end
