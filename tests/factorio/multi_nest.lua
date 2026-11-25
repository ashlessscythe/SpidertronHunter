-- Multi-nest campaign: does the hunter keep kiting / engaging on the 2nd and 3rd nest?
-- Runs the same three-nest scenario with threat awareness off / normal / cautious and records
-- per-nest metrics (kiting repositions, stationary time while attacking, health, states).
local H = require("tests/factorio/helpers")
local surface, zoom_to, spawn_hunter, spawn_enemy, distance =
  H.surface, H.zoom_to, H.spawn_hunter, H.spawn_enemy, H.distance

local NESTS = {
  { name = "A", x = 70, y = 0 },
  { name = "B", x = 70, y = 90 },
  { name = "C", x = -70, y = 90 },
}

local function set_setting(name, value)
  local old = settings.global[name].value
  settings.global[name] = { value = value }
  storage.settings_cache = nil
  after_test(function()
    settings.global[name] = { value = old }
    storage.settings_cache = nil
  end)
end

local function build_nest(n, hard)
  local list = {}
  local function add(e) if e then list[#list + 1] = e end end
  if hard then
    for i = 1, 4 do add(spawn_enemy(i % 2 == 0 and "spitter-spawner" or "biter-spawner", n.x + (i - 1) * 9, n.y)) end
    for i = 1, 2 do add(spawn_enemy("medium-worm-turret", n.x + (i - 1) * 8, n.y - 12)) end
    add(spawn_enemy("small-worm-turret", n.x + 20, n.y - 12))
    for i = 1, 10 do add(spawn_enemy("medium-biter", n.x + (i % 5) * 2, n.y + 6 + math.floor(i / 5) * 2)) end
    for i = 1, 6 do add(spawn_enemy("medium-spitter", n.x + (i % 3) * 2, n.y + 12 + math.floor(i / 3) * 2)) end
    return list
  end
  for i = 1, 2 do add(spawn_enemy("biter-spawner", n.x + (i - 1) * 9, n.y)) end
  for i = 1, 2 do add(spawn_enemy("small-worm-turret", n.x + (i - 1) * 8, n.y - 10)) end
  for i = 1, 10 do add(spawn_enemy("small-biter", n.x + (i % 5) * 2, n.y + 6 + math.floor(i / 5) * 2)) end
  return list
end

local function alive(list)
  local c = 0
  for _, e in ipairs(list) do if e.valid then c = c + 1 end end
  return c
end

local logistics = require("scripts.logistics")
local ai_mod = require("scripts.ai")

local function run_campaign(mode, variant, style)
  local hard = variant ~= "easy"
  local lasers = variant:find("lasers", 1, true) ~= nil
  H.clear_lake(); H.clear_arena()
  set_setting("sh-threat-awareness", mode)
  set_setting("sh-alert-level", "off")
  if variant == "lasers-close" then set_setting("sh-combat-range", 12) end
  if variant == "lasers-aware" then set_setting("sh-laser-aware-range", true) end
  zoom_to(0, 45, 0.18)
  local spider = spawn_hunter(0, 0)
  if variant ~= "hard" then spider.get_inventory(defines.inventory.spider_ammo).insert({ name = "rocket", count = 600 }) end
  local grid = lasers and H.equip_lasers(spider, 4, 6) or nil
  -- The default-ammo campaign is kept short (2 nests, 100 rockets): the runner aborts if Factorio
  -- prints nothing for 15 s, and ammo must still run out during the run.
  local defs = variant == "hard" and { NESTS[1], NESTS[2] } or NESTS
  if variant == "hard" then
    spider.get_inventory(defines.inventory.spider_ammo).remove({ name = "rocket", count = 100 })
  end
  local nests = {}
  for i, n in ipairs(defs) do
    nests[i] = { def = n, enemies = build_nest(n, hard), repositions = 0, ticks_near = 0, still = 0, max_still = 0,
                 first_near = nil, cleared = nil, start_health = nil }
  end
  remote.call("SpidertronHunter", "enable", spider)
  if style then ai_mod.set_combat_style(spider, style) end

  local trace, last_state = {}, nil
  local restock_entries = 0
  local resupplies, parked_since = 0, nil
  local last_reposition_tick = {}
  local last_pos = spider.position
  local start = game.tick
  local TIME_LIMIT = 60 * (variant == "hard" and 1500 or 420)

  local function summary()
    local lines = { "mode=" .. mode .. " " .. variant .. " style=" .. tostring(style or "default") .. " resupplies=" .. resupplies .. (grid and (" battery=" .. math.floor(H.battery_fraction(grid) * 100) .. "%") or "") .. " t=" .. math.floor((game.tick - start) / 60) .. "s health=" ..
      math.floor(spider.valid and spider.health or 0) }
    for _, n in ipairs(nests) do
      lines[#lines + 1] = string.format(
        "  nest %s: alive=%d/%d near=%ss first_near=%s cleared=%s repositions=%d max_still=%ss start_hp=%s",
        n.def.name, alive(n.enemies), #n.enemies, math.floor(n.ticks_near / 60),
        n.first_near and math.floor((n.first_near - start) / 60) or "never",
        n.cleared and math.floor((n.cleared - start) / 60) or "no", n.repositions,
        math.floor(n.max_still / 60), n.start_health and math.floor(n.start_health) or "-")
    end
    lines[#lines + 1] = "  states: " .. table.concat(trace, " ")
    return table.concat(lines, "\n")
  end

  async(TIME_LIMIT + 120)
  on_tick(function()
    if not spider.valid then error("spider died\n" .. summary()) end
    -- Heartbeat: the test runner aborts if Factorio prints nothing for 15 s.
    if (game.tick - start) % 600 == 0 then log("[multi-nest] " .. mode .. " " .. variant .. " t=" .. math.floor((game.tick - start) / 60) .. "s") end
    local ai = storage.spiders[spider.unit_number]
    local state = ai and ai.state
    if state ~= last_state then
      local cur, des = logistics.ammo_counts(spider, ai)
      trace[#trace + 1] = string.format("%s@%d(hp%d,ammo%d/%d)", tostring(state), math.floor((game.tick - start) / 60),
        math.floor(spider.health), cur or -1, des or -1)
      last_state = state
      if state == "restocking" then restock_entries = restock_entries + 1 end
    end
    local moved = distance(spider.position, last_pos)
    last_pos = spider.position
    for _, n in ipairs(nests) do
      local near = distance(spider.position, n.def) < 55
      if near and alive(n.enemies) > 0 then
        n.first_near = n.first_near or game.tick
        n.start_health = n.start_health or spider.health
        n.ticks_near = n.ticks_near + 1
        if state == "attacking" then
          if moved < 0.02 then n.still = n.still + 1 else n.still = 0 end
          n.max_still = math.max(n.max_still, n.still)
          if ai.combat_last_move_tick and ai.combat_last_move_tick ~= last_reposition_tick[n] then
            last_reposition_tick[n] = ai.combat_last_move_tick
            n.repositions = n.repositions + 1
          end
        end
      end
      if not n.cleared and alive(n.enemies) == 0 then n.cleared = game.tick end
    end
    -- Hard nests with default ammo: nothing resupplies the hunter, so it should park at home
    -- ("waiting" / no-ammo) instead of ping-ponging. Hold it there for a few seconds, then act as
    -- the player would and top up the ammo; it must resume and carry on with the remaining nests.
    if variant == "hard" then
      local out_of_ammo = logistics.ammo_below_threshold(spider, 20, ai)
      if state == "waiting" and ai.wait_reason == "no-ammo" and out_of_ammo then
        parked_since = parked_since or game.tick
        if game.tick - parked_since > 60 * 8 then
          spider.get_inventory(defines.inventory.spider_ammo).insert({ name = "rocket", count = 200 })
          resupplies = resupplies + 1
          parked_since = nil
        end
      elseif parked_since and out_of_ammo then
        error("hunter left its parking spot without ammo (state " .. tostring(state) .. ")\n" .. summary())
      else
        parked_since = nil
      end
    end
    local all_clear = true
    for _, n in ipairs(nests) do if alive(n.enemies) > 0 then all_clear = false end end
    if all_clear or game.tick - start > TIME_LIMIT then
      log("[multi-nest]\n" .. summary())
      local report = summary()
      if variant == "hard" then
        -- one trip home per resupply (plus the first): more means the hunter went back out unfit
        assert(resupplies >= 1, "hunter never ran out of ammo; scenario no longer exercises parking\n" .. report)
        assert(restock_entries <= resupplies + 2, "restock ping-pong: " .. restock_entries
          .. " trips home for " .. resupplies .. " resupplies\n" .. report)
      end
      if lasers then
        assert(H.battery_fraction(grid) < 0.999, "lasers never fired (battery untouched)\n" .. report)
      end
      if style then
        local ai = storage.spiders[spider.unit_number]
        local applied = ({ strafe = ai.strafe_sign, circle = ai.orbit_angle, flank = ai.flank_sign })[style]
        assert(applied ~= nil, "combat style '" .. style .. "' never took effect\n" .. report)
      end
      assert(all_clear, "campaign not finished\n" .. report)
      for _, n in ipairs(nests) do
        -- A nest the hunter wipes out within a few seconds legitimately sees little kiting.
        if n.cleared and n.ticks_near >= 60 * 8 then
          assert(n.repositions >= 3, "nest " .. n.def.name .. ": hunter barely kited (" .. n.repositions
            .. " repositions)\n" .. report)
        end
        assert(n.max_still < 60 * 5, "nest " .. n.def.name .. ": hunter attacked from a standstill for "
          .. math.floor(n.max_still / 60) .. "s\n" .. report)
      end
      done()
    end
  end)
end

tags("visual")
describe("multi-nest campaign", function()
  after_each(function() H.clear_arena() end)
  -- Every moving combat style (hold is stationary by design) with rockets only and with lasers.
  for _, style in ipairs({ "strafe", "circle", "flank" }) do
    for _, variant in ipairs({ "stocked", "lasers", "lasers-close" }) do
      test("three hard nests, " .. style .. " style (" .. variant .. ")", function()
        run_campaign("normal", variant, style)
      end)
    end
  end
  test("three hard nests, laser-aware range", function() run_campaign("normal", "lasers-aware", "strafe") end)
  for _, mode in ipairs({ "off", "normal", "cautious" }) do
    test("three nests, TA " .. mode .. " (easy)", function() run_campaign(mode, "easy") end)
    test("three hard nests, TA " .. mode .. " (default ammo)", function() run_campaign(mode, "hard") end)
    test("three hard nests, TA " .. mode .. " (stocked ammo)", function() run_campaign(mode, "stocked") end)
  end
end)
