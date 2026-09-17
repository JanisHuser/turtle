-- Position tracking and movement that survives server restarts.
--
-- Before every move the turtle writes a "pending" record containing its fuel
-- level. On boot, if fuel dropped, the move happened; otherwise it didn't.
-- GPS is used on boot to verify the position and to find the heading when it
-- is unknown (e.g. the server stopped in the middle of a turn).

local config = require("config")
local state = require("lib.state")
local tools = require("lib.tools")

local M = {}

local STATE = "/.nav"

-- heading index -> {dx, dz}
M.DIRS = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
M.HEADING = { north = 0, east = 1, south = 2, west = 3 }

local s = {} -- { x, y, z, h, pending }

-- Called after every successful move; worker programs hook status updates in here.
M.onMove = function() end

local function save() state.save(STATE, s) end

local function applyMove(op)
  if op == "up" then
    s.y = s.y + 1
  elseif op == "down" then
    s.y = s.y - 1
  else
    local d = M.DIRS[s.h]
    local sign = op == "back" and -1 or 1
    s.x = s.x + d[1] * sign
    s.z = s.z + d[2] * sign
  end
end

local function locate()
  if not tools.equip("modem") then return nil end
  local x, y, z = gps.locate(2)
  if not x then return nil end
  return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
end

local function isTurtle(name)
  return name:find("^computercraft:turtle") ~= nil
end

-- Where digging/attacking is forbidden. Programs may replace M.protect.
M.protect = function(x, y, z)
  local st = config.station
  local r = st.protectRadius
  return math.abs(x - st.bay.x) <= r and math.abs(z - st.bay.z) <= r and y < config.cruise.base
end

function M.isProtected(x, y, z)
  return M.protect(x, y, z)
end

local function targetOf(dir)
  if dir == "up" then return s.x, s.y + 1, s.z end
  if dir == "down" then return s.x, s.y - 1, s.z end
  local d = M.DIRS[s.h]
  return s.x + d[1], s.y, s.z + d[2]
end

function M.canDig(dir, blockName)
  if M.isProtected(targetOf(dir)) then return false end
  for _, pattern in ipairs(config.noDig) do
    if blockName:find(pattern) then return false end
  end
  return true
end

