-- Crash-safe persistence of Lua tables.
-- Writes go to `<path>.tmp` first, so a server stop mid-write never leaves a
-- half-written state file behind.

local M = {}

local function read(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local data = h.readAll()
  h.close()
  local ok, value = pcall(textutils.unserialise, data)
  if ok then return value end
  return nil
end

function M.load(path, default)
  -- A complete .tmp is newer than the main file (crash between write and move).
  local value = read(path .. ".tmp")
  if value == nil then value = read(path) end
  if value == nil then return default end
  return value
end

function M.save(path, value)
  local tmp = path .. ".tmp"
  local h = fs.open(tmp, "w")
  h.write(textutils.serialise(value, { compact = true }))
  h.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

function M.clear(path)
  if fs.exists(path) then fs.delete(path) end
  if fs.exists(path .. ".tmp") then fs.delete(path .. ".tmp") end
end

return M
