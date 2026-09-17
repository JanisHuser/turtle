-- Single turtle miner: coal + prosperity shards.
--
-- Needs a pickaxe and a geo scanner equipped. No GPS, modem or chunk loader:
-- it only works while you are close enough for its chunks to be loaded.
-- When you come back it continues where it stopped.
--
-- Home: the turtle's place in the bay. PICKUP container on its left, COAL
-- container on its right. The shaft is dug straight up/down behind it.
--
-- Usage: miner          start / continue
--        miner reset    forget progress and mine the area again

package.path = "/?.lua;/?/init.lua;" .. package.path

local config = require("config")
local state = require("lib.state")
local nav = require("lib.nav")
local inv = require("lib.inv")

local STATE = "/.miner"
local cfg = config.miner

if arg[1] == "reset" then
  state.clear(STATE)
  print("Miner progress cleared.")
  return
end

local home = settings.get("swarm.home")
if not home then error("miner: run 'setup miner' first") end

local scanner = peripheral.find("geoScanner")
if not scanner then error("miner: no geo scanner equipped") end

local H = nav.HEADING[home.facing]
local LEFT, RIGHT, BACK = (H + 3) % 4, (H + 1) % 4, (H + 2) % 4
local back = nav.DIRS[BACK]
local dist = cfg.shaftDistance
local shaft = { x = home.x + back[1] * dist, z = home.z + back[2] * dist }

local P = cfg.protect
local TOP, BOTTOM = home.y + P.above + 1, home.y - P.below - 1

local function atShaft(x, z) return x == shaft.x and z == shaft.z end

-- Home and the straight corridor from home to the shaft (at home height).
local function inCorridor(x, y, z)
  if y ~= home.y then return false end
  for i = 0, dist do
    if x == home.x + back[1] * i and z == home.z + back[2] * i then return true end
  end
  return false
end

-- Your base: a box around home the turtle never digs into (except the
-- corridor and the shaft).
nav.protect = function(x, y, z)
  if atShaft(x, z) or inCorridor(x, y, z) then return false end
  return math.abs(x - home.x) <= P.radius and math.abs(z - home.z) <= P.radius
    and y >= home.y - P.below and y <= home.y + P.above
end

-- -1 below the base's height band, 1 above it, 0 inside it.
local function band(y)
  if y > home.y + P.above then return 1 end
  if y < home.y - P.below then return -1 end
  return 0
end

