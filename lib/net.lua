-- Rednet messaging between workers and the coordinator.
--
-- Turtles only ever *ask* the coordinator (request/reply). They never listen
-- for pushed messages, because turtle movement discards unrelated events.

local M = {}

M.PROTOCOL = "turtleswarm"

local coordinatorId
local lastStatus = -math.huge

function M.open()
  if turtle then
    local ok, err = require("lib.tools").equip("modem")
    if not ok then return false, err end
  end
  if rednet.isOpen() then return true end
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return false, "no wireless/ender modem" end
  rednet.open(peripheral.getName(modem))
  return true
end

local function stamp(msg)
  msg.label = os.getComputerLabel()
  if turtle then
    msg.fuel = turtle.getFuelLevel()
    local p = require("lib.nav").pos()
    if p.x then msg.pos = p end
  end
  return msg
end

local lastLookupFailed = -math.huge

local function coordinator()
  -- A failed lookup blocks for ~2s, so don't retry it more than once a minute.
  if not coordinatorId and os.clock() - lastLookupFailed > 60 then
    coordinatorId = rednet.lookup(M.PROTOCOL, "coordinator")
    if not coordinatorId then lastLookupFailed = os.clock() end
  end
  return coordinatorId
end

-- Send `msg` and wait for the matching reply. Returns nil if there is no
-- coordinator or it didn't answer in time.
function M.request(msg, timeout)
  if not M.open() then return nil end
  local id = coordinator()
  if not id then return nil end
  msg.nonce = math.random(1, 1000000000)
  rednet.send(id, stamp(msg), M.PROTOCOL)
  local deadline = os.clock() + (timeout or 3)
  while true do
    local remaining = deadline - os.clock()
    if remaining <= 0 then break end
    local from, reply = rednet.receive(M.PROTOCOL, remaining)
    if not from then break end
    if from == id and type(reply) == "table" and reply.nonce == msg.nonce then
      return reply
    end
  end
  coordinatorId = nil -- look it up again next time
  return nil
end

-- Fire-and-forget status update, at most every 15 seconds unless forced.
function M.status(fields, force)
  local now = os.clock()
  if not force and now - lastStatus < 15 then return end
  lastStatus = now
  if not M.open() then return end
  local id = coordinator()
  if not id then return end
  local msg = { type = "status" }
  for k, v in pairs(fields or {}) do msg[k] = v end
  rednet.send(id, stamp(msg), M.PROTOCOL)
end

return M
