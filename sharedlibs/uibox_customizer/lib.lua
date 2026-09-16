local lib = {}
Registry.registerGlobal("GlobalUI", lib)
GlobalUI = lib

lib.default_skin = {
    ["light"] = "light",
    ["dark"] = "dark",
}
lib.default_fill = {}

---@param color? Color|string
---@return Color?
function lib.parseColor(color)
    if type(color) ~= "string" then return color end
    
    local named = COLORS[color]
    if named then
        return TableUtils.copy(named)
    end

    return ColorUtils.hexToRGB(color)
end

---@param style? string
---@param light? boolean
function lib:setDefault(style, light)
    self.default_skin[light and "light" or "dark"] = style
end

---@param light? boolean
---@return string?
function lib:getDefault(light)
    return self.default_skin[light and "light" or "dark"]
end

---@param color? Color|string
---@param light? boolean
function lib:setDefaultFill(color, light)
    self.default_fill[light and "light" or "dark"] = lib.parseColor(color)
end

---@param light? boolean
---@return Color
function lib:getDefaultFill(light)
    return self.default_fill[light and "light" or "dark"] or {0, 0, 0}
end

return lib
