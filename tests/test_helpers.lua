--- Lightweight pure-Lua tests (run outside Factorio with a tiny shim, or as documentation).
--- These assert helper logic that does not need the game runtime.

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
  end
end

-- Inline copies of pure helpers (mirror scripts/util.lua chunk_key / distance).
local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function chunk_key(position)
  local cx = math.floor(position.x / 32)
  local cy = math.floor(position.y / 32)
  return cx * 65536 + cy
end

assert_eq(distance({ x = 0, y = 0 }, { x = 3, y = 4 }), 5, "distance 3-4-5")
assert_eq(chunk_key({ x = 0, y = 0 }), 0, "chunk origin")
assert_eq(chunk_key({ x = 32, y = 0 }), 65536, "chunk +1x")
assert_eq(chunk_key({ x = -1, y = -1 }), (-1) * 65536 + (-1), "chunk negative")

-- State name set
local states = {
  idle = true,
  patrol = true,
  search = true,
  moving = true,
  attacking = true,
  returning = true,
  restocking = true,
  waiting = true,
}
local count = 0
for _ in pairs(states) do
  count = count + 1
end
assert_eq(count, 8, "eight FSM states")

print("SpidertronHunter pure tests OK")
