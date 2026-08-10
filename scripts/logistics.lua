--- Restock / repair wait at Home. Timeout always wins — never stuck forever.
--- Limitation: no LuaEntity.repair(); we wait for robots / logistics only.
--- Ammo % is current / logistic ammo request (not stack capacity). Fallback: ammo count at enable.
local settings_mod = require("scripts.settings")
local util = require("scripts.util")

local M = {}

local SPIDER_AMMO = (defines and defines.inventory and defines.inventory.spider_ammo) or "spider_ammo"
local DEFAULT_QUALITY = "normal"

--- @param name string
--- @param quality string?
--- @return string
function M.ammo_request_key(name, quality)
  return name .. "\0" .. (quality or DEFAULT_QUALITY)
end

--- @param name string
--- @return boolean
local function is_ammo_item(name)
  if not name or not prototypes or not prototypes.item then
    return false
  end
  local proto = prototypes.item[name]
  return proto ~= nil and proto.ammo_category ~= nil
end

--- @param quality any
--- @return string
local function quality_name(quality)
  if quality == nil then
    return DEFAULT_QUALITY
  end
  if type(quality) == "string" then
    return quality
  end
  if type(quality) == "table" and quality.name then
    return quality.name
  end
  return DEFAULT_QUALITY
end

--- @param filter table|string?
--- @return string? name
--- @return string quality
local function filter_item_and_quality(filter)
  if not filter then
    return nil, DEFAULT_QUALITY
  end
  local value = filter.value
  if type(value) == "string" then
    return value, DEFAULT_QUALITY
  end
  if type(value) == "table" then
    return value.name, quality_name(value.quality)
  end
  if filter.name then
    return filter.name, quality_name(filter.quality)
  end
  return nil, DEFAULT_QUALITY
end

--- Sum logistic request mins for ammo items (section multiplier + quality).
--- Keys are name\\0quality via ammo_request_key.
--- @param spidertron LuaEntity|table
--- @return table<string, integer> requested_by_key
--- @return integer total
function M.ammo_request_totals(spidertron)
  local requested = {}
  local total = 0
  if not spidertron then
    return requested, total
  end

  local point = nil
  if type(spidertron.get_requester_point) == "function" then
    point = spidertron.get_requester_point()
  end
  if not point and type(spidertron.get_logistic_point) == "function" then
    local idx = defines
      and defines.logistic_member_index
      and defines.logistic_member_index.spidertron_requester
    if idx ~= nil then
      point = spidertron.get_logistic_point(idx)
    end
  end
  if not point then
    return requested, total
  end

  local function add_filter(filter, multiplier)
    local name, quality = filter_item_and_quality(filter)
    local min = filter and filter.min or 0
    if not name or not min or min <= 0 then
      return
    end
    if not is_ammo_item(name) then
      return
    end
    local amt = math.floor(min * (multiplier or 1) + 0.5)
    if amt <= 0 then
      return
    end
    local key = M.ammo_request_key(name, quality)
    requested[key] = (requested[key] or 0) + amt
    total = total + amt
  end

  local sections = point.sections
  if sections then
    for i = 1, #sections do
      local section = sections[i]
      if section and section.active ~= false then
        local mult = section.multiplier or 1
        local filters = section.filters
        if filters then
          for j = 1, #filters do
            add_filter(filters[j], mult)
          end
        end
      end
    end
  elseif point.filters then
    local filters = point.filters
    for i = 1, #filters do
      add_filter(filters[i], 1)
    end
  end

  return requested, total
end

--- Total items currently in spider_ammo (all qualities).
--- @param spidertron LuaEntity|table
--- @return integer
function M.total_ammo_count(spidertron)
  if not spidertron or type(spidertron.get_inventory) ~= "function" then
    return 0
  end
  local ammo = spidertron.get_inventory(SPIDER_AMMO)
  if not ammo then
    return 0
  end
  if ammo.is_empty and ammo.is_empty() then
    return 0
  end
  -- Prefer stack walk so mixed qualities are all counted (string get_item_count is normal-only).
  local n = 0
  for i = 1, #ammo do
    local stack = ammo[i]
    if stack and stack.valid_for_read then
      n = n + (stack.count or 0)
    end
  end
  if n == 0 and type(ammo.get_item_count) == "function" then
    return ammo.get_item_count() or 0
  end
  return n
end

--- Count on-hand ammo matching request keys (name+quality).
--- @param spidertron LuaEntity|table
--- @param requested table<string, integer>?
--- @return integer
function M.count_ammo_for_requests(spidertron, requested)
  if not spidertron or type(spidertron.get_inventory) ~= "function" then
    return 0
  end
  local ammo = spidertron.get_inventory(SPIDER_AMMO)
  if not ammo then
    return 0
  end
  if not requested or next(requested) == nil then
    return M.total_ammo_count(spidertron)
  end

  local current = 0
  -- Prefer quality-aware API: string item name counts normal only.
  if type(ammo.get_item_count) == "function" then
    for key in pairs(requested) do
      local name, quality = key:match("^(.-)\0(.*)$")
      if name then
        current = current + (ammo.get_item_count({ name = name, quality = quality }) or 0)
      end
    end
    return current
  end

  for i = 1, #ammo do
    local stack = ammo[i]
    if stack and stack.valid_for_read then
      local key = M.ammo_request_key(stack.name, quality_name(stack.quality))
      if requested[key] then
        current = current + (stack.count or 0)
      end
    end
  end
  return current
