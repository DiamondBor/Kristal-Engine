local lib = {}

function lib:init()
    Game:registerEvent("musicer", function(data)
        return Musicer(data)
    end)
end

return lib