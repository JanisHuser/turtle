-- Worker turtle main program (started by startup.lua).
-- Jobs are saved to disk so the turtle carries on after a server restart.
-- Right now the only jobs are "dock" and "idle"; mining and looting come next.

package.path = "/?.lua;/?/init.lua;" .. package.path

local state = require("lib.state")
local nav = require("lib.nav")
local net = require("lib.net")
local dock = require("lib.dock")

local JOB = "/.job"

nav.init()

local job = state.load(JOB, { task = "dock" })
nav.onMove = function() net.status({ task = job.task }) end

while true do
  job = state.load(JOB, { task = "dock" })
  if job.task == "dock" then
    dock.run()
    state.save(JOB, { task = "idle" })
  elseif job.task == "idle" then
    net.status({ task = "idle" }, true)
    -- Later steps: ask the coordinator for a mining/looting job here.
    sleep(30)
  else
    print("unknown job '" .. tostring(job.task) .. "', going home")
    state.save(JOB, { task = "dock" })
  end
end
