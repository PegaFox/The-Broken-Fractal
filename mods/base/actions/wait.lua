function queue(object, waitTime)
  return {
    cost = waitTime,
    make = function() end
  }
end
