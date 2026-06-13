-- Returns a table with at minimum a make function and a cost number 
function queue(object, offset)
  local objectPos = object.pos:get()
  local pos = {objectPos[1] + offset[1], objectPos[2] + offset[2]}

  if object.mod.levels.level0.tiles:getInfo(pos).walkable then
    return {
      -- Inaccurate but cheap distance calculation
      cost = math.abs(offset[1]) + math.abs(offset[2]),
      make = function()
        object.pos:set({pos[1], pos[2]})
      end
    }
  end
end
