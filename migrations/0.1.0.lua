-- v0.1.0: initial storage shape.
-- spiders, enemy_cache, target_claims, destroy_regs, path_requests,
-- path_statuses, scan/think cursors, settings_cache, next_cache_id.
local persistence = require("scripts.persistence")
persistence.init_storage()
