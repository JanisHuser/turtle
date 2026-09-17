-- Inventory helpers.

local config = require("config")
local tools = require("lib.tools")

local M = {}

function M.freeSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return slot end
  end
  return nil
end

function M.freeSlots()
  local n = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then n = n + 1 end
  end
  return n
end

-- Burn fuel items from the inventory until `level` is reached.
-- Returns true if the fuel level is now at least `level`.
function M.refuelFromInventory(level)
  local prev = turtle.getSelectedSlot()
  for slot = 1, 16 do
    if turtle.getFuelLevel() >= level then break end
    local d = turtle.getItemDetail(slot)
    if d and config.fuel.items[d.name] then
      turtle.select(slot)
      while turtle.getFuelLevel() < level and turtle.getItemCount(slot) > 0 do
        if not turtle.refuel(1) then break end
      end
    end
  end
  turtle.select(prev)
  return turtle.getFuelLevel() >= level
end

-- Call fn(slot, detail) for every non-tool item stack.
function M.eachCargo(fn)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and not tools.isTool(d.name) then fn(slot, d) end
  end
end

return M
