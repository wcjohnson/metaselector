local strace = require("lib.core.strace")
local relm = require("lib.core.relm.relm")
local event = require("lib.core.event")
require("lib.core.debug-log") -- for debug_crash

relm.bootstrap_with_core_events(event)

strace.set_handler(strace.standard_log_handler)

require("control.storage")
require("control.combinator")
require("control.mode")

require("control.modes.product-to-ingredients")
require("control.modes.ingredients-to-products")

require("control.ui.combinator")
