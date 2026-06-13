-- The functions defined in this file are automatically namespaced, and as such are an exception to the no globals rule
-- self is an alias for fractal.mods.modName.levels.levelName
function init(self)

  -- Remove extra tiles after this if possible
  self.tiles.max = 400
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
    result = {"cyanideCarpet"}
  elseif pos[1]%2 == 0 and pos[2]%2 == 0 then
    result = {"yellowWallpaper"}
  else
    if math.random(0, 3) == 0 then
      result = {"yellowWallpaper"}
    else
      result = {"cyanideCarpet"}
    end
  end

  if pos[1]%2 == 0 and pos[2]%2 == 0 and
    self.tiles:getInfo({pos[1]-1, pos[2]}).walkable and
    self.tiles:getInfo({pos[1]+1, pos[2]}).walkable and
    self.tiles:getInfo({pos[1], pos[2]-1}).walkable and
    self.tiles:getInfo({pos[1], pos[2]+1}).walkable
  then
    result = {"cyanideCarpet"}
  end

  --print("Generate "..result[1].." at {"..tostring(pos).."}")
  return result
end

