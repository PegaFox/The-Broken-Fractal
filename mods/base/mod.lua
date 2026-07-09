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
      energy = {value = 100, rate = -1},
      food = {value = 100, rate = -1},
      fluid = {value = 100, rate = -1},
      sanity = {value = 100, rate = -1},
    }
  )

  fractal.mods.base.player = self.levels.level0.objects.get(0)
end

function update(self)

  if self.player.energy.value.get() == 0 then
    print("Oh boy! Looks like you ran out of energy!")
  end

  self.player.memory.draw()
  self.player.sight.draw()
end
