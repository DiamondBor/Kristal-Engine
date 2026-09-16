---@diagnostic disable-next-line
---@class Map : Map
local Map, super = HookSystem.hookScript(Map)

function Map:init(world, data)
    super.init(self, world, data)
    if data and self:hasMusicer(data.layers) then
        self.keep_music = true
    end
end

--- Whether any object layer of the map contains a `musicer` event.
---@param layers table[]?
---@return boolean
function Map:hasMusicer(layers)
    for _, layer in ipairs(layers or {}) do
        if layer.type == "group" and self:hasMusicer(layer.layers) then
            return true
        end
        if layer.type == "objectgroup" and self:isLayerType(layer, "objects") then
            for _, object in ipairs(layer.objects) do
                local obj_type = object.type or object.class
                if obj_type == "" then
                    obj_type = object.name
                end
                if obj_type == "musicer" then
                    return true
                end
            end
        end
    end
    return false
end

return Map
