---@class MainMenuMobileControls : StateClass
---
---@field menu MainMenu
---@field selected_option number
---@field dragging table<any, number>
---
---@overload fun(menu:MainMenu) : MainMenuMobileControls
local MainMenuMobileControls, super = Class(StateClass)

function MainMenuMobileControls:init(menu)
    self.menu = menu

    self.selected_option = 1
    self.dragging = {}

    self.sliders = {
        { name = "Side Distance", config = "mobileSideDistance", y = 110 },
        { name = "Scale",         config = "mobileScale",        y = 142 },
        { name = "Opacity",       config = "mobileOpacity",      y = 174 }
    }
end

function MainMenuMobileControls:registerEvents()
    self:registerEvent("enter", self.onEnter)
    self:registerEvent("leave", self.onLeave)
    self:registerEvent("keypressed", self.onKeyPressed)
    self:registerEvent("update", self.update)
    self:registerEvent("draw", self.draw)
end

-------------------------------------------------------------------------------
-- Callbacks
-------------------------------------------------------------------------------

function MainMenuMobileControls:onEnter()
    self.selected_option = 1
    self.dragging = {}
end

function MainMenuMobileControls:onLeave()
    Kristal.saveConfig()
end

function MainMenuMobileControls:update()
    self:updateDragging()

    if self.selected_option <= 3 then
        local config = self.sliders[self.selected_option].config
        if Input.down("left") then
            Kristal.Config[config] = MathUtils.clamp(Kristal.Config[config] - (0.01 * DTMULT), 0, 1)
        elseif Input.down("right") then
            Kristal.Config[config] = MathUtils.clamp(Kristal.Config[config] + (0.01 * DTMULT), 0, 1)
        end
    end

    self.menu.heart_target_x = 80 - 18
    if self.selected_option == 1 then
        self.menu.heart_target_y = 110 + 16
    elseif self.selected_option == 2 then
        self.menu.heart_target_y = 142 + 16
    elseif self.selected_option == 3 then
        self.menu.heart_target_y = 174 + 16
    elseif self.selected_option == 4 then
        self.menu.heart_target_y = 206 + 16
    elseif self.selected_option == 5 then
        self.menu.heart_target_y = 270 + 16
    elseif self.selected_option == 6 then
        self.menu.heart_target_y = 302 + 16
    end
end

function MainMenuMobileControls:draw()
    Draw.setColor(COLORS.silver)
    Draw.printShadow("( OPTIONS )", 0, 0, 2, "center", 640)

    Draw.setColor(1, 1, 1)
    Draw.printShadow("MOBILE CONTROLS", 0, 48, 2, "center", 640)

    for i, slider in ipairs(self.sliders) do
        Draw.setColor(1, 1, 1)
        Draw.printShadow(slider.name, 80, slider.y)
        Draw.printShadow(MathUtils.round(Kristal.Config[slider.config] * 100) .. "%", 516, slider.y)

        Draw.setColor(0, 0, 0)
        love.graphics.rectangle("fill", 332, slider.y + 10, 170, 12)
        Draw.setColor(0.33, 0.33, 0.33)
        love.graphics.rectangle("fill", 330, slider.y + 8, 170, 12)

        Draw.setColor(self.selected_option == i and COLORS.yellow or COLORS.white)
        love.graphics.rectangle("fill", 330 + (Kristal.Config[slider.config] * 162), slider.y + 4, 8, 20)
    end

    Draw.setColor(1, 1, 1)
    Draw.printShadow("Button Style", 80, 206)
    Draw.printShadow(MobileControls.getButtonStyle():upper(), 330, 206)

    Draw.printShadow("Reset to defaults", 80, 270)
    Draw.printShadow("Back", 80, 302)
end


---@return number? index
function MainMenuMobileControls:getSliderAt(x, y)
    for i, slider in ipairs(self.sliders) do
        if x >= 80 and x <= 516 and y >= slider.y and y <= slider.y + 32 then
            return i
        end
    end
end

function MainMenuMobileControls:updateDragging()
    local dragging = {}

    for _, id in ipairs(love.touch.getTouches()) do
        local x, y = Input.getMousePosition(love.touch.getPosition(id))
        local index = self.dragging[id] or self:getSliderAt(x, y)
        if index then
            dragging[id] = index
            self.selected_option = index
            Kristal.Config[self.sliders[index].config] = MathUtils.clamp((x - 330) / 162, 0, 1)
        end
    end

    self.dragging = dragging
end

function MainMenuMobileControls:onKeyPressed(key, is_repeat)
    if Input.isCancel(key) then
        Assets.stopAndPlaySound("ui_select")
        self.menu:popState()
        return
    end

    local old_selected = self.selected_option
    if Input.is("up", key) then self.selected_option = self.selected_option - 1 end
    if Input.is("down", key) then self.selected_option = self.selected_option + 1 end
    if self.selected_option < 1 then self.selected_option = is_repeat and 1 or 6 end
    if self.selected_option > 6 then self.selected_option = is_repeat and 6 or 1 end

    if old_selected ~= self.selected_option then
        Assets.stopAndPlaySound("ui_move")
    end

    if self.selected_option == 4 then
        local offset = 0
        if Input.is("left", key) then offset = -1 end
        if Input.is("right", key) or Input.isConfirm(key) then offset = 1 end

        if offset ~= 0 then
            Assets.stopAndPlaySound("ui_move")
            local styles = MobileControls.STYLES
            local index = TableUtils.getIndex(styles, MobileControls.getButtonStyle()) + offset
            if index < 1 then index = #styles end
            if index > #styles then index = 1 end
            Kristal.Config["mobileButtonStyle"] = styles[index]
        end
    elseif Input.isConfirm(key) then
        if self.selected_option == 5 then
            Assets.stopAndPlaySound("ui_select")
            for _, slider in ipairs(self.sliders) do
                Kristal.Config[slider.config] = Kristal.getDefaultConfig()[slider.config]
            end
            Kristal.Config["mobileButtonStyle"] = Kristal.getDefaultConfig()["mobileButtonStyle"]
        elseif self.selected_option == 6 then
            Assets.stopAndPlaySound("ui_select")
            self.menu:popState()
        end
    end
end

return MainMenuMobileControls