end

--- Desired ammo count + current on-hand. Prefer logistic ammo requests; else ai.ammo_baseline.
--- @param spidertron LuaEntity|table
--- @param ai table?
--- @return integer current
--- @return integer desired
function M.ammo_counts(spidertron, ai)
  local requested, desired = M.ammo_request_totals(spidertron)
  if desired > 0 then
    return M.count_ammo_for_requests(spidertron, requested), desired
  end
  local baseline = ai and ai.ammo_baseline or 0
  local current = M.total_ammo_count(spidertron)
  if baseline > 0 then
    return current, baseline
  end
  -- No request / baseline: empty → 0 desired signal via current only.
  return current, 0
end

--- Snapshot total ammo for enable-time baseline fallback.
--- @param spidertron LuaEntity|table
--- @return integer
function M.snapshot_ammo_baseline(spidertron)
  return M.total_ammo_count(spidertron)
end

--- current/desired clamped to 0–1. No desired: empty→0 else→1.
--- @param current number
--- @param desired number
--- @return number
function M.ratio_from_counts(current, desired)
  if not desired or desired <= 0 then
    if not current or current <= 0 then
      return 0
    end
    return 1
  end
  if not current or current <= 0 then
    return 0
  end
  return math.min(1, current / desired)
end

--- Fill ratio vs logistic ammo request (or enable baseline). Missing inv → full.
--- @param spidertron LuaEntity|table
--- @param ai table?
--- @return number
function M.ammo_fill_ratio(spidertron, ai)
  if not spidertron or not spidertron.get_inventory then
    return 1
  end
  local current, desired = M.ammo_counts(spidertron, ai)
  return M.ratio_from_counts(current, desired)
end

--- Short debug summary: "ammo 500/500" or "ammo 0 (no req)".
--- @param spidertron LuaEntity|table
--- @param ai table?
--- @return string
function M.ammo_debug_summary(spidertron, ai)
  local current, desired = M.ammo_counts(spidertron, ai)
  if desired > 0 then
    return "ammo " .. tostring(current) .. "/" .. tostring(desired)
  end
  return "ammo " .. tostring(current) .. " (no req)"
end

--- True when percent > 0 and fill is at or below that percent (e.g. 2/10 at 20%).
--- @param ratio number
--- @param percent number
--- @return boolean
function M.ratio_at_or_below_percent(ratio, percent)
  if not percent or percent <= 0 then
    return false
  end
  return (ratio or 0) * 100 <= percent
end

--- @param spidertron LuaEntity|table
--- @param percent number
--- @param ai table?
--- @return boolean
function M.ammo_below_threshold(spidertron, percent, ai)
  if not percent or percent <= 0 then
    return false
  end
  return M.ratio_at_or_below_percent(M.ammo_fill_ratio(spidertron, ai), percent)
end

--- @param spidertron LuaEntity
--- @return boolean needs_repair
function M.needs_repair(spidertron)
  if not spidertron.valid then
    return false
  end
  local health = spidertron.health
  local max_health = spidertron.max_health
  if not health or not max_health then
    return false
  end
  return health < max_health
end

--- @param spidertron LuaEntity
--- @return boolean in_network
function M.in_logistic_network(spidertron)
  return spidertron.valid and spidertron.logistic_network ~= nil
end

--- @param ai table
--- @return boolean done  true = finished waiting (success or give up)
function M.update_restock(ai)
  local spidertron = ai.entity
  if not util.is_valid_spidertron(spidertron) then
    return true
  end

  local cfg = settings_mod.get()
  local elapsed = game.tick - ai.state_entered_tick
  if elapsed >= cfg.max_restock_ticks then
    util.debug_log("restock timeout", spidertron)
    return true
  end

  if not cfg.restock_enabled and not cfg.repair_enabled then
    return true
  end

  local waiting = false

  if cfg.repair_enabled and M.needs_repair(spidertron) then
    if M.in_logistic_network(spidertron) or spidertron.is_registered_for_repair() then
      waiting = true
    elseif elapsed < 180 then
      waiting = true
    end
  end

  if cfg.restock_enabled and ai.role ~= "scout" then
    if M.in_logistic_network(spidertron) then
      -- Wait a settle period so bots can deliver; then wait until requests filled (or empty→any).
      if elapsed < 180 then
        waiting = true
      else
        local current, desired = M.ammo_counts(spidertron, ai)
        if desired > 0 then
          if current < desired and elapsed < cfg.max_restock_ticks then
            if elapsed == 180 or elapsed % 300 == 0 then
              util.debug_log(M.ammo_debug_summary(spidertron, ai) .. " wait", spidertron)
            end
            waiting = true
          end
        elseif current <= 0 and elapsed < cfg.max_restock_ticks then
          waiting = true
        end
      end
    elseif elapsed < 60 then
      -- Brief wait in case network membership updates after arrival.
      waiting = true
    end
  end

  return not waiting
end

return M
