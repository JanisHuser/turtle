-- Scans for an ore, digs to every matching block in range, mines it and
-- comes back to where it started. Refuels from its own inventory.
-- Nothing in range: moves 16 blocks forward and scans again (up to 10 times).
--
-- Needs a pickaxe and a geo scanner equipped, plus some coal.
-- The facing is found automatically (moves one block and scans again).
--
-- Usage: ore                      platinum, radius 16
--        ore allthemodium         any block whose name contains this
--        ore platinum 8 north     radius 8, turtle faces north (skips detection)

local HEADINGS = { north = 0, east = 1, south = 2, west = 3 }
local NAMES = { [0] = "north", "east", "south", "west" }
local DIRS = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- dx, dz

local TARGET, RADIUS, h = "platinum", 16, nil
for _, a in ipairs(arg) do
  if tonumber(a) then RADIUS = tonumber(a)
  elseif HEADINGS[a] then h = HEADINGS[a]
  else TARGET = string.lower(a) end
end

-- Never dig these.
local NO_DIG = {
  "^computercraft:", "^advancedperipherals:", "chest", "barrel",
  "shulker_box", "spawner", "^minecraft:bedrock$",
}
-- Thrown away when the inventory gets full.
local JUNK = {
  "stone", "deepslate", "cobble", "dirt", "gravel", "tuff", "granite",
  "diorite", "andesite", "netherrack", "sand", "calcite", "sculk",
}
local RESERVE = 50 -- fuel kept on top of the way home
local SEARCH_STEP = 16 -- nothing found: move this far forward and scan again
local MAX_SEARCH = 10  -- ... at most this many times, then go home

local scanner = peripheral.find("geo_scanner")
if not scanner then
  print("ERROR: Geo Scanner not found!")
  return
end

-- Position relative to the start, in world axes (x = east, z = south).
local x, y, z = 0, 0, 0

local function isTarget(name) return string.find(string.lower(name or ""), TARGET, 1, true) ~= nil end

local function scan()
  while true do
    local blocks, err = scanner.scanBlocks(RADIUS)
    if blocks then return blocks end
    print("Scan failed: " .. tostring(err) .. ", retrying")
    sleep(1)
  end
end

local function distTo(p) return math.abs(p.x - x) + math.abs(p.y - y) + math.abs(p.z - z) end
local function distHome() return math.abs(x) + math.abs(y) + math.abs(z) end

-- Burn fuel items from the inventory until `level` is reached.
local function refuel(level)
  if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() >= level then return true end
  local prev = turtle.getSelectedSlot()
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then
      while turtle.getFuelLevel() < level and turtle.refuel(1) do end
    end
    if turtle.getFuelLevel() >= level then break end
  end
  turtle.select(prev)
  return turtle.getFuelLevel() >= level
end

local function freeSlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

-- Drop stone & co. when the inventory is almost full (never ore or fuel).
local function dropJunk()
  if freeSlots() >= 2 then return end
  local prev = turtle.getSelectedSlot()
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and not isTarget(d.name) then
      turtle.select(slot)
      if not turtle.refuel(0) then
        for _, j in ipairs(JUNK) do
          if d.name:find(j) then turtle.dropDown() break end
        end
      end
    end
  end
  turtle.select(prev)
end

local ops = {
  forward = { turtle.forward, turtle.dig, turtle.inspect, turtle.attack },
  up = { turtle.up, turtle.digUp, turtle.inspectUp, turtle.attackUp },
  down = { turtle.down, turtle.digDown, turtle.inspectDown, turtle.attackDown },
}

-- Move one block, digging whatever is in the way.
local function step(dir)
  local move, dig, inspect, attack = table.unpack(ops[dir])
  for _ = 1, 40 do
    if turtle.getFuelLevel() == 0 and not refuel(1) then return false, "out of fuel" end
    if move() then
      if dir == "up" then y = y + 1
      elseif dir == "down" then y = y - 1
      elseif h then x, z = x + DIRS[h][1], z + DIRS[h][2] end
      return true
    end
    local solid, info = inspect()
    if solid then
      for _, p in ipairs(NO_DIG) do
        if info.name:find(p) then return false, "blocked by " .. info.name end
      end
      dropJunk()
      if not dig() then return false, "can't dig " .. info.name end
    else
      attack() -- mob in the way
      sleep(0.5)
    end
  end
  return false, "stuck"
end

local function face(target)
  while h ~= target do
    turtle.turnRight()
    h = (h + 1) % 4
  end
end

-- One move in a world direction: "up", "down" or a heading 0..3.
local function go(d)
  if d == "up" or d == "down" then return step(d) end
  face(d)
  return step("forward")
end

