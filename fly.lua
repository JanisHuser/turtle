-- Test movement: fly to a coordinate at cruise height.
-- Usage: fly <x> <y> <z>

package.path = "/?.lua;/?/init.lua;" .. package.path

local nav = require("lib.nav")

local x, y, z = tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3])
if not (x and y and z) then
  print("Usage: fly <x> <y> <z>")
  return
end

nav.init()
local cost = nav.travelCost(x, y, z)
print(("distance %d, fuel %d"):format(cost, turtle.getFuelLevel()))
local ok, err = nav.travelTo(x, y, z)
print(ok and "arrived" or ("stopped: " .. tostring(err)))
