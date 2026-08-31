-- Building-aware pathfinding layer (adapted from Spidertron Enhancements; see NOTICE).
if data.raw["collision-layer"] and data.raw["collision-layer"]["large_entity"] then
  return
end

local math2d = require("math2d")
local collision_mask_util = require("__core__/lualib/collision-mask-util")

local prototypes = collision_mask_util.collect_prototypes_with_layer("player")

local function collision_box_too_large(collision_box)
  local left_top = math2d.position.ensure_xy(collision_box[1] or collision_box.left_top)
  local right_bottom = math2d.position.ensure_xy(collision_box[2] or collision_box.right_bottom)
  local width = math.abs(right_bottom.x - left_top.x)
  local height = math.abs(right_bottom.y - left_top.y)
  return width > 9 and height > 9
end

local large_entity_found = false
for _, prototype in pairs(prototypes) do
  if prototype.type ~= "tile" and prototype.collision_box and collision_box_too_large(prototype.collision_box) then
    local collision_mask = collision_mask_util.get_mask(prototype)
    collision_mask.layers["large_entity"] = true
    prototype.collision_mask = collision_mask
    large_entity_found = true
  end
end

if large_entity_found then
  for _, prototype in pairs(prototypes) do
    if prototype.type == "tile" then
      local collision_mask = collision_mask_util.get_mask(prototype)
      collision_mask.layers["large_entity"] = true
      prototype.collision_mask = collision_mask
    end
  end
end

if large_entity_found then
  data:extend({
    {
      type = "collision-layer",
      name = "large_entity",
    },
  })
end
