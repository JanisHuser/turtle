-- Swapping upgrades on the turtle's swap side.
--
-- A turtle only has two upgrade slots. One holds the chunk controller forever
-- (so the turtle keeps running when nobody is nearby). The other rotates
-- between pickaxe, ender modem and geo scanner, which live in the inventory
-- while not equipped.

local config = require("config")

local M = {}

local side = config.tools.swapSide
local current -- kind currently on the swap side; nil = not yet detected

function M.kindOf(name)
  if not name then return "none" end
  for kind, names in pairs(config.tools.items) do
    for _, n in ipairs(names) do
      if n == name then return kind end
    end
  end
  return "other"
end

function M.isTool(name)
  local kind = M.kindOf(name)
  return kind ~= "other" and kind ~= "none"
end

function M.find(kind)
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d and M.kindOf(d.name) == kind then return slot end
  end
  return nil
end

local function getter(which)
  if which == "left" then return turtle.getEquippedLeft end
  return turtle.getEquippedRight
end

function M.equippedOn(which)
  local get = getter(which)
  if get then
    local d = get()
    return M.kindOf(d and d.name)
  end
  -- Older CC:Tweaked without getEquipped*: infer from the peripheral.
  local t = peripheral.getType(which)
  if t == "modem" then return "modem" end
  if t == "geoScanner" then return "scanner" end
  if t then return "other" end
  if not M.find("pickaxe") then return "pickaxe" end
  return "unknown"
end

function M.equip(kind)
  if current == nil then current = M.equippedOn(side) end
  if current == kind then return true end
  -- Already on the permanent side (e.g. a miner with pickaxe + geo scanner)?
  if M.equippedOn(side == "left" and "right" or "left") == kind then return true end
  local slot = M.find(kind)
  if not slot then return false, "no " .. kind .. " in inventory" end
  local prev = turtle.getSelectedSlot()
  turtle.select(slot)
  local fn = side == "left" and turtle.equipLeft or turtle.equipRight
  local ok, err = fn()
  turtle.select(prev)
  if not ok then
    current = nil
    return false, err
  end
  current = kind
  return true
end

-- One-time setup: chunk controller on the permanent side, modem on the swap side.
function M.setupWorker()
  local fixed = side == "left" and "right" or "left"
  if M.equippedOn(fixed) ~= "chunky" then
    local slot = M.find("chunky")
    if not slot then
      return false, "put an Advanced Peripherals chunk controller in the inventory"
    end
    turtle.select(slot)
    local fn = fixed == "left" and turtle.equipLeft or turtle.equipRight
    local ok, err = fn()
    if not ok then return false, err end
  end
  current = nil
  if not M.find("pickaxe") and M.equippedOn(side) ~= "pickaxe" then
    return false, "turtle needs a diamond pickaxe (equipped or in inventory)"
  end
  local ok, err = M.equip("modem")
  if not ok then return false, "turtle needs an ender modem: " .. tostring(err) end
  turtle.select(1)
  return true
end

return M
