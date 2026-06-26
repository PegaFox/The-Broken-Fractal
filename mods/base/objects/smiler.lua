function takeTurn(self)
  local modActions = self.mod.actions

  local pos = self.pos:get()
  local playerPos = self.mod.levels.level0.objects:get(0).pos:get()
  local offset = {playerPos[1] - pos[1], playerPos[2] - pos[2]}
  local movement = {
    math.floor(offset[1] / math.abs(offset[1])),
    math.floor(offset[2] / math.abs(offset[2]))
  }

  if movement[1] ~= movement[1] then movement[1] = 0 end
  if movement[2] ~= movement[2] then movement[2] = 0 end

  print(movement)

  if movement[1] ~= 0 or movement[2] ~= 0 then
    return modActions.move.queue(
      self,
      movement
    )
  end
end
