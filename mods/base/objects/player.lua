-- Init can be a function or a table, depending on whether extra processing is required
function init()
  local result = {
    name = "player",
    ch = "@",
    color = {r = 1.0, g = 1.0, b = 1.0},
    mass = math.random(50, 100),
    volume = 0
  }
  -- Human body average density is similar to water, so volume in liters is approximately the same as mass in kilos
  result.volume = result.mass

  return result
end

-- The input parameter is optional. If it is included, the program will wait until user input is given before running the function
-- object.takeTurn is currently the only function that can take an input parameter
function takeTurn(self, input)
  print("player turn")
  --print("fractal.input = ", fractal.input())
  local inputs = self.mod.inputs
  local modActions = self.mod.actions

  if self.pos == nil then 
    return modActions.wait.queue(self, 10)
  end

  print("pos = {", self.pos:get()[1], ", ", self.pos:get()[2], "}")

  if input.is(inputs.Wait) then
    return modActions.wait.queue(self, 1)
  end
  if input.is(inputs.Up) then
    return modActions.move.queue(self, { 0, -1})
  end
  if input.is(inputs.UpRight) then
    return modActions.move.queue(self, { 1, -1})
  end
  if input.is(inputs.Right) then
    return modActions.move.queue(self, { 1,  0})
  end
  if input.is(inputs.DownRight) then
    return modActions.move.queue(self, { 1,  1})
  end
  if input.is(inputs.Down) then
    return modActions.move.queue(self, { 0,  1})
  end
  if input.is(inputs.DownLeft) then
    return modActions.move.queue(self, {-1,  1})
  end
  if input.is(inputs.Left) then
    return modActions.move.queue(self, {-1,  0})
  end
  if input.is(inputs.UpLeft) then
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