-- Scan points: a square spiral around the shaft.
local CELLS = { { 0, 0 } }
for r = 1, cfg.rings do
  for i = -r, r do CELLS[#CELLS + 1] = { i, -r } end
  for j = -r + 1, r do CELLS[#CELLS + 1] = { r, j } end
  for i = r - 1, -r, -1 do CELLS[#CELLS + 1] = { i, r } end
  for j = r - 1, -r + 1, -1 do CELLS[#CELLS + 1] = { -r, j } end
end

local st

local function save() state.save(STATE, st) end

local function manhattan(a, b)
  return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

-- Height at which to fly horizontally to the shaft from p.
local function shaftY(p)
  if band(p.y) ~= 0 then return p.y end
  return p.y >= home.y and TOP or BOTTOM
end

-- Fuel needed to get from p back home (through the shaft).
local function homeCost(p)
  if inCorridor(p.x, p.y, p.z) then return manhattan(p, home) end
  if atShaft(p.x, p.z) then return math.abs(p.y - home.y) + dist end
  local sy = shaftY(p)
  return math.abs(p.y - sy) + math.abs(p.x - shaft.x) + math.abs(p.z - shaft.z)
    + math.abs(sy - home.y) + dist
end

-- Keep trying; tell the player what's wrong.
local function retry(what, fn)
  while true do
    local ok, err = fn()
    if ok then return end
    print(what .. " failed: " .. tostring(err) .. " - retrying in 10s")
    sleep(10)
  end
end

local function isKept(name)
  for _, pattern in ipairs(cfg.keep) do
    if name:find(pattern) then return true end
  end
  return false
end

-- Throw away everything that isn't wanted or fuel.
local function purge()
  inv.eachCargo(function(slot, d)
    if not isKept(d.name) and not config.fuel.items[d.name] then
      turtle.select(slot)
      if not turtle.dropUp() then turtle.drop() end
    end
  end)
  turtle.select(1)
end

-- Run moves in order, stop at the first failure.
local function path(...)
  for _, t in ipairs({ ... }) do
    local ok, err = nav.moveTo(t[1], t[2], t[3])
    if not ok then return false, err end
  end
  return true
end

-- Walk from anywhere to (x, y, z) without cutting through the base:
-- leave home through the corridor and shaft, and only cross the base's
-- height band vertically, outside the protected box or inside the shaft.
local function goTo(x, y, z)
  local p = nav.pos()
  if inCorridor(p.x, p.y, p.z) then
    if inCorridor(x, y, z) then return nav.moveTo(x, y, z) end
    local ok, err = nav.moveTo(shaft.x, home.y, shaft.z)
    if not ok then return false, err end
    p = nav.pos()
  end

  if atShaft(p.x, p.z) then
    if atShaft(x, z) then return nav.moveTo(x, y, z) end
    local sy = band(y) ~= 0 and y or (y >= home.y and TOP or BOTTOM)
    return path({ shaft.x, sy, shaft.z }, { x, sy, z }, { x, y, z })
  end

  local from, to = band(p.y), band(y)
  if from ~= 0 and to ~= 0 and from ~= to then
    -- other side of the base: through the shaft
    return path({ shaft.x, p.y, shaft.z }, { shaft.x, y, shaft.z }, { x, y, z })
  end
  local sy
  if from ~= 0 then sy = p.y
  elseif to ~= 0 then sy = y
  else sy = y >= home.y and TOP or BOTTOM end
  return path({ p.x, sy, p.z }, { x, sy, z }, { x, y, z })
end

local function goHome()
  local p = nav.pos()
  if not inCorridor(p.x, p.y, p.z) then
    if not atShaft(p.x, p.z) then
      local sy = shaftY(p)
      retry("going to shaft", function() return path({ p.x, sy, p.z }, { shaft.x, sy, shaft.z }) end)
    end
    purge() -- also after a restart that happened right at the shaft
    retry("using shaft", function() return nav.moveTo(shaft.x, home.y, shaft.z) end)
  end
  retry("going home", function() return nav.moveTo(home.x, home.y, home.z) end)
  nav.face(H)
end

-- True if we should go home now. `extra` = fuel for the planned trip.
local function needHome(extra)
  if inv.freeSlots() < 4 then purge() end
  if inv.freeSlots() < 2 then return true, "inventory full" end
  local need = homeCost(nav.pos()) + (extra or 0) + cfg.fuelReserve
  if turtle.getFuelLevel() < need then inv.refuelFromInventory(need + 800) end
  if turtle.getFuelLevel() < need then return true, "low fuel" end
  return false
end

-- Fuel for the longest trip: home -> farthest scan point on the deepest level -> home.
local function minFuel()
  local depth = 0
  for _, y in ipairs(cfg.levels) do depth = math.max(depth, math.abs(y - home.y)) end
  local far = cfg.rings * cfg.cellSize * 2 + depth + P.above + P.below + dist
  return 2 * far + 4 * cfg.scanRadius * 3 + cfg.fuelReserve
end

local function service()
  -- Right: refuel from the COAL container, then store the mined coal there.
  -- Mined coal is only burned if the container has no fuel for us.
  nav.face(RIGHT)
  local target = math.min(cfg.fuelTarget, turtle.getFuelLimit())
  while true do
    while turtle.getFuelLevel() < target do
      local slot = inv.freeSlot()
      if not slot then break end
      turtle.select(slot)
      if not turtle.suck(math.max(1, math.min(64, math.ceil((target - turtle.getFuelLevel()) / 800)))) then break end
      if turtle.refuel(0) then
        turtle.refuel()
        -- a leftover partial stack goes back
        if turtle.getItemCount(slot) > 0 then turtle.drop() end
      end
    end
    if turtle.getFuelLevel() < minFuel() then inv.refuelFromInventory(minFuel()) end
    if turtle.getFuelLevel() >= minFuel() then break end
    print(("Need fuel: %d/%d. Put coal or coal blocks into the right container."):format(
      turtle.getFuelLevel(), minFuel()))
    sleep(30)
  end
  inv.eachCargo(function(slot, d)
    if cfg.coal[d.name] then
      turtle.select(slot)
      turtle.drop()
    end
  end)

  -- Left: everything else (and coal the right container refused).
  nav.face(LEFT)
  inv.eachCargo(function(slot)
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 and not turtle.drop() do
      print("PICKUP container is full, waiting")
      sleep(15)
    end
  end)
  turtle.select(1)
  nav.face(H)
end

local function scan()
  while true do
    local blocks, err = scanner.scan(cfg.scanRadius)
    if blocks then
      local p = nav.pos()
      local found = {}
      for _, b in ipairs(blocks) do
        if cfg.targets[b.name] then
          local o = { x = p.x + b.x, y = p.y + b.y, z = p.z + b.z }
          if o.y > cfg.minY and not nav.protect(o.x, o.y, o.z) and not inCorridor(o.x, o.y, o.z) then
            found[#found + 1] = o
          end
        end
      end
      return found
    end
    print("scan failed: " .. tostring(err))
    sleep(2)
  end
end

local function nearest(list)
  local p, best, bestD = nav.pos(), nil, math.huge
  for i, o in ipairs(list) do
    local d = manhattan(p, o)
    if d < bestD then best, bestD = i, d end
  end
  return best
end

local function nextCell()
  st.ores = nil
  st.cell = st.cell + 1
  if st.cell > #CELLS then
    st.cell = 1
    st.level = st.level + 1
  end
  save()
end

-- One unit of work. Returns after each ore / scan point so progress is saved often.
local function mine()
  local y = cfg.levels[st.level]
  if not y then
    st.phase = "service"
    save()
    return
  end
  local c = CELLS[st.cell]
  local point = { x = shaft.x + c[1] * cfg.cellSize, y = y, z = shaft.z + c[2] * cfg.cellSize }

  if not st.ores then
    local home_, why = needHome(manhattan(nav.pos(), point) + homeCost(point))
    if home_ then
      print("going home: " .. why)
      st.phase = "service"
      save()
      return
    end
    print(("scan point %d/%d on level %d (Y %d)"):format(st.cell, #CELLS, st.level, y))
    local ok, err = goTo(point.x, point.y, point.z)
    if not ok then
      print("can't reach scan point: " .. tostring(err) .. ", skipping")
      nextCell()
      return
    end
    st.ores = scan()
    print(("found %d ore blocks"):format(#st.ores))
    save()
  end

  if #st.ores == 0 then
    nextCell()
    return
  end

  local i = nearest(st.ores)
  local ore = st.ores[i]
  local home_, why = needHome(manhattan(nav.pos(), ore) * 2)
  if home_ then
    print("going home: " .. why)
    st.phase = "service"
    save()
    return
  end
  local ok, err = goTo(ore.x, ore.y, ore.z)
  if not ok then print("skipping ore: " .. tostring(err)) end
  table.remove(st.ores, i)
  save()
end

-- main --------------------------------------------------------------------

nav.init({ origin = { x = home.x, y = home.y, z = home.z, h = H } })
st = state.load(STATE, { phase = "service", level = 1, cell = 1 })

print(("Miner: %d levels, %d scan points each. Ctrl+T to stop."):format(#cfg.levels, #CELLS))

while true do
  if st.phase == "service" then
    goHome()
    service()
    if cfg.levels[st.level] then
      st.phase = "mine"
    else
      st.phase = "done"
    end
    save()
  elseif st.phase == "mine" then
    mine()
  else
    goHome()
    print("Area finished. Run 'miner reset' to mine it again, or set up a new home.")
    return
  end
end
