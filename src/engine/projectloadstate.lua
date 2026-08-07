local ProjectLoading = {}

function ProjectLoading:init()
    self.font = Assets.getFont("main")
end

function ProjectLoading:enter(from, after, time_limit, compile_steps, mod_name)
    MOD_LOADING = true
    self.after = after
    self.time_limit = time_limit
    self.compile_steps = compile_steps
    self.mod_name = mod_name
    self.finished_loading = false
    self.completion_drawn = false
    self.enter_time = love.timer.getTime()
    if not compile_steps then
        self.stage = Stage()
        self.dog = LoadingDog()
        self.stage:addChild(self.dog)
    end
end

function ProjectLoading:leave()
    MOD_LOADING = false
end

function ProjectLoading:update()
    if self.finished_loading then
        if not self.completion_drawn then
            return
        end
        Kristal.popState()
        self.after()
        return
    end

    if self.compile_steps then
        local success, message = coroutine.resume(self.compile_steps.thread)
        if not success then
            MOD_LOADING = false
            error(message, 0)
        end
        if coroutine.status(self.compile_steps.thread) ~= "dead" then return end
        Kristal.popState()
        self.after()
        return
    end

    local bucket = Assets.getBucket("project")
    local elapsed = love.timer.getTime() - self.enter_time
    local loaded = bucket.assets_loaded >= bucket.assets_total
    if loaded or (self.time_limit and elapsed >= self.time_limit) then
        self.finished_loading = true
        if Kristal.Config["verboseLoader"] then
            print(string.format("[Assets] Project %s %d/%d assets in %.1fms",
                loaded and "fully loaded" or "partially loaded",
                bucket.assets_loaded, bucket.assets_total, elapsed * 1000))
        end
    end

    self.dog:setProgress(self:getProgress(bucket, elapsed))
    self.stage:update()
end

function ProjectLoading:getProgress(bucket, elapsed)
    if self.finished_loading or bucket.assets_total == 0 then
        return 1
    end
    local progress = bucket.assets_loaded / bucket.assets_total
    if self.time_limit then
        progress = math.max(progress, elapsed / self.time_limit)
    end
    return MathUtils.clamp(progress, 0, 1)
end

function ProjectLoading:draw()
    if self.compile_steps then
        love.graphics.setFont(self.font)
        Draw.setColor(COLORS.white)
        love.graphics.printf("INITIALIZING\n" .. self.mod_name, 0, 224, SCREEN_WIDTH, "center")
        return
    end

    self.stage:draw()

    if self.finished_loading then
        self.completion_drawn = true
    end
end

return ProjectLoading
