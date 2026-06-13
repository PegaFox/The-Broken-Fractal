function takeTurn(self)
  print("fractal.input = ", fractal.input())
  print("pos = {", self.pos:get()[1], ", ", self.pos:get()[2], "}")
  local inputs = self.mod.inputs
  local modActions = self.mod.actions

  if fractal.input(inputs.Wait) then
    return modActions.wait.queue(self)
  end
  if fractal.input(inputs.Up) then
    return modActions.move.queue(self, { 0, -1})
  end
  if fractal.input(inputs.UpRight) then
    return modActions.move.queue(self, { 1, -1})
  end
  if fractal.input(inputs.Right) then
    return modActions.move.queue(self, { 1,  0})
  end
  if fractal.input(inputs.DownRight) then
    return modActions.move.queue(self, { 1,  1})
  end
  if fractal.input(inputs.Down) then
    return modActions.move.queue(self, { 0,  1})
  end
  if fractal.input(inputs.DownLeft) then
    return modActions.move.queue(self, {-1,  1})
  end
  if fractal.input(inputs.Left) then
    return modActions.move.queue(self, {-1,  0})
  end
  if fractal.input(inputs.UpLeft) then
    return modActions.move.queue(self, {-1, -1})
  end
  --if fractal.input == 'w' then
  --  local dir = fractal.prompt("Direction?")
  --  if dir == 'h' then return self:write({-1, 0}) end
  --  if dir == 'j' then return self:write({0, 1}) end
  --  if dir == 'k' then return self:write({0, -1}) end
  --  if dir == 'l' then return self:write({1, 0}) end
  --end
end
