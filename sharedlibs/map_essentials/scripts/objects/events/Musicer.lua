---@class Musicer : Event
---
---@field music     string?
---@field volume    number
---@field pitch     number
---@field force     boolean
---@field fade_in   number?
---
---@overload fun(...) : Musicer
local Musicer, super = Class(Event)

function Musicer:init(data)
    super.init(self, data)
    local properties = data.properties or {}
    self.music = properties["music"]
    self.volume = properties["volume"] or 1
    self.pitch = properties["pitch"] or 1
    self.force = properties["force"] or false
    self.fade_in = properties["fadein"]
end

function Musicer:getDebugInfo()
    local info = super.getDebugInfo(self)
    table.insert(info, "Music: " .. (self.music or "None"))
    table.insert(info, "Volume: " .. self.volume)
    table.insert(info, "Pitch: " .. self.pitch)
    table.insert(info, "Force: " .. (self.force and "True" or "False"))
    return info
end

function Musicer:postLoad()
    if Game.world.music:isPlaying() and not self.force then return end

    Game.world:transitionMusic({ self.music, self.fade_in and 0 or self.volume, self.pitch })

    if self.fade_in then
        Game.world.music:fade(self.volume, self.fade_in)
    end
end

return Musicer
