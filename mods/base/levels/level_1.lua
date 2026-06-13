-- The functions defined in this file are automatically namespaced, and as such are an exception to the no globals rule
-- self is an alias for mods.modName.levels.levelName
function init(self)

end

function deinit(self)

end

function enter(self)

end

function exit(self)

end

function update(self)
  local pos = self.camera:centerOn(self.objects:get(0))
  --print(pos[1], ", ", pos[2])
end

function generateTile(self, pos)
  local result = nil
  if pos[1]%20 < 10 and pos[2]%20 < 10 then
    result = {"concreteWall"}
  else
    result = {"concreteFloor"}
  end

  --if pos[1]%2 == 0 and pos[2]%2 == 0 and
  --  self.tiles:getInfo({pos[1]-1, pos[2]}).walkable and
  --  self.tiles:getInfo({pos[1]+1, pos[2]}).walkable and
  --  self.tiles:getInfo({pos[1], pos[2]-1}).walkable and
  --  self.tiles:getInfo({pos[1], pos[2]+1}).walkable
  --then
  --  result = {"concreteFloor"}
  --end

  --print("Generate "..result[1].." at {"..tostring(pos).."}")
  return result
end

