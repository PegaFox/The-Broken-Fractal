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

function takeTurn(self)
  print("player turn")
  --print("fractal.input = ", fractal.input())
  local inputs = self.mod.inputs
  local modActions = self.mod.actions

  if self.pos == nil then 
    return modActions.wait.queue(self, 10)
  end

  print("pos = {", self.pos:get()[1], ", ", self.pos:get()[2], "}")

  if fractal.input(inputs.Wait) then
    return modActions.wait.queue(self, 1)
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
  if fractal.input(inputs.Write) then
    local dirInput = fractal.prompt("Direction?")

    local dir = {0, 0}

    if dirInput == inputs.Left  then dir = {-1,  0} end
    if dirInput == inputs.Down  then dir = { 0,  1} end
    if dirInput == inputs.Up    then dir = { 0, -1} end
    if dirInput == inputs.Right then dir = { 1,  0} end

    local pos = self.pos:get()
    local tile =
      self.mod.levels.level0.tiles:get({pos[1]+dir[1], pos[2]+dir[2]})

    local startText = ""
    if tile:lua().writing then
      startText = tile:lua().writing
    end

    local window = fractal.openWindow({10, 10}, {
      {
        "navigation",
        up = inputs.Up,
        down = inputs.Down,
        left = inputs.Left,
        right = inputs.Right,
        select = inputs.Wait,
        back = inputs.Cancel,
      },
      {"border"},
      {"text area", size = {10, 10}, text = startText}
    })

    return modActions.write.queue(self, window[3].text, tile)
  end
end
