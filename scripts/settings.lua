--- Cached runtime-global settings. Refresh on change; never read settings.global in hot loops.
local M = {}

local DEFAULTS = {
  search_radius = 256,
  max_pursuit_distance = 512,
  scan_interval = 60,
  scan_budget = 4,
  return_home_after_combat = true,
  restock_enabled = true,
  repair_enabled = true,
  max_restock_ticks = 3600,
  enemy_prioritization = "nearest",
  max_idle_time = 600,
  spiders_per_think = 8,
  enemy_cache_ttl = 18000,
  debug_mode = false,
}

--- @return table
function M.refresh()
  local g = settings.global
  local cache = {
    search_radius = g["sh-search-radius"].value,
    max_pursuit_distance = g["sh-max-pursuit-distance"].value,
    scan_interval = g["sh-scan-interval"].value,
    scan_budget = g["sh-scan-budget"].value,
    return_home_after_combat = g["sh-return-home-after-combat"].value,
    restock_enabled = g["sh-restock-enabled"].value,
    repair_enabled = g["sh-repair-enabled"].value,
    max_restock_ticks = g["sh-max-restock-ticks"].value,
    enemy_prioritization = g["sh-enemy-prioritization"].value,
    max_idle_time = g["sh-max-idle-time"].value,
    spiders_per_think = g["sh-spiders-per-think"].value,
    enemy_cache_ttl = g["sh-enemy-cache-ttl"].value,
    debug_mode = g["sh-debug-mode"].value,
  }
  storage.settings_cache = cache
  return cache
end

--- @return table
function M.get()
  return storage.settings_cache or M.refresh()
end

M.DEFAULTS = DEFAULTS

return M
