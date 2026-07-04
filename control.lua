local strace = require("lib.core.strace")
local relm = require("lib.core.relm.relm")
local event = require("lib.core.event")
require("lib.core.debug-log") -- for debug_crash

relm.bootstrap_with_core_events(event)

strace.set_handler(strace.standard_log_handler)

require("control.mode")

require("control.modes.item-to-ingredients")

require("control.ui.combinator")
