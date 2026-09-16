---@diagnostic disable-next-line
---@class UIBox : UIBox
local UIBox, super = HookSystem.hookScript(UIBox)

---@param skin? string
---@param fill_color? Color|string
function UIBox:init(x, y, width, height, skin, fill_color)
    super.init(self, x, y, width, height, skin)

    self:setFillColor(fill_color)
end

function UIBox:getWorldSkin()
    return GlobalUI:getDefault(Game:isLight()) or super.getWorldSkin(self)
end

---@param color? Color|string
function UIBox:setFillColor(color)
    self.fill_color = GlobalUI.parseColor(color) or GlobalUI:getDefaultFill(Game:isLight())
end

return UIBox
