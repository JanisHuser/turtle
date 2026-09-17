-- Send this turtle home: fly to the station, unload, refuel, park.
-- Usage: home

package.path = "/?.lua;/?/init.lua;" .. package.path

local state = require("lib.state")
local nav = require("lib.nav")
local dock = require("lib.dock")

nav.init()
state.save("/.job", { task = "dock" })
dock.run()
state.save("/.job", { task = "idle" })
