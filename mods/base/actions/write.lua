function queue(object, data, tile)
  local typeData = tile:typeData()
  local oldCh = typeData.ch

  typeData.ch = function(tile)
    if tile:lua().writing then
      return "~"
    elseif type(oldCh) == "function" then
      return oldCh(tile)
    else
      return oldCh
    end
  end

  return {
    cost = #data,
    make = function()
      print("Wrote: \"", data, "\"");
      tile:lua().writing = data
    end
  }
end
