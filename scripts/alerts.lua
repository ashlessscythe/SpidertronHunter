--- Player alerts for hunter/scout trouble: retreat, stuck, low ammo, destroyed.
--- Controlled by the "sh-alert-level" setting; each kind is throttled per spider so a fleet in
--- trouble does not spam. Alerts use Factorio's custom alerts (edge-of-screen icon, click to locate);
--- a destroyed spidertron has no entity left to point at, so that one is a chat line with a map ping.
local settings_mod = require("scripts.settings")

local M = {}

M.COOLDOWN_TICKS = 1800
M.STUCK_REPATHS_BEFORE_ALERT = 3

local LEVELS = { off = 0, important = 1, all = 2 }
--- Minimum level at which each kind is shown.
local KIND_LEVEL = {
  died = 1, retreat = 1, stuck = 1, ["too-dangerous"] = 1, ["out-of-ammo"] = 1, ["needs-repair"] = 1, ["low-ammo"] = 2,
}
--- Conditions that persist until the player acts re-alert far less often.
local KIND_COOLDOWN = { ["out-of-ammo"] = 18000, ["needs-repair"] = 18000 }

local ICON = { type = "item", name = "spidertron" }
local DIED_COLOR = { r = 1, g = 0.4, b = 0.3 }

--- @param kind string
--- @return boolean
function M.is_enabled(kind)
  local level = LEVELS[settings_mod.get().alert_level or "important"] or 0
  return level >= (KIND_LEVEL[kind] or math.huge)
end

--- @param entity LuaEntity
--- @return LocalisedString
local function label(entity)
  local name = entity.entity_label
  if name and name ~= "" then
    return name
  end
  return entity.localised_name or entity.name
end

--- Returns true when this kind is off cooldown for the spider (and starts the cooldown).
--- @param ai table
--- @param kind string
--- @return boolean
local function pass_cooldown(ai, kind)
  ai.alert_ticks = ai.alert_ticks or {}
  local last = ai.alert_ticks[kind]
  if last and game.tick - last < (KIND_COOLDOWN[kind] or M.COOLDOWN_TICKS) then
    return false
  end
  ai.alert_ticks[kind] = game.tick
  return true
end

--- Show an alert for a live spidertron.
--- @param spidertron LuaEntity
--- @param kind "retreat"|"stuck"|"low-ammo"|"too-dangerous"|"out-of-ammo"|"needs-repair"
--- @param ai table
--- @param detail any? extra locale parameter (e.g. health percent)
--- @return boolean shown
function M.notify(spidertron, kind, ai, detail)
  if not ai or not spidertron or not spidertron.valid or not M.is_enabled(kind) then
    return false
  end
  if not pass_cooldown(ai, kind) then
    return false
  end
  local message = { "sh.alert-" .. kind, label(spidertron), detail }
  for _, player in pairs(spidertron.force.connected_players) do
    if player.valid then
      player.add_custom_alert(spidertron, ICON, message, true)
    end
  end
  return true
end

--- Chat line (with clickable map ping) for a spidertron that was just destroyed.
--- Call from on_entity_died while the entity is still valid.
--- @param entity LuaEntity
--- @return boolean shown
function M.died(entity)
  if not entity or not entity.valid or not M.is_enabled("died") then
    return false
  end
  local pos = entity.position
  local gps = string.format("[gps=%d,%d,%s]", math.floor(pos.x), math.floor(pos.y), entity.surface.name)
  entity.force.print({ "sh.alert-died", label(entity), gps }, DIED_COLOR)
  return true
end

--- Count one stuck re-path for a spider; alerts once enough accumulate in the same place.
--- @param spidertron LuaEntity
--- @param ai table?
function M.on_stuck_repath(spidertron, ai)
  if not ai then
    return
  end
  local pos = spidertron.position
  local last = ai.stuck_count_pos
  if last and (pos.x - last.x) ^ 2 + (pos.y - last.y) ^ 2 > 20 * 20 then
    ai.stuck_count = 0
  end
  ai.stuck_count_pos = { x = pos.x, y = pos.y }
  ai.stuck_count = (ai.stuck_count or 0) + 1
  if ai.stuck_count >= M.STUCK_REPATHS_BEFORE_ALERT then
    ai.stuck_count = 0
    M.notify(spidertron, "stuck", ai)
  end
end

return M
