-- In-game smoke tests, run by factorio-test (scripts/run_factorio_tests.sh).
describe("SpidertronHunter loads", function()
  test("mod is active", function()
    assert(script.active_mods["SpidertronHunter"], "mod not active")
  end)

  test("custom input prototypes exist", function()
    assert(prototypes.custom_input["sh-toggle-autonomy"], "custom input missing")
  end)

  test("can spawn a spidertron", function()
    local s = game.surfaces[1]
    local spider = s.create_entity({ name = "spidertron", position = { 0, 0 }, force = "player" })
    assert(spider and spider.valid, "spidertron not created")
    spider.destroy()
  end)
end)