local raw = {
  forward = { move = turtle.forward, dig = turtle.dig, inspect = turtle.inspect, attack = turtle.attack },
  up = { move = turtle.up, dig = turtle.digUp, inspect = turtle.inspectUp, attack = turtle.attackUp },
  down = { move = turtle.down, dig = turtle.digDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

-- Move one block. opts.dig = false disables digging, opts.maxWait = seconds to
-- wait for another turtle / entity before giving up.
local function step(dir, opts)
  opts = opts or {}
  local a = raw[dir]
  local waited = 0
  local maxWait = opts.maxWait or 60
  while true do
    local fuel = turtle.getFuelLevel()
    if fuel == 0 then return false, "out of fuel" end
    s.pending = { op = dir, fuel = fuel }
    save()
    local ok = a.move()
    if ok then applyMove(dir) end
    s.pending = nil
    save()
    if ok then
      M.onMove()
      return true
    end

    local hasBlock, info = a.inspect()
    if hasBlock then
      if isTurtle(info.name) then
        if waited >= maxWait then return false, "blocked by turtle" end
        local t = 0.5 + math.random()
        sleep(t)
        waited = waited + t
      elseif opts.dig == false or not M.canDig(dir, info.name) then
        return false, "blocked by " .. info.name
      else
        local okTool, err = tools.equip("pickaxe")
        if not okTool then return false, err end
        if not a.dig() then return false, "cannot dig " .. info.name end
      end
    else
      -- Something without a block is in the way: a mob, a player, a dropped boat...
      if waited >= maxWait then return false, "blocked by entity" end
      if not M.isProtected(targetOf(dir)) and tools.equip("pickaxe") then a.attack() end
      sleep(0.5)
      waited = waited + 0.5
    end
  end
end

local function turn(right)
  s.pending = { op = "turn" }
  save()
  if right then turtle.turnRight() else turtle.turnLeft() end
  s.h = (s.h + (right and 1 or 3)) % 4
  s.pending = nil
  save()
end

function M.turnRight() turn(true) end
function M.turnLeft() turn(false) end

function M.face(h)
  if type(h) == "string" then h = M.HEADING[h] end
  local diff = (h - s.h) % 4
  if diff == 1 then M.turnRight()
  elseif diff == 2 then M.turnRight() M.turnRight()
  elseif diff == 3 then M.turnLeft() end
end

function M.forward(opts) return step("forward", opts) end
function M.up(opts) return step("up", opts) end
function M.down(opts) return step("down", opts) end

-- Find heading by moving one block and comparing GPS positions.
local function determineHeading()
  local x, y, z = locate()
  if not x then
    error("nav: GPS unavailable - is the GPS tower running and an ender modem in the inventory?")
  end
  s.x, s.y, s.z, s.h, s.pending = x, y, z, nil, nil
  save()
  for attempt = 1, 3 do
    for _ = 1, 4 do
      if turtle.forward() then
        local x2, y2, z2 = locate()
        if not x2 then error("nav: GPS lost while finding heading") end
        local dx, dz = x2 - x, z2 - z
        for h, d in pairs(M.DIRS) do
          if d[1] == dx and d[2] == dz then s.h = h end
        end
        s.x, s.y, s.z = x2, y2, z2
        save()
        if s.h == nil then error("nav: unexpected GPS delta while finding heading") end
        return
      end
      turtle.turnRight()
    end
    -- Boxed in horizontally: try to dig forward once, otherwise change height.
    local hasBlock, info = turtle.inspect()
    local dug = false
    if attempt == 1 and hasBlock and not M.isProtected(x, y, z) then
      local blocked = false
      for _, pattern in ipairs(config.noDig) do
        if info.name:find(pattern) then blocked = true end
      end
      if not blocked and tools.equip("pickaxe") then dug = turtle.dig() end
    end
    if not dug and (turtle.up() or turtle.down()) then
      x, y, z = locate()
      if not x then error("nav: GPS lost while finding heading") end
      s.x, s.y, s.z = x, y, z
      save()
    end
  end
  error("nav: cannot find heading, turtle is boxed in")
end

-- opts.origin = { x, y, z, h }: position to use when there is neither a saved
-- position nor GPS (turtles without an ender modem).
function M.init(opts)
  s = state.load(STATE, {})
  local p = s.pending
  if p then
    if p.op == "turn" then
      s.h = nil
    elseif type(p.fuel) ~= "number" or type(turtle.getFuelLevel()) ~= "number" then
      s.x = nil
    elseif turtle.getFuelLevel() < p.fuel and s.h ~= nil then
      applyMove(p.op)
    end
    s.pending = nil
    save()
  end

  local x, y, z = locate()
  if x then
    if s.x ~= x or s.y ~= y or s.z ~= z or s.h == nil then
      if s.x ~= nil and (s.x ~= x or s.y ~= y or s.z ~= z) then
        print(("nav: saved position was wrong, GPS says %d %d %d"):format(x, y, z))
      end
      determineHeading()
    end
  elseif (s.x == nil or s.h == nil) and opts and opts.origin then
    local o = opts.origin
    s = { x = o.x, y = o.y, z = o.z, h = o.h }
    save()
  elseif s.x == nil or s.h == nil then
    error("nav: no saved position and no GPS signal")
  else
    print("nav: no GPS signal, trusting saved position")
  end
  print(("nav: at %d %d %d facing %d"):format(s.x, s.y, s.z, s.h))
end

function M.pos()
  return { x = s.x, y = s.y, z = s.z, h = s.h }
end

function M.cruiseY()
  return config.cruise.base + (os.getComputerID() % config.cruise.layers)
end

-- Move along axes: up first, then X, then Z, then down.
-- If an axis is blocked by something undiggable, hop up one block and retry.
function M.moveTo(tx, ty, tz, opts)
  opts = opts or {}
  local detours = 0
  while s.x ~= tx or s.y ~= ty or s.z ~= tz do
    local ok, err
    if s.y < ty then
      ok, err = step("up", opts)
    elseif s.x ~= tx then
      M.face(s.x < tx and 1 or 3)
      ok, err = step("forward", opts)
    elseif s.z ~= tz then
      M.face(s.z < tz and 2 or 0)
      ok, err = step("forward", opts)
    else
      ok, err = step("down", opts)
    end
    if not ok then
      if err == "out of fuel" or detours >= (opts.maxDetours or 8) then return false, err end
      detours = detours + 1
      if not step("up", opts) then return false, err end
    end
  end
  return true
end

-- Long distance: climb to our cruise layer, fly across, descend.
function M.travelTo(tx, ty, tz, opts)
  if s.x == tx and s.z == tz then return M.moveTo(tx, ty, tz, opts) end
  local cy = M.cruiseY()
  local ok, err = M.moveTo(s.x, cy, s.z, opts)
  if not ok then return false, err end
  ok, err = M.moveTo(tx, cy, tz, opts)
  if not ok then return false, err end
  return M.moveTo(tx, ty, tz, opts)
end

function M.travelCost(tx, ty, tz)
  if s.x == tx and s.z == tz then return math.abs(s.y - ty) end
  local cy = M.cruiseY()
  return math.abs(s.y - cy) + math.abs(s.x - tx) + math.abs(s.z - tz) + math.abs(cy - ty)
end

return M
