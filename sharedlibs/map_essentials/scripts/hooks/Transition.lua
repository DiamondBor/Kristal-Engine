---@class Transition : Event
---
---@field music_fade boolean
local Transition, super = HookSystem.hookScript(Transition)

function Transition:init(x, y, shape, properties)
    super.init(self, x, y, shape, properties)

    self.music_fade = properties and properties.musicfade or false

    local map = self.target.map
    if map and map:find("^%.%.?/") then
        local parts = StringUtils.split(Game.world.map.id, "/")
        table.remove(parts)
        for _, part in ipairs(StringUtils.split(map, "/")) do
            if part == ".." then
                table.remove(parts)
            elseif part ~= "." then
                table.insert(parts, part)
            end
        end
        self.target.map = table.concat(parts, "/")
    end
end

function Transition:onEnter(chara)
    if chara.is_player and self.music_fade then
        Game.world.music:fade(0, 10 / 30, function() Game.world.music:stop() end)
    end
    return super.onEnter(self, chara)
end

return Transition