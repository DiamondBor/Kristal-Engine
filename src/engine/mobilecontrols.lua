---@class MobileControls
---
---@field touches table<any, {type:string, x:number, y:number}>
---@field held table<string, boolean>
---
local MobileControls = {}
local self = MobileControls

MobileControls.DIRECTIONS = {
    ["up"]    = -math.pi / 2,
    ["down"]  = math.pi / 2,
    ["left"]  = math.pi,
    ["right"] = 0
}
MobileControls.BUTTONS = { "confirm", "cancel", "menu" }
MobileControls.STYLES = { "official", "custom" }
MobileControls.touches = {}
MobileControls.held = {}

---@return boolean
function MobileControls.isEnabled()
    return Kristal.isMobile() and not Input.hasGamepad()
end

---@return string
function MobileControls.getButtonStyle()
    local style = Kristal.Config["mobileButtonStyle"]
    return TableUtils.contains(self.STYLES, style) and style or self.STYLES[1]
end

--- Returns the boxes in which the dpad and the buttons are drawn in
---@return table dpad
---@return table buttons
function MobileControls.getLayout()
    local window_width, window_height = love.graphics.getDimensions()

    local bottom = window_height * 0.95
    local top = window_height * (0.75 - (Kristal.Config["mobileScale"] * 0.5))
    local proportion = 1.02 + (Kristal.Config["mobileSideDistance"] * 0.73)
    
    local width = proportion * (bottom - top)
    if width > window_width * 0.475 then
        width = window_width * 0.475
        top = bottom - (width / proportion)
    end

    local size = bottom - top
    return { x = width - size, y = top, size = size }, { x = window_width - width, y = top, size = size }
end

---@return table<string, table>
function MobileControls.getButtonRects()
    local _, buttons = MobileControls.getLayout()
    
    local size = buttons.size * 0.375
    local far = buttons.size * 0.625

    return {
        ["confirm"] = { x = buttons.x + far, y = buttons.y,       size = size },
        ["cancel"]  = { x = buttons.x,       y = buttons.y + far, size = size },
        ["menu"]    = { x = buttons.x + far, y = buttons.y + far, size = size },
    }
end

---@return string?
function MobileControls.getButtonAt(x, y)
    for name, rect in pairs(MobileControls.getButtonRects()) do
        if x >= rect.x and x <= rect.x + rect.size and y >= rect.y and y <= rect.y + rect.size then
            return name
        end
    end
end

---@return boolean
function MobileControls.isInDpad(x, y)
    local dpad = MobileControls.getLayout()
    return MathUtils.dist(dpad.x + (dpad.size / 2), dpad.y + (dpad.size / 2), x, y) <= (dpad.size * 0.75)
end

---@return string[]
function MobileControls.getDpadDirections(x, y)
    local dpad = MobileControls.getLayout()
    local center_x, center_y = dpad.x + (dpad.size / 2), dpad.y + (dpad.size / 2)

    if MathUtils.dist(center_x, center_y, x, y) < (dpad.size * 0.1) then
        return {}
    end

    local directions = {}
    for direction, angle in pairs(self.DIRECTIONS) do
        if math.abs(MathUtils.angleDiff(MathUtils.angle(center_x, center_y, x, y), angle)) <= math.rad(60) then
            table.insert(directions, direction)
        end
    end
    return directions
end

function MobileControls.touchPressed(id, x, y)
    if not MobileControls.isEnabled() then return end

    local button = MobileControls.getButtonAt(x, y)
    if button then
        self.touches[id] = { type = button, x = x, y = y }
    elseif MobileControls.isInDpad(x, y) then
        self.touches[id] = { type = "dpad", x = x, y = y }
    end
end

function MobileControls.touchMoved(id, x, y)
    if self.touches[id] then
        self.touches[id].x = x
        self.touches[id].y = y
    end
end

function MobileControls.touchReleased(id)
    self.touches[id] = nil
end

function MobileControls.update()
    if not MobileControls.isEnabled() then
        self.touches = {}
    end

    local held = {}
    for _, touch in pairs(self.touches) do
        if touch.type == "dpad" then
            for _, direction in ipairs(MobileControls.getDpadDirections(touch.x, touch.y)) do
                held[direction] = true
            end
        else
            held[touch.type] = true
        end
    end
    
    for alias, _ in pairs(Input.required_binds) do
        if held[alias] and not self.held[alias] then
            Input.onKeyPressed("touch:" .. alias, false)
        elseif not held[alias] and self.held[alias] then
            Input.onKeyReleased("touch:" .. alias)
        end
    end

    self.held = held
end

---@param path string
---@param name string
---@param rect table
function MobileControls.drawButton(path, name, rect)
    local texture = Assets.getTexture(path .. name .. (self.held[name] and "_2" or "_1"))
    Draw.draw(texture, rect.x, rect.y, 0, rect.size / texture:getWidth(), rect.size / texture:getHeight())
end

function MobileControls.draw()
    if not MobileControls.isEnabled() then return end

    love.graphics.push("all")
    love.graphics.origin()

    Draw.setColor(1, 1, 1, MathUtils.lerp(0.1, 1, Kristal.Config["mobileOpacity"]))

    local dpad = MobileControls.getLayout()
    for direction, _ in pairs(self.DIRECTIONS) do
        MobileControls.drawButton("kristal/buttons/mobile/", direction, dpad)
    end

    local rects = MobileControls.getButtonRects()
    for _, button in ipairs(self.BUTTONS) do
        MobileControls.drawButton("kristal/buttons/mobile/" .. MobileControls.getButtonStyle() .. "/", button, rects[button])
    end

    love.graphics.pop()
end

return MobileControls
