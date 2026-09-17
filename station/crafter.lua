-- Crafter turtle: turns coal from the COAL barrel (below) into coal blocks
-- and puts them into the FUEL barrel (in front). Anything that is not coal
-- is dropped upwards (put an overflow barrel above the crafter).
--
-- Upgrades: crafting table + chunk controller (keeps the station loaded).

package.path = "/?.lua;/?/init.lua;" .. package.path

local craft = turtle.craft
if not craft then
  local bench = peripheral.find("workbench")
  craft = bench and bench.craft
end
if not craft then error("crafter: equip a crafting table on this turtle") end

local COAL, BLOCK = "minecraft:coal", "minecraft:coal_block"
local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
local BUFFER = { 4, 8, 12, 13, 14, 15, 16 }

-- Empty the whole inventory to where each item belongs.
local function flush()
  for slot = 1, 16 do
    local d = turtle.getItemDetail(slot)
    if d then
      turtle.select(slot)
      if d.name == BLOCK then
        while not turtle.drop() do
          print("FUEL barrel full, waiting")
          sleep(10)
        end
      elseif d.name == COAL then
        turtle.dropDown()
      else
        turtle.dropUp()
      end
    end
  end
  turtle.select(1)
end

local function cycle()
  flush()

  -- Pull up to 7 stacks of coal into the non-grid slots.
  local total = 0
  for _, slot in ipairs(BUFFER) do
    turtle.select(slot)
    if not turtle.suckDown(64) then break end
    local d = turtle.getItemDetail(slot)
    if d and d.name ~= COAL then
      turtle.dropUp()
    elseif d then
      total = total + d.count
    end
  end

  local perSlot = math.min(64, math.floor(total / 9))
  if perSlot == 0 then
    flush()
    return 0
  end

  -- Put exactly `perSlot` coal into each of the 9 grid slots.
  for _, g in ipairs(GRID) do
    local need = perSlot
    for _, b in ipairs(BUFFER) do
      if need == 0 then break end
      local count = turtle.getItemCount(b)
      if count > 0 then
        turtle.select(b)
        local n = math.min(count, need)
        turtle.transferTo(g, n)
        need = need - n
      end
    end
  end

  -- Crafting needs every slot outside the grid to be empty.
  for _, b in ipairs(BUFFER) do
    if turtle.getItemCount(b) > 0 then
      turtle.select(b)
      turtle.dropDown()
    end
  end

  turtle.select(1)
  local ok, err = craft(perSlot)
  if not ok then print("craft failed: " .. tostring(err)) end
  flush()
  return ok and perSlot or 0
end

print("Crafter running. COAL below, FUEL in front, overflow above.")
local made = 0
while true do
  local n = cycle()
  if n > 0 then
    made = made + n
    print(("crafted %d coal blocks (%d total)"):format(n, made))
  else
    sleep(10)
  end
end
