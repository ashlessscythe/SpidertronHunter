--- Shared global enemy cache. Discover via scanner; prune on death / TTL.
local util = require("scripts.util")
local settings_mod = require("scripts.settings")

local M = {}

local function surface_bucket(surface_index)
  local bucket = storage.enemy_cache[surface_index]
  if not bucket then
    bucket = {}
    storage.enemy_cache[surface_index] = bucket
  end
  return bucket
end

--- @param entity LuaEntity
--- @return integer cache_id
function M.remember(entity)
  if not entity or not entity.valid then
    return nil
  end
  local bucket = surface_bucket(entity.surface_index)
  local key = util.chunk_key(entity.position)

  -- Update existing entry in same chunk if same entity / nearby.
  local list = bucket[key]
  if list then
    for i = 1, #list do
      local entry = list[i]
      if entry.entity and entry.entity.valid and entry.entity == entity then
        entry.last_seen = game.tick
        entry.position = { x = entity.position.x, y = entity.position.y }
        entry.name = entity.name
        entry.type = entity.type
        return entry.id
      end
    end
  else
    list = {}
    bucket[key] = list
  end

  local id = storage.next_cache_id
  storage.next_cache_id = id + 1
  list[#list + 1] = {
    id = id,
    position = { x = entity.position.x, y = entity.position.y },
    surface_index = entity.surface_index,
    entity = entity,
    name = entity.name,
    type = entity.type,
    last_seen = game.tick,
  }
  return id
end

--- @param cache_id integer
--- @return table?
function M.get(cache_id)
  for _, bucket in pairs(storage.enemy_cache) do
    for _, list in pairs(bucket) do
      for i = 1, #list do
        if list[i].id == cache_id then
          return list[i]
        end
      end
    end
  end
  return nil
end

--- @param cache_id integer
function M.remove(cache_id)
  for surface_index, bucket in pairs(storage.enemy_cache) do
    for key, list in pairs(bucket) do
      for i = #list, 1, -1 do
        if list[i].id == cache_id then
          table.remove(list, i)
          if storage.target_claims[cache_id] then
            storage.target_claims[cache_id] = nil
          end
          if #list == 0 then
            bucket[key] = nil
          end
          return
        end
      end
    end
  end
end

--- Remove by entity reference (death handler).
--- @param entity LuaEntity
function M.remove_entity(entity)
  if not entity then
    return
  end
  local surface_index = entity.surface_index
  local bucket = storage.enemy_cache[surface_index]
  if not bucket then
    return
  end
  local key = util.chunk_key(entity.position)
  local list = bucket[key]
  if not list then
    -- Fallback: scan surface bucket (entity may have moved).
    for _, l in pairs(bucket) do
      for i = #l, 1, -1 do
        local e = l[i]
        if e.entity == entity or (e.name == entity.name and util.distance_squared(e.position, entity.position) < 4) then
          local id = e.id
          table.remove(l, i)
          storage.target_claims[id] = nil
        end
      end
    end
    return
  end
  for i = #list, 1, -1 do
    if list[i].entity == entity or list[i].name == entity.name then
      local id = list[i].id
      table.remove(list, i)
      storage.target_claims[id] = nil
    end
  end
  if #list == 0 then
    bucket[key] = nil
  end
end

--- Expire old / invalid entries. Budget-limited.
--- @param budget integer?
function M.prune(budget)
  budget = budget or 8
  local ttl = settings_mod.get().enemy_cache_ttl
  local tick = game.tick
  local checked = 0

  for surface_index, bucket in pairs(storage.enemy_cache) do
    for key, list in pairs(bucket) do
      for i = #list, 1, -1 do
        checked = checked + 1
        local entry = list[i]
        local dead = not entry.entity or not entry.entity.valid
        local expired = (tick - entry.last_seen) > ttl
        if dead or expired then
          storage.target_claims[entry.id] = nil
          table.remove(list, i)
        end
        if checked >= budget then
          if #list == 0 then
            bucket[key] = nil
          end
          return
        end
      end
      if #list == 0 then
        bucket[key] = nil
      end
    end
  end
end

--- Find best cached enemy near position within radius.
--- Soft claims: prefer unclaimed, but still return claimed targets so multiple
--- spiders can converge on the same nest.
--- @param surface_index integer
--- @param position MapPosition
--- @param radius number
--- @param spider_unit_number integer
--- @param prioritization string
--- @return table? entry
function M.find_near(surface_index, position, radius, spider_unit_number, prioritization)
  local bucket = storage.enemy_cache[surface_index]
  if not bucket then
    return nil
  end

  local radius_sq = radius * radius
  local best = nil
  local best_score = 1e18

  for _, list in pairs(bucket) do
    for i = 1, #list do
      local entry = list[i]
      if not entry.entity or not entry.entity.valid then
        goto continue
      end
      local dsq = util.distance_squared(position, entry.position)
      if dsq > radius_sq then
        goto continue
      end

      local score = dsq
      local claimer = storage.target_claims[entry.id]
      if claimer and claimer ~= spider_unit_number then
        -- Soft preference only — do not skip.
        score = score + 1e6
      end
      if prioritization == "spawners-first" then
        if entry.type == "unit-spawner" then
          score = score - 1e10
        elseif entry.type == "turret" then
          score = score - 1e9
        end
      elseif prioritization == "units-first" then
        if entry.type == "unit" then
          score = score - 1e10
        end
      end

      if score < best_score then
        best_score = score
        best = entry
      end
      ::continue::
    end
  end

  return best
end

--- Wipe all cache entries and claims.
function M.reset()
  storage.enemy_cache = {}
  storage.target_claims = {}
  storage.next_cache_id = 1
end

--- Debug snapshot of cache sizes.
--- @return table
function M.debug_stats()
  local entries = 0
  local surfaces = 0
  for _, bucket in pairs(storage.enemy_cache) do
    surfaces = surfaces + 1
    for _, list in pairs(bucket) do
      entries = entries + #list
    end
  end
  local claims = 0
  for _ in pairs(storage.target_claims) do
    claims = claims + 1
  end
  return {
    surfaces = surfaces,
    entries = entries,
    claims = claims,
  }
end

return M
