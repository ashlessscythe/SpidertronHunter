--- Restock / repair wait at Home. Timeout always wins — never stuck forever.
--- Limitation: no LuaEntity.repair(); we wait for robots / logistics only.
local settings_mod = require("scripts.settings")
local util = require("scripts.util")

local M = {}

--- @param spidertron LuaEntity
--- @return boolean
local function ammo_looks_empty(spidertron)
  local ammo = spidertron.get_inventory(defines.inventory.spider_ammo)
  if not ammo then
    return false
  end
  return ammo.is_empty()
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
      -- Wait a settle period so bots can deliver; if ammo still empty keep waiting until timeout.
      if elapsed < 180 then
        waiting = true
      elseif ammo_looks_empty(spidertron) and elapsed < cfg.max_restock_ticks then
        waiting = true
      end
    elseif elapsed < 60 then
      -- Brief wait in case network membership updates after arrival.
      waiting = true
    end
  end

  return not waiting
end

return M
