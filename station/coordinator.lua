-- Coordinator computer: shows swarm status and hands out the bay lock so only
-- one turtle is in the bay at a time. Needs an ender modem; a monitor is optional.

package.path = "/?.lua;/?/init.lua;" .. package.path

local net = require("lib.net")

local LOCK_TIMEOUT = 120 -- seconds without renewal before a bay lock is dropped
local QUEUE_TIMEOUT = 30 -- seconds without re-request before leaving the queue

local ok, err = net.open()
if not ok then error("coordinator: " .. err) end
rednet.host(net.PROTOCOL, "coordinator")

local turtles = {}
local bay = { holder = nil, renewed = 0, queue = {} }

local function now() return os.epoch("utc") / 1000 end

local function track(id, msg)
  local t = turtles[id] or {}
  t.label = msg.label or t.label
  t.fuel = msg.fuel or t.fuel
  t.pos = msg.pos or t.pos
  t.task = msg.task or t.task
  t.note = msg.note or t.note
  t.seen = now()
  turtles[id] = t
end

local function queueIndex(id)
  for i, e in ipairs(bay.queue) do
    if e.id == id then return i end
  end
end

local function expire()
  local t = now()
  if bay.holder and t - bay.renewed > LOCK_TIMEOUT then bay.holder = nil end
  for i = #bay.queue, 1, -1 do
    if t - bay.queue[i].t > QUEUE_TIMEOUT then table.remove(bay.queue, i) end
  end
end

local function bayRequest(id)
  expire()
  if bay.holder == id then
    bay.renewed = now()
    return { granted = true }
  end
  local i = queueIndex(id)
  if not bay.holder and (#bay.queue == 0 or i == 1) then
    if i then table.remove(bay.queue, i) end
    bay.holder, bay.renewed = id, now()
    return { granted = true }
  end
  if i then
    bay.queue[i].t = now()
  else
    table.insert(bay.queue, { id = id, t = now() })
    i = #bay.queue
  end
  return { granted = false, queue = i }
end

local function listen()
  while true do
    local id, msg = rednet.receive(net.PROTOCOL)
    if type(msg) == "table" then
      track(id, msg)
      local reply
      if msg.type == "bay_request" then
        reply = bayRequest(id)
      elseif msg.type == "bay_release" then
        if bay.holder == id then bay.holder = nil end
        reply = { ok = true }
      end
      if reply and msg.nonce then
        reply.nonce = msg.nonce
        rednet.send(id, reply, net.PROTOCOL)
      end
    end
  end
end

local out = peripheral.find("monitor") or term.current()
if out.setTextScale then out.setTextScale(0.5) end

local function draw()
  while true do
    expire()
    out.setBackgroundColor(colors.black)
    out.clear()
    out.setCursorPos(1, 1)
    out.setTextColor(colors.yellow)
    local q = {}
    for _, e in ipairs(bay.queue) do q[#q + 1] = tostring(e.id) end
    out.write(("Turtle swarm  |  bay: %s  queue: %s"):format(
      bay.holder and ("#" .. bay.holder) or "free", #q > 0 and table.concat(q, ",") or "-"))

    local ids = {}
    for id in pairs(turtles) do ids[#ids + 1] = id end
    table.sort(ids)
    local _, h = out.getSize()
    local row = 3
    for _, id in ipairs(ids) do
      if row > h then break end
      local t = turtles[id]
      local age = math.floor(now() - t.seen)
      out.setCursorPos(1, row)
      out.setTextColor(age > 120 and colors.red or colors.white)
      local pos = t.pos and ("%d,%d,%d"):format(t.pos.x, t.pos.y, t.pos.z) or "?"
      out.write(("#%-3d %-10s %-8s fuel %-6s %-14s %3ds  %s"):format(
        id, (t.label or ""):sub(1, 10), t.task or "?", tostring(t.fuel or "?"), pos, age, t.note or ""))
      row = row + 1
    end
    sleep(2)
  end
end

print("Coordinator running on computer #" .. os.getComputerID())
parallel.waitForAny(listen, draw)
