--- storage schema, destroy registration, configuration migrations.
local util = require("scripts.util")
local pathfinder = require("scripts.pathfinder")
local schema = require("scripts.schema")

local M = {}

function M.init_storage()
  schema.ensure_storage()
end

--- Full schema migrate used by versioned migration scripts.
function M.migrate()
  schema.migrate_ai_records()
end

--- @param spidertron LuaEntity
--- @return table SpiderAI
function M.create_ai(spidertron)
  local unit_number = spidertron.unit_number
  local reg = script.register_on_object_destroyed(spidertron)
  storage.destroy_regs[reg] = unit_number

  local ai = {
    entity = spidertron,
    unit_number = unit_number,
    state = "idle",
    home = {
      surface_index = spidertron.surface_index,
      x = spidertron.position.x,
      y = spidertron.position.y,
    },
    target_entity = nil,
    target_pos = nil,
    claim_id = nil,
    state_entered_tick = game.tick,
    next_think_tick = 0,
    scan_offset = 0,
    path_request_ids = {},
    pending_goal = nil,
    path_start_tick = nil,
    wait_reason = nil,
  }
  storage.spiders[unit_number] = ai
  return ai
end

--- @param unit_number integer
function M.remove_ai(unit_number)
  local ai = storage.spiders[unit_number]
  if not ai then
    return
  end
  if ai.claim_id and storage.target_claims[ai.claim_id] == unit_number then
    storage.target_claims[ai.claim_id] = nil
  end
  storage.spiders[unit_number] = nil
  if storage.path_statuses[unit_number] then
    storage.path_statuses[unit_number] = nil
  end
  pathfinder.clear_queue_for(unit_number)
end

--- @param event EventData.on_object_destroyed
function M.on_object_destroyed(event)
  local unit_number = storage.destroy_regs[event.registration_number]
  if not unit_number then
    return
  end
  storage.destroy_regs[event.registration_number] = nil
  M.remove_ai(unit_number)
end

--- Remap AI when a spidertron entity is replaced (unit_number change).
--- @param old_unit_number integer
--- @param new_spidertron LuaEntity
function M.remap_spidertron(old_unit_number, new_spidertron)
  local ai = storage.spiders[old_unit_number]
  if not ai or not util.is_valid_spidertron(new_spidertron) then
    return
  end
  storage.spiders[old_unit_number] = nil
  local reg = script.register_on_object_destroyed(new_spidertron)
  storage.destroy_regs[reg] = new_spidertron.unit_number
  ai.entity = new_spidertron
  ai.unit_number = new_spidertron.unit_number
  storage.spiders[new_spidertron.unit_number] = ai
  if ai.claim_id then
    storage.target_claims[ai.claim_id] = new_spidertron.unit_number
  end
end

--- @param unit_number integer
--- @return table?
function M.get_ai(unit_number)
  return storage.spiders[unit_number]
end

--- @param spidertron LuaEntity
--- @return table?
function M.get_ai_for_entity(spidertron)
  if not spidertron or not spidertron.valid or not spidertron.unit_number then
    return nil
  end
  return storage.spiders[spidertron.unit_number]
end

return M
