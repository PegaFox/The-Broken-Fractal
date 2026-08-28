-- This mod currently does not work with other mods (kind of ruins the point of mods, doesn't it?)

function init(self)
  print("Hello from The Broken Fractal!")
  
  --print(fractal)
  --for k,v in pairs(_G) do
  --  if k ~= "_G" then
  --    print(k, ": ", v, ",")
  --  end
  --end
  --
  --for k,v in ipairs(_G) do
  --  print(k, ": ", v, ",")
  --end

  self.levels.level0.objects:add(
    {"base", "player"},
    {
      pos = {0, 0},
      sight = {radius = 15},
      memory = {},
      inventory = {capacity = 5, items = {}},
      energy = {value = 60 * 60 * 16, rate = -1},
      stamina = {value = 60 * 20, rate = 0},
      food = {value = 60 * 60 * 12, rate = -1},
      fluid = {value = 60 * 60 * 4, rate = -1},
      sanity = {value = 100, rate = -1},
    }
  )

  self.player = self.levels.level0.objects.get(0)

  self.levels.level0.objects:add(
    {"base", "backpack"},
    {
      inventory = {capacity = 5, items = {}},
    }
  )
  local backpack = self.levels.level0.objects.get(1)
  self.player.inventory[0] = backpack
end

function update(self)

  if self.player.energy.value.get() == 0 then
    print("Oh boy! Looks like you ran out of energy!")
  end

  self.player.memory.draw()
  self.player.sight.draw()
end
