-- The functions defined in this file are automatically namespaced, and as such are an exception to the no globals rule
-- self is an alias for fractal.mods.modName.levels.levelName
function init(self)
  -- Remove extra tiles after this if possible
  self.tiles.max = 400
  
  local used = {}
  local display
  display = function(used, table)
    for key, value in pairs(table) do
      if used[value] == nil then
        used[value] = true
        if type(value) == "table" then
          print(key, " = ")
          display(used, value)
        else
          print(key, " = ", value)
        end
      end
    end
  end

  print("Hello, Level 0!");
  --display(used, self)

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
  self.objects:add(
    {"base", "player"},
    {pos = {0, 0}, sight = {radius = 15}, memory = {}}
  )
  -- Oh, no! It's not lore accurate!
  self.objects:add(
    {"base", "smiler"},
    {pos = {30, 30}}
  )
end

function deinit(self)

end

function enter(self)

end

function exit(self)

end

local function removeExtraTiles(self)
  self.tiles.max = 400
  for k, _ in self.tiles:iterate() do
    if self.tiles:count() <= self.tiles.max then
      break
    end

    if not self.objects:get(0).sight:inView(k) then
      print("Remove tile { ", k[1], ", ", k[2], " }")
      self.tiles:remove(k)
      -- May need to resync iterator at this point
    end
  end
end

function update(self)
  self.camera:centerOn(self.objects:get(0))

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
  local result = nil
  if pos[1]%2 == 1 and pos[2]%2 == 1 then
    result = {"base", "cyanideCarpet"}
  elseif pos[1]%2 == 0 and pos[2]%2 == 0 then
    result = {"base", "yellowWallpaper"}
  else
    if math.random(0, 3) == 0 then
      result = {"base", "yellowWallpaper"}
    else
      result = {"base", "cyanideCarpet"}
    end
  end

  if pos[1]%2 == 0 and pos[2]%2 == 0 and
    self.tiles:getInfo({pos[1]-1, pos[2]}).walkable and
    self.tiles:getInfo({pos[1]+1, pos[2]}).walkable and
    self.tiles:getInfo({pos[1], pos[2]-1}).walkable and
    self.tiles:getInfo({pos[1], pos[2]+1}).walkable
  then
    result = {"base", "cyanideCarpet"}
  end

  --print("Generate "..result[1].." at {"..tostring(pos).."}")
  return result
end

