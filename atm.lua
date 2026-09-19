-- Tunnels to the nearest allthemodium ore and stops right next to it,
-- WITHOUT mining it (mine it yourself with the right pickaxe).
--
-- Needs a pickaxe and a geo scanner equipped, plus some fuel.
-- No GPS needed: it finds its facing by moving one block and scanning again.
--
-- Usage: atm                 scan radius 8
--        atm 16              bigger radius (costs fuel per scan, max 16)
--        atm north           skip facing detection (F3 "Facing" of the turtle)

local TARGETS = {
  ["allthemodium:allthemodium_ore"] = true,
  ["allthemodium:allthemodium_slate_ore"] = true,
}

-- Never dig these (wait / go around instead).
local NO_DIG = {
  "^computercraft:", "^advancedperipherals:", "chest", "barrel",
  "shulker_box", "spawner", "^minecraft:bedrock$",
}

local HEADINGS = { north = 0, east = 1, south = 2, west = 3 }
local NAMES = { [0] = "north", "east", "south", "west" }
local DIRS = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } } -- dx, dz

local radius, h = 8, nil
for _, a in ipairs(arg) do
  if tonumber(a) then radius = math.min(16, tonumber(a))
  elseif HEADINGS[a] then h = HEADINGS[a]
  else error("usage: atm [radius] [north|east|south|west]") end
end

local scanner = peripheral.find("geo_scanner") or peripheral.find("geoScanner")
if not scanner then error("atm: equip a geo scanner (and a pickaxe)") end

-- Position relative to where we started, in world axes.
local x, y, z = 0, 0, 0

-- Ore positions relative to the start, plus the raw scan.
local function scan()
  while true do
    local blocks, err = scanner.scan(radius)
    if blocks then
      local ores = {}
      for _, b in ipairs(blocks) do
        if TARGETS[b.name] then ores[#ores + 1] = { x = x + b.x, y = y + b.y, z = z + b.z } end
      end
      return ores, blocks
    end
    print("scan: " .. tostring(err) .. ", retrying")
    sleep(1)
  end
end

local function dist(o) return math.abs(o.x - x) + math.abs(o.y - y) + math.abs(o.z - z) end

local function nearest(ores)
  local best
  for _, o in ipairs(ores) do
    if not best or dist(o) < dist(best) then best = o end
  end
  return best
end

local ops = {
  forward = { turtle.forward, turtle.dig, turtle.inspect, turtle.attack },
  up = { turtle.up, turtle.digUp, turtle.inspectUp, turtle.attackUp },
  down = { turtle.down, turtle.digDown, turtle.inspectDown, turtle.attackDown },
}

-- Move one block, digging if needed. Returns true, or false + "ore" when the
-- block in the way is allthemodium ore (= we are next to it), or false + reason.
local function step(dir)
  local move, dig, inspect, attack = table.unpack(ops[dir])
  for _ = 1, 40 do
    if turtle.getFuelLevel() == 0 then return false, "out of fuel" end
    if move() then
      if dir == "up" then y = y + 1
      elseif dir == "down" then y = y - 1
      elseif h then x, z = x + DIRS[h][1], z + DIRS[h][2] end
      return true
    end
    local solid, info = inspect()
    if solid then
      if TARGETS[info.name] then return false, "ore" end
      for _, p in ipairs(NO_DIG) do
        if info.name:find(p) then return false, "blocked by " .. info.name end
      end
      if not dig() then return false, "cannot dig " .. info.name end
      -- gravel/sand may fall back in: the loop just digs again
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

local function arrived(dir)
  local where = dir == "forward" and ("in front (" .. NAMES[h] .. ")") or (dir == "up" and "above" or "below")
  print("Next to allthemodium ore! It is " .. where .. ".")
  print(("Turtle is %d east, %d up, %d south of the start (negative = west/down/north)."):format(x, y, z))
end

-- Already touching one?
for _, dir in ipairs({ "up", "down" }) do
  local solid, info = ops[dir][3]()
  if solid and TARGETS[info.name] then arrived(dir) return end
end

local ores, before = scan()
if #ores == 0 then
  print(("No allthemodium ore within %d blocks. Move somewhere else (deeper) and try again."):format(radius))
  return
end
local target = nearest(ores)
print(("%d ore blocks found, nearest is %d blocks away."):format(#ores, dist(target)))

-- Fuel: the trip plus some room for detours.
local need = dist(target) + 40
if turtle.getFuelLevel() < need then
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then
      while turtle.getFuelLevel() < need and turtle.refuel(1) do end
    end
  end
  turtle.select(1)
  if turtle.getFuelLevel() < need then
    error(("atm: need %d fuel, have %d. Put coal in the turtle."):format(need, turtle.getFuelLevel()))
  end
end

-- Unknown facing: step forward, scan again and see which way the blocks shifted.
if not h then
  local moved = false
  for _ = 1, 4 do
    local ok, err = step("forward")
    if ok then moved = true break end
    if err == "ore" then
      -- touching ore in front; facing doesn't matter any more
      print("Next to allthemodium ore! It is in front of the turtle.")
      return
    end
    turtle.turnRight()
  end
  if not moved then error("atm: can't move to find the facing. Run: atm <north|east|south|west>") end

  -- Compare all scanned blocks: the world shifted by one step the other way.
  local _, after = scan()
  local seen = {}
  for _, b in ipairs(before) do seen[b.x .. "," .. b.y .. "," .. b.z] = b.name end
  local best, bestHits = nil, 0
  for d = 0, 3 do
    local hits = 0
    for _, a in ipairs(after) do
      if seen[(a.x + DIRS[d][1]) .. "," .. a.y .. "," .. (a.z + DIRS[d][2])] == a.name then hits = hits + 1 end
    end
    if hits > bestHits then best, bestHits = d, hits end
  end
  if not best then error("atm: couldn't work out the facing. Run: atm <north|east|south|west>") end
  h = best
  x, z = DIRS[h][1], DIRS[h][2]
  print("Facing " .. NAMES[h] .. ".")
end

-- Walk towards the ore: X, then Z, then Y. The ore itself is never dug, so the
-- trip ends when the next step would go into it (or into any other ATM ore).
local detours = 0
while true do
  local dir
  if target.x ~= x then
    face(target.x > x and 1 or 3)
    dir = "forward"
  elseif target.z ~= z then
    face(target.z > z and 2 or 0)
    dir = "forward"
  elseif target.y ~= y then
    dir = target.y > y and "up" or "down"
  else
    error("atm: standing inside the ore?") -- can't happen
  end

  local ok, err = step(dir)
  if not ok then
    if err == "ore" then arrived(dir) return end
    if err == "out of fuel" then error("atm: out of fuel") end
    -- Undiggable block: hop over (or under) it and carry on.
    detours = detours + 1
    if detours > 20 then error("atm: giving up, " .. err) end
    print(err .. ", going around")
    local around = dir == "forward" and { "up", "down" } or { "forward" }
    if dir ~= "forward" then face((h + 1 + detours % 2 * 2) % 4) end
    for _, d in ipairs(around) do
      local ok2, err2 = step(d)
      if ok2 then break end
      if err2 == "ore" then arrived(d) return end
    end
  end
end
