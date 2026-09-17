-- Station service: fly home, wait for the bay, unload, refuel, leave.
--
--   side view (bayFacing = east):
--
--     y+1   [FUEL  ][CRAFTER]    crafter faces west into FUEL
--     y     [ BAY  ][ COAL  ]    worker faces east into COAL
--     y-1   [PICKUP]
--
-- Safe to call again after a reboot from anywhere: it works out which phase
-- it was in from the turtle's position.

local config = require("config")
local nav = require("lib.nav")
local net = require("lib.net")
local inv = require("lib.inv")

local M = {}

local st = config.station

local function offset(p, dirName)
  local d = nav.DIRS[nav.HEADING[dirName]]
  return { x = p.x + d[1], y = p.y, z = p.z + d[2] }
end

local function say(task, text)
  print(text)
  net.status({ task = task, note = text }, true)
end

-- Keep retrying a movement; the station area should clear up by itself
-- (another turtle moving away) or the player has to fix it.
local function retry(what, fn)
  while true do
    local ok, err = fn()
    if ok then return end
    say("dock", what .. " failed: " .. tostring(err) .. " - retrying")
    sleep(5)
  end
end

local function renewLock()
  return net.request({ type = "bay_request" }, 3)
end

local function acquireLock()
  while true do
    local reply = renewLock()
    if not reply then
      print("dock: no coordinator answered, entering without a bay lock")
      return
    end
    if reply.granted then return end
    say("waiting", ("waiting for bay, position %d in queue"):format(reply.queue or 0))
    sleep(5)
  end
end

local function unload()
  inv.eachCargo(function(slot, d)
    turtle.select(slot)
    local toCoal = config.coalItems[d.name]
    while turtle.getItemCount(slot) > 0 do
      if toCoal then
        -- COAL barrel full -> put the rest in PICKUP instead
        if not turtle.drop() then toCoal = false end
      elseif not turtle.dropDown() then
        say("dock", "PICKUP barrel is full, waiting")
        renewLock()
        sleep(10)
      end
    end
  end)
  turtle.select(1)
end

local function refuel()
  local target = math.min(config.fuel.target, turtle.getFuelLimit())
  while turtle.getFuelLevel() < target do
    local slot = inv.freeSlot()
    if not slot then break end
    turtle.select(slot)
    local want = math.max(1, math.min(64, math.ceil((target - turtle.getFuelLevel()) / 800)))
    if turtle.suckUp(want) then
      if turtle.refuel(0) then
        turtle.refuel()
      else
        turtle.dropDown() -- something that isn't fuel ended up in FUEL
      end
    elseif turtle.getFuelLevel() >= config.fuel.minToLeave then
      break
    else
      say("dock", ("FUEL barrel empty, fuel %d - waiting"):format(turtle.getFuelLevel()))
      renewLock()
      sleep(15)
    end
  end
  turtle.select(1)
end

-- Make sure we can get to `cost` blocks away, burning carried fuel if needed.
function M.ensureFuel(cost)
  local need = cost + config.fuel.reserve
  if turtle.getFuelLevel() >= need then return true end
  if inv.refuelFromInventory(need) then return true end
  say("dock", ("low fuel: have %d, need %d"):format(turtle.getFuelLevel(), need))
  return false
end

function M.park()
  local cy = nav.cruiseY()
  M.ensureFuel(nav.travelCost(st.park.x, cy, st.park.z))
  retry("flying to park", function() return nav.travelTo(st.park.x, cy, st.park.z) end)
end

function M.run()
  local bay = st.bay
  local cy = nav.cruiseY()
  local entry, exit = offset(bay, st.entry), offset(bay, st.exit)
  local p = nav.pos()
  local atBay = p.x == bay.x and p.y == bay.y and p.z == bay.z
  local inEntry = p.x == entry.x and p.z == entry.z and p.y >= bay.y and p.y < cy
  local inExit = p.x == exit.x and p.z == exit.z and p.y >= bay.y and p.y < cy

  if not atBay and not inExit then
    if not inEntry then
      M.park()
    end
    say("dock", "requesting bay")
    acquireLock()
    if not inEntry then
      retry("flying to entry", function() return nav.moveTo(entry.x, cy, entry.z) end)
    end
    retry("descending", function() return nav.moveTo(entry.x, bay.y, entry.z) end)
    retry("entering bay", function() return nav.moveTo(bay.x, bay.y, bay.z) end)
    atBay = true
  elseif atBay then
    acquireLock()
  end

  if atBay then
    nav.face(st.bayFacing)
    say("dock", "unloading")
    unload()
    say("dock", "refuelling")
    refuel()
    retry("leaving bay", function() return nav.moveTo(exit.x, bay.y, exit.z) end)
  end

  net.request({ type = "bay_release" }, 2)
  retry("climbing out", function() return nav.moveTo(exit.x, cy, exit.z) end)
  M.park()
  say("idle", ("docked, fuel %d"):format(turtle.getFuelLevel()))
end

return M
