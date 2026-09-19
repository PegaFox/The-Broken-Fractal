-- The functions and tables defined in this file are automatically namespaced, and as such are an exception to the no globals rule
-- self is an alias for fractal.mods.modName.levels.levelName
init = {
  name = "level0"
}

function deinit(self)

end

function enter(self)
  -- Remove extra tiles after this if possible
  self.tiles.max = 400
  
  print("Hello, Level 0!");
  --try Level.objects.append(init.gpa, .init(0, .{0, 0}, .{
  --  .sight = Sight{.radius = 15, .view = .empty},
  --  .tileMemory = TileMemory{.tiles = .empty},
  --}));
  --try Turn.push(init.gpa, &ecs, Level.objects.getLast());
  --defer Turn.queue.deinit(init.gpa);

  --defer ecs.getPtr(
  --  Level.objects.items[0].id, "tileMemory", TileMemory
  --).?.tiles.deinit(init.gpa);
  --defer ecs.getPtr(
  --  Level.objects.items[0].id, "sight", Sight
  --).?.view.deinit(init.gpa);

  -- Oh, no! It's not lore accurate!
  self.objects:add(
    {"base", "smiler"},
    {pos = {30, 30}}
  )

end

function exit(self)

end

local function removeExtraTiles(self)
  self.tiles.max = 400

  local player = fractal.mods.base.player
  local playerPos = player.pos:get()

  for k, _ in self.tiles:iterate() do
    if self.tiles:count() <= self.tiles.max then
      break
    end

    -- Use approximation for distance since this could be done several times per turn
    local dis = math.abs(k[1]-playerPos[1]) + math.abs(k[2]-playerPos[2])
    if dis > 10 and not player.sight:inView(k) then
      print("Remove tile { ", k[1], ", ", k[2], " }")
      self.tiles:remove(k)
      -- May need to resync iterator at this point
    end
  end
end

function update(self)
  self.camera:centerOn(fractal.mods.base.player)

  --local array = {1, 1, 2, 3, 5, 8, 13, 21}
  --local function iterator(array)
  --  local index = 0
  --  return 
  --   function()
  --     index = index + 1
  --     if index > #array then
  --       return nil
  --     else
  --       return array[index]
  --     end
  --   end
  --end

  --for element in iterator(array) do
  --  print(element)
  --end

  removeExtraTiles(self)
end

function generateTile(self, pos)
  --return fractal.mods.base.levels.level1:generateTile(pos)
  local originDis = math.abs(pos[1]) + math.abs(pos[2])

  local result = nil
  if pos[1]%2 == 1 and pos[2]%2 == 1 then
    result = {"base", "cyanideCarpet"}
  elseif pos[1]%2 == 0 and pos[2]%2 == 0 then
    result = {"base", "yellowWallpaper"}
  else
    --if originDis > 4 and math.random(0, 3) == 0 then
    --if math.random(0, math.max(3, 32-math.floor(originDis))) == 0 then
    if math.random(0, 3) == 0 then
      result = {"base", "yellowWallpaper"}
    else
      result = {"base", "cyanideCarpet"}
    end
  end

  if pos[1]%2 == 0 and pos[2]%2 == 0 and
    self.tiles:get({pos[1]-1, pos[2]}):typeData().walkable and
    self.tiles:get({pos[1]+1, pos[2]}):typeData().walkable and
    self.tiles:get({pos[1], pos[2]-1}):typeData().walkable and
    self.tiles:get({pos[1], pos[2]+1}):typeData().walkable
  then
    result = {"base", "cyanideCarpet"}
  end

  --print("Generate "..result[1].." at {"..tostring(pos).."}")
  return result
end