-- Dig to (tx, ty, tz). Tries every direction that gets closer (up/down, X, Z);
-- if all are blocked (bedrock, chests...) it sidesteps, preferring up.
local function goTo(tx, ty, tz)
  local detours = 0
  local lastErr
  while x ~= tx or y ~= ty or z ~= tz do
    local closer = {}
    if y ~= ty then closer[#closer + 1] = ty > y and "up" or "down" end
    if x ~= tx then closer[#closer + 1] = tx > x and 1 or 3 end
    if z ~= tz then closer[#closer + 1] = tz > z and 2 or 0 end
    local moved = false
    for _, d in ipairs(closer) do
      local ok, err = go(d)
      if ok then moved = true break end
      if err == "out of fuel" then return false, err end
      lastErr = err
    end
    if not moved then
      detours = detours + 1
      if detours > 30 then return false, lastErr end
      local side = { "up", (h + 1) % 4, (h + 3) % 4, "down" }
      for _, d in ipairs(side) do
        -- a couple of blocks sideways so we don't bounce straight back
        if go(d) then
          if d ~= "up" and d ~= "down" then go("up") end
          break
        end
      end
    end
  end
  return true
end

-- MAIN

if not refuel(RESERVE * 2) then
  print("ERROR: no fuel. Put coal into the turtle.")
  return
end

local current = scan() -- blocks relative to where the turtle is now

-- Unknown facing: step forward, scan again and see which way the world shifted.
if not h then
  local moved = false
  for _ = 1, 4 do
    if step("forward") then moved = true break end
    turtle.turnRight()
  end
  if not moved then
    print("ERROR: can't move to find the facing. Run: ore " .. TARGET .. " " .. RADIUS .. " <north|east|south|west>")
    return
  end
  local seen = {}
  for _, b in ipairs(current) do seen[b.x .. "," .. b.y .. "," .. b.z] = b.name end
  current = scan()
  local best, bestHits = nil, 0
  for d = 0, 3 do
    local hits = 0
    for _, a in ipairs(current) do
      if seen[(a.x + DIRS[d][1]) .. "," .. a.y .. "," .. (a.z + DIRS[d][2])] == a.name then hits = hits + 1 end
    end
    if hits > bestHits then best, bestHits = d, hits end
  end
  if not best then
    print("ERROR: couldn't work out the facing. Run: ore " .. TARGET .. " " .. RADIUS .. " <north|east|south|west>")
    return
  end
  h = best
  x, z = DIRS[h][1], DIRS[h][2]
  print("Facing " .. NAMES[h] .. ".")
end
local startH = h -- facing to restore at the end

-- Nothing in range: tunnel SEARCH_STEP blocks forward and scan again.
local ores = {}
local hops = 0
while true do
  for _, b in ipairs(current) do
    if isTarget(b.name) then
      ores[#ores + 1] = { x = x + b.x, y = y + b.y, z = z + b.z, name = b.name }
    end
  end
  if #ores > 0 then break end
  if hops >= MAX_SEARCH then
    print(("No %s found after %d moves, giving up."):format(TARGET, hops))
    break
  end
  -- fuel to go forward and still get back home
  if not refuel(distHome() + 2 * SEARCH_STEP + RESERVE) then
    print("Low fuel, stopping the search.")
    break
  end
  hops = hops + 1
  print(("No %s here, moving %d blocks %s (%d/%d)"):format(TARGET, SEARCH_STEP, NAMES[startH], hops, MAX_SEARCH))
  local ok, err = goTo(x + DIRS[startH][1] * SEARCH_STEP, y, z + DIRS[startH][2] * SEARCH_STEP)
  if not ok then
    print("Can't go further: " .. tostring(err))
    break
  end
  current = scan()
end
if #ores > 0 then print(("Found %d %s blocks."):format(#ores, TARGET)) end

-- Mine the nearest ore, then the next nearest, ... When the list is done,
-- scan again from where we are (the vein may go on) and keep going.
local mined = 0
while #ores > 0 do
  local best
  for i, o in ipairs(ores) do
    if not best or distTo(o) < distTo(ores[best]) then best = i end
  end
  local o = table.remove(ores, best)

  -- Enough fuel to get there and back home?
  local need = distTo(o) + math.abs(o.x) + math.abs(o.y) + math.abs(o.z) + RESERVE
  if not refuel(need) then
    print(("Low fuel (%d, need %d), going home."):format(turtle.getFuelLevel(), need))
    break
  end
  if freeSlots() == 0 then dropJunk() end
  if freeSlots() == 0 then
    print("Inventory full, going home.")
    break
  end

  local ok, err = goTo(o.x, o.y, o.z) -- moving into the ore block digs it
  if ok then
    mined = mined + 1
    print(("Mined %s (%d left)"):format(o.name, #ores))
  else
    print("Skipping ore: " .. tostring(err))
  end

  if #ores == 0 and ok then
    for _, b in ipairs(scan()) do
      if isTarget(b.name) then
        ores[#ores + 1] = { x = x + b.x, y = y + b.y, z = z + b.z, name = b.name }
      end
    end
    if #ores > 0 then print(("Found %d more."):format(#ores)) end
  end
end

print("Going home...")
refuel(distHome() + 1)
local ok, err = goTo(0, 0, 0)
if not ok then
  print("ERROR: can't get home: " .. tostring(err))
  print(("I'm at %d east, %d up, %d south of the start."):format(x, y, z))
  return
end
face(startH)
print(("Done. Mined %d %s blocks. Fuel: %s"):format(mined, TARGET, tostring(turtle.getFuelLevel())))
