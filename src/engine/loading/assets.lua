local LoadingMode = require("src.engine.loading.LoadingMode")
---@class Assets
---
---@field loaded boolean
---
---@field data Assets.data
---@field data_mirror table
---@field data_owner table
---
---@field frames_for table<string, {[1]: string, [2]: number}>
---@field texture_ids table<love.Image, string>
---@field sounds table<string, Sound>
---@field sound_instances table<string, Sound[]>
---@field quads table<string, love.Quad>
---
---@field saved_data table?
---
---@field last_on_demand number?
---
local Assets = {}
local self = Assets

---@class Assets.data
---@field texture table<string, love.Image>
---@field texture_data table<string, love.ImageData>
---@field frames table<string, love.Image[]>
---@field frame_ids table<string, string[]>
---@field fonts table<string, love.Font|{default: number, [number]: love.Font}>
---@field font_data table<string, love.Data>
---@field font_bmfont_data table<string, string>
---@field font_image_data table<string, love.ImageData>
---@field font_settings table<string, Assets.font_settings>
---@field sound_data table<string, love.SoundData>
---@field sound_settings table<string, Assets.sound_settings>
---@field music table<string, string>
---@field shaders table<string, love.Shader>
---@field shader_paths table<string, string>
---@field videos table<string, string>
---@field bubble_settings table<string, table>

--- Settings for a font asset, paired with the actual font data as a .json file.
---@class Assets.font_settings
---@field defaultSize integer? # The default size of the font.
---@field autoScale boolean? # Whether to scale the default-sized font to fit requested sizes. This is true by default for image and BMFont fonts.
---@field glyphs string? # (Image fonts only) Characters in the font, in order from left to right.
---@field hinting love.HintingMode? # (TrueType fonts only) The hinting mode to load the font with.
---@field fallbacks Assets.font_settings.fallbacks[]? # Fallback fonts to use in case there are missing glyphs.

---@class Assets.font_settings.fallbacks
---@field font string # ID of the fallback font. It must be of the same font type as the base font.
---@field size number? # (TrueType fonts only) The default size of the fallback font.

--- Settings for a sound asset, paired with the actual sound data as a .json file.
---@class Assets.sound_settings
---@field volume number? # Default volume to play the sound at.

Assets.saved_data = nil
Assets.last_on_demand = 0

---@type AssetBucket[]
Assets.buckets = {}

---@internal
---@return any task
function Assets.getQueue(bucket_id, asset_type)
    if not self.queued_tasks[bucket_id] then
        self.queued_tasks[bucket_id] = {}
    end
    if not self.queued_tasks[bucket_id][asset_type] then
        self.queued_tasks[bucket_id][asset_type] = {}
    end
    return self.queued_tasks[bucket_id][asset_type]
end

function Assets.init()
    Assets.clear()
    AssetLoaders.init()
    self.queued_tasks = {}
    self.asset_load_in_channel = love.thread.getChannel("asset_load_in")
    self.asset_load_out_channel = love.thread.getChannel("asset_load_out")
    self.asset_load_width_channel = love.thread.getChannel("asset_load_width")
    self.asset_load_in_channel:clear()
    self.asset_load_out_channel:clear()
    self.asset_load_width_channel:clear()
    local thread_arg = Kristal.Args["asset-loader-threads"]
    local configured_threads = tonumber(thread_arg and thread_arg[1])
        or tonumber(Kristal.Config["assetLoaderThreads"])
        or 0
    local processor_count = love.system.getProcessorCount()
    if configured_threads <= 0 then
        configured_threads = math.min(4, math.max(1, processor_count - 1))
    end
    self.asset_load_worker_count = math.max(1, math.min(8, math.floor(configured_threads)))
    self.asset_load_in_flight_limit = math.max(64, self.asset_load_worker_count * 32)
    self.asset_load_width = self.asset_load_worker_count
    self.asset_load_width_channel:push(self.asset_load_width)
    self.asset_load_threads = {}
    for worker_id = 1, self.asset_load_worker_count do
        local thread = love.thread.newThread("src/engine/loading/assetloadthread.lua")
        thread:start(worker_id)
        table.insert(self.asset_load_threads, thread)
    end
    print(string.format("[AssetLoader] Started %d decode worker(s) on %d logical processor(s), queue limit %d",
        self.asset_load_worker_count, processor_count, self.asset_load_in_flight_limit))
    self.buckets = {
        AssetBucket("engine", { "assets" }),
        AssetBucket("project", { "assets" }),
    }
    for i, bucket in ipairs(self.buckets) do
        bucket.rank = i
    end
    self.getBucket("engine"):startLoading({ "assets" })
end

function Assets.shutdown()
    local threads = self.asset_load_threads or {}
    if #threads == 0 then return end
    -- !!! WORKER THROTTLE
    Assets.setWorkerWidth(self.asset_load_worker_count)
    self.asset_load_in_channel:clear()
    for _ = 1, #threads do
        self.asset_load_in_channel:push("stop")
    end
    for _, thread in ipairs(threads) do
        thread:wait()
    end
end


-- !!! WORKER THROTTLE
---@param width integer
function Assets.setWorkerWidth(width)
    if self.asset_load_width == width then return end
    self.asset_load_width = width
    self.asset_load_width_channel:clear()
    self.asset_load_width_channel:push(width)
end
-------

---@param bucket AssetBucket
---@return integer mode
function Assets.getBucketMode(bucket)
    if bucket.bucket_id == "engine" then
        return Kristal.Config["engineLoadingMode"]
    end
    return Kristal.Config["projectLoadingMode"]
end

---@return boolean loading
function Assets.isLoading()
    for _, bucket in ipairs(self.buckets) do
        if Assets.getBucketMode(bucket) == LoadingMode.LAZY then
            if bucket.pending_tasks > 0 or self.asset_load_out_channel:getCount() > 0 then return true end
        elseif bucket.state == AssetBucket.State.LOADING then
            return true
        end
    end
    return false
end

---@return integer, integer
function Assets.getAssetCount()
    local asset_total = 0
    local asset_loaded = 0
    for _, bucket in pairs(self.buckets) do
        asset_loaded = asset_loaded + bucket.assets_loaded
        asset_total = asset_total + bucket.assets_total
    end
    return asset_loaded, asset_total
end

---@param bucket_id string
---@return table? stats
function Assets.getLoadStats(bucket_id)
    return self.getBucket(bucket_id).last_load_stats
end

function Assets.clear()
    self.loaded = false
    self.data = {
        texture = {},
        texture_data = {},
        frame_ids = {},
        frames = {},
        fonts = {},
        font_data = {},
        font_bmfont_data = {},
        font_image_data = {},
        font_settings = {},
        sound_data = {},
        sound_settings = {},
        music = {},
        videos = {},
        bubbles = {},
        bubble_settings = {},
        shaders = {},
        shader_paths = {}
    }
    self.data_mirror = {}
    self.data_owner = {}
    for field in pairs(self.data) do
        self.data_mirror[field] = {}
        self.data_owner[field] = {}
    end
    self.frames_for = {}
    self.texture_ids = {}
    self.sounds = {}
    self.sound_instances = {}
    self.quads = {}
    Assets.rematerialize()
end

---@param path string
---@return new_path string
function Assets.checkSpritesOverride(path)
    local split_path = Utils.splitFast(path, "/")
    if #split_path > 1 then
        if split_path[1] == "player" then
            table.insert(split_path, 2, Kristal.getSoulFacing())
            return table.concat(split_path, "/")
        end
    end
    return path
end

---@param data Assets.data
function Assets.loadData(data)
    TableUtils.merge(self.data, data, true)

    self.parseData(data)

    self.loaded = true
end

---@private
---@param bucket AssetBucket
function Assets.materializeField(field, key, value, bucket)
    if value == nil then return end

    local data = self.data[field]
    local mirror = self.data_mirror[field]
    local owner = self.data_owner[field]

    if data[key] ~= nil then
        if data[key] ~= mirror[key] then return end
        if owner[key] > bucket.rank then return end
    end

    data[key] = value
    mirror[key] = value
    owner[key] = bucket.rank

    bucket.data_entries[field] = bucket.data_entries[field] or {}
    bucket.data_entries[field][key] = value
end

---@private
---@param bucket AssetBucket
function Assets.rematerializeBucket(bucket)
    for field, entries in pairs(bucket.data_entries) do
        for key, value in pairs(entries) do
            Assets.materializeField(field, key, value, bucket)
        end
    end
end

---@private
function Assets.rematerialize()
    for _, bucket in ipairs(self.buckets) do
        for field, entries in pairs(bucket.data_entries) do
            for key, value in pairs(entries) do
                Assets.materializeField(field, key, value, bucket)
            end
        end
    end
end

--- For compatibility with Assets.data since some mods and projects get things from there.
---@internal
---@param output any
---@param final any
---@param task any
---@param bucket AssetBucket
function Assets.materialize(asset_type, asset_id, output, final, task, bucket)
    if asset_type == "sprite" then
        for exact_id, texture in pairs(final.exact_textures) do
            Assets.materializeField("texture", exact_id, texture, bucket)
            Assets.materializeField("texture_data", exact_id, final.exact_data[exact_id], bucket)
        end
        if final.numbered then
            Assets.materializeField("frames", asset_id, final.textures, bucket)
            Assets.materializeField("frame_ids", asset_id, final.frame_ids, bucket)
        end
    elseif asset_type == "font" then
        local data = final or output
        if final then
            local font = final.font_data and { default = final.default } or final.font
            Assets.materializeField("fonts", asset_id, font, bucket)
        end
        Assets.materializeField("font_data", asset_id, data.font_data, bucket)
        Assets.materializeField("font_bmfont_data", asset_id, output.bmfont_path, bucket)
        Assets.materializeField("font_image_data", asset_id, data.image_data, bucket)
        Assets.materializeField("font_settings", asset_id, data.settings, bucket)
    elseif asset_type == "sound" then
        Assets.materializeField("sound_data", asset_id, output.sound_data, bucket)
        Assets.materializeField("sound_settings", asset_id, output.metadata, bucket)
    elseif asset_type == "music" then
        Assets.materializeField("music", asset_id, final.path, bucket)
    elseif asset_type == "shader" then
        Assets.materializeField("shaders", asset_id, final.shader, bucket)
        Assets.materializeField("shader_paths", asset_id, task, bucket)
    elseif asset_type == "video" then
        Assets.materializeField("videos", asset_id, final, bucket)
    elseif asset_type == "bubble" then
        Assets.materializeField("bubble_settings", asset_id, final, bucket)
    end
end

---@param asset_type string
---@param asset_id string
---@return any asset
function Assets.get(asset_type, asset_id)
    if not AssetLoaders.exists(asset_type) then
        error(string.format("Attempt to get unknown asset type '%s' with id '%s'", asset_type, asset_id), 2)
    end
    local asset = Assets.internalGet(asset_type, asset_id)
    if asset == nil then
        error(string.format("Attempt to get missing asset of type '%s' with ID '%s'", asset_type, asset_id), 2)
    end
    return asset
end

function Assets.tryGet(asset_type, asset_id)
    if not AssetLoaders.exists(asset_type) then
        error(string.format("Attempt to get unknown asset type '%s' with id '%s'", asset_type, asset_id), 2)
    end
    if Assets.internalHas(asset_type, asset_id) then
        return Assets.internalGet(asset_type, asset_id)
    end
end

--- Iterate over assets of a particular type.
---@param asset_type string
---@param id_prefix string?
---@return fun(): string
function Assets.iterate(asset_type, id_prefix)
    id_prefix = id_prefix or ""
    return coroutine.wrap(function()
        for _, bucket in ipairs(self.buckets) do
            for id in pairs(Assets.getQueue(bucket.bucket_id, asset_type)) do
                if StringUtils.startsWith(id, id_prefix) then
                    coroutine.yield(id)
                end
            end
            for id in pairs(bucket.loaded_assets[asset_type] or {}) do
                if StringUtils.startsWith(id, id_prefix) then
                    coroutine.yield(id)
                end
            end
        end
    end)
end

---@private
---@param asset_type string
---@param asset_id string
---@return any asset
function Assets.internalGet(asset_type, asset_id)
    for i = #self.buckets, 1, -1 do
        if self.buckets[i]:has(asset_type, asset_id) then
            return self.buckets[i]:get(asset_type, asset_id)
        end
    end
    return nil
end

---@private
---@param asset_type string
---@param asset_id string
---@return boolean found
function Assets.internalHas(asset_type, asset_id)
    for i = #self.buckets, 1, -1 do
        if self.buckets[i]:has(asset_type, asset_id) then
            return true
        end
    end
    return false
    
end

---@private
---@param exact_id string
---@return love.Image? texture
---@return love.ImageData? data
function Assets.internalGetExactSprite(exact_id)
    for i = #self.buckets, 1, -1 do
        local bucket = self.buckets[i]
        if bucket:hasExactSprite(exact_id) then
            return bucket:getExactSprite(exact_id)
        end
    end
    return nil, nil
end

---@param bucket_id string
---@return AssetBucket bucket
function Assets.getBucket(bucket_id)
    for i = 1, #self.buckets do
        if self.buckets[i].bucket_id == bucket_id then
            return self.buckets[i]
        end
    end
    error(string.format("Attempt to get non-existent bucket '%s'", bucket_id))
end

function Assets.saveData()
    self.saved_data = {
        data = TableUtils.copy(self.data, true),
        frames_for = TableUtils.copy(self.frames_for, true),
        texture_ids = TableUtils.copy(self.texture_ids, true),
        sounds = TableUtils.copy(self.sounds, true),
    }
end

---@return boolean
function Assets.restoreData()
    if self.saved_data then
        Assets.clear()
        for k, v in pairs(self.saved_data) do
            self[k] = TableUtils.copy(v, true)
        end
        for field, entries in pairs(self.data) do
            local mirror = {}
            local owner = {}
            for key, value in pairs(entries) do
                mirror[key] = value
                owner[key] = 1
            end
            self.data_mirror[field] = mirror
            self.data_owner[field] = owner
        end
        Assets.rematerializeBucket(self.getBucket("engine"))
        self.loaded = true
        return true
    else
        return false
    end
end

---@param data Assets.data
function Assets.parseData(data)
    -- thread can't create images, we do it here
    for key, image_data in pairs(data.texture_data) do
        self.data.texture[key] = love.graphics.newImage(image_data)
        self.texture_ids[self.data.texture[key]] = key
    end

    -- create frame tables with images
    for key, ids in pairs(data.frame_ids) do
        self.data.frames[key] = {}
        for i, id in pairs(ids) do
            self.data.frames[key][i] = self.data.texture[id]
            self.frames_for[id] = { key, i }
        end
    end

    -- create TTF fonts
    for key, file_data in pairs(data.font_data) do
        local default = data.font_settings[key] and data.font_settings[key].defaultSize or 12
        self.data.fonts[key] = { default = default }
    end
    -- create bmfont fonts
    for key, file_path in pairs(data.font_bmfont_data) do
        data.font_settings[key] = data.font_settings[key] or {}
        if data.font_settings[key].autoScale == nil then
            data.font_settings[key].autoScale = true
        end
        self.data.fonts[key] = love.graphics.newFont(file_path)
    end
    -- set up bmfont font fallbacks
    for key, _ in pairs(data.font_bmfont_data) do
        if data.font_settings[key].fallbacks then
            local fallbacks = {}
            for _, fallback in ipairs(data.font_settings[key].fallbacks) do
                local font = self.data.fonts[fallback.font]
                if type(font) == "table" or (self.data.font_settings[fallback.font] and self.data.font_settings[fallback.font].glyphs) then
                    error("Attempt to use TTF or image fallback on BMFont font: " .. key)
                else
                    table.insert(fallbacks, font)
                end
            end
            self.data.fonts[key]:setFallbacks(unpack(fallbacks))
        end
    end
    -- create image fonts
    for key, image_data in pairs(data.font_image_data) do
        local glyphs = data.font_settings[key] and data.font_settings[key].glyphs or ""
        data.font_settings[key] = data.font_settings[key] or {}
        if data.font_settings[key].autoScale == nil then
            data.font_settings[key].autoScale = true
        end
        self.data.fonts[key] = love.graphics.newImageFont(image_data, glyphs)
    end
    -- set up image font fallbacks
    for key, _ in pairs(data.font_image_data) do
        if data.font_settings[key].fallbacks then
            local fallbacks = {}
            for _, fallback in ipairs(data.font_settings[key].fallbacks) do
                local font = self.data.fonts[fallback.font]
                if type(font) == "table" or not (self.data.font_settings[fallback.font] and self.data.font_settings[fallback.font].glyphs) then
                    error("Attempt to use TTF or BMFont fallback on image font: " .. key)
                else
                    table.insert(fallbacks, font)
                end
            end
            self.data.fonts[key]:setFallbacks(unpack(fallbacks))
        end
    end

    -- may be a memory hog, we clone the existing source so we dont need the sound data anymore
    --self.data.sound_data = {}
end

---@private
function Assets.dispatchPending(max_cost, max_inspect)
    local in_flight = 0
    for _, bucket in ipairs(self.buckets) do in_flight = in_flight + bucket.pending_tasks end
    for _, bucket in ipairs(self.buckets) do
        if in_flight >= self.asset_load_in_flight_limit then break end
        if Assets.getBucketMode(bucket) ~= LoadingMode.LAZY then
            in_flight = in_flight + bucket:dispatchTasks(self.asset_load_in_flight_limit - in_flight, max_cost, max_inspect)
        end
    end
end

function Assets.update()
    local sounds_to_remove = {}
    for key, sounds in pairs(self.sound_instances) do
        for _, sound in ipairs(sounds) do
            if not sound:isPlaying() then
                table.insert(sounds_to_remove, { key = key, value = sound })
            end
        end
    end
    for _, sound in ipairs(sounds_to_remove) do
        TableUtils.removeValue(self.sound_instances[sound.key], sound.value)
    end
    for _, thread in ipairs(self.asset_load_threads) do
        if not thread:isRunning() then
            local thread_error = thread:getError()
            if thread_error then error("Asset loader thread failed:\n" .. thread_error) end
        end
    end
    
    local now = love.timer.getTime()
    local state = Kristal.getState()
    local blocking_load = MOD_LOADING
        or state == Kristal.States["Loading"]
        or state == Kristal.States["Empty"]

    local warming = not blocking_load and state == Game
    -- !!! WORKER THROTTLE - start
    local full_width = self.asset_load_worker_count
    local gameplay_width = state == Game and Kristal.Config["projectLoadingMode"] ~= LoadingMode.FULL
    Assets.setWorkerWidth(gameplay_width and 1 or full_width)
    -- !!! WORKER THROTTLE - end
    local warm_now = not warming or (now - self.last_on_demand) >= 0.1

    local max_cost = warming and 100 or nil
    local max_inspect = warming and 64 or nil
    if warm_now then
        Assets.dispatchPending(max_cost, max_inspect)
    end

    local start_time = love.timer.getTime()
    local apply_budget = blocking_load and (2 / 30)
        or (warming and 0.002 or (0.5 / 30))
    while warm_now and self.asset_load_out_channel:getCount() > 0 do
        local message = self.asset_load_out_channel:pop()
        local bucket = self.getBucket(message.bucket_id)
        if bucket.state == AssetBucket.State.LOADING
            and bucket.generation == message.generation then
            bucket:receiveTask(message.asset_type, message.asset_id,
                message.success, message.result, message.decode_time,
                message.worker_id, message.worker_heap_kb)
            if Kristal.Config["verboseLoader"] then
                Kristal.Loader.message = string.format("%s/%s: %s",
                    message.bucket_id, message.asset_type, message.asset_id)
            end
        elseif message.success then
            AssetLoaders.get(message.asset_type):releaseOutput(message.result)
        end
        if love.timer.getTime() - start_time >= apply_budget then break end
    end

    if warm_now then
        Assets.dispatchPending(max_cost, max_inspect)
    end

    for _, bucket in ipairs(self.buckets) do bucket:finishIfReady() end

    local loading = self.isLoading()
    local show = (state ~= Kristal.States["ProjectLoading"]) and (Kristal.Loader.waiting > 0 or (loading and not warming))
    Kristal.Overlay.setLoading(show)
    if not show and not loading then
        Kristal.Loader.message = ""
    end
end

---@param path string
---@return table
function Assets.getBubbleData(path)
    return self.data.bubble_settings[path] or self.tryGet("bubble", path) or {}
end

---@return FontAssetLoader.Font?
function Assets.getFontInfo(asset_id)
    return self.tryGet("font", asset_id)
end

---@param path string
---@param size? number
---@return love.Font?
function Assets.getFont(path, size)
    local font = self.getFontInfo(path)
    if not font then
        return nil
    end
    local font_cache = self.data.fonts[path] or {}
    self.data.fonts[path] = font_cache
    local settings = font.settings or {}
    if not font.font then
        if settings.autoScale then
            size = font.default
        else
            size = size or font.default
        end
        if not font_cache[size] then
            ---@diagnostic disable-next-line: param-type-mismatch
            font_cache[size] = love.graphics.newFont(font.font_data --[[@as string]], size, settings.hinting or "mono")

            if settings.fallbacks then
                local fallbacks = {}

                for _, fallback in ipairs(settings.fallbacks) do
                    self.getFontInfo(fallback.font)
                    local fb_font = self.data.fonts[fallback.font]

                    if type(fb_font) ~= "table" then
                        error("Attempt to use image or BMFont fallback on TTF font: " .. path)
                    else
                        local ratio = (fallback.size or fb_font.default) / font.default
                        table.insert(fallbacks, self.getFont(fallback.font, size * ratio))
                    end
                end

                font_cache[size]:setFallbacks(unpack(fallbacks))
            end
        end
        return font_cache[size]
    else
        return font.font
    end
end

---@param path string
function Assets.getFontData(path)
    if not self.data.fonts[path] then
        self.getFontInfo(path)
    end
    return self.data.font_settings[path] or {}
end

---@param path string
---@param size? number
---@return number
function Assets.getFontScale(path, size)
    if not self.data.fonts[path] then
        self.getFontInfo(path)
    end
    local data = self.data.font_settings[path]
    if data and data.autoScale then
        return (size or 1) / (data.defaultSize or 1)
    else
        return 1
    end
end

---@param path string
---@return love.Image?
function Assets.getTexture(path)
    local injected = self.data.texture[path]
    if injected then return injected end
    local exact_texture = self.internalGetExactSprite(path)
    if exact_texture then return exact_texture end

    local identifier, split_frame = SpriteAssetLoader.splitIdentifier(path)
    local frames = self.getFrames(identifier)
    if not frames then return nil end
    return frames[split_frame or 1]
end

---@return boolean
function Assets.hasSprite(asset_id)
    return Assets.internalHas("sprite", asset_id)
end

--[[Utils.hook(Assets, "getTexture", function (orig, path)
    return orig(Assets.checkSpritesOverride(path)) or orig(path)
end)]]

---@param path string
---@return love.ImageData?
function Assets.getTextureData(path)
    local injected = self.data.texture_data[path]
    if injected then return injected end
    local _, exact_data = self.internalGetExactSprite(path)
    if exact_data then return exact_data end

    local identifier, split_frame = SpriteAssetLoader.splitIdentifier(path)
    if not self.internalHas("sprite", identifier) then return nil end
    local frames = self.get("sprite", identifier).data
    return frames[split_frame or 1]
end

---@param texture love.Image|string
---@return string
function Assets.getTextureID(texture)
    if type(texture) == "string" then return texture end
    for bucket_n = #Assets.buckets, 1, -1 do
        local id = Assets.buckets[bucket_n].texture_ids[texture]
        if id then return id end
    end
end

---@param path string
---@return love.Image[]?
function Assets.getFrames(path)
    local injected = self.data.frames[path]
    if injected then return injected end
    if not self.internalHas("sprite", path) then return nil end
    local sprite = self.get("sprite", path)
    if not sprite.numbered then return nil end
    return sprite.textures
end

--[[Utils.hook(Assets, "getFrames", function (orig, path)
    return orig(Assets.checkSpritesOverride(path)) or orig(path)
end)]]

---@param path string
---@return string[]?
function Assets.getFrameIds(path)
    local injected = self.data.frame_ids[path]
    if injected then return injected end
    if not self.internalHas("sprite", path) then return nil end
    local sprite = self.get("sprite", path)
    if not sprite.numbered then return nil end
    return sprite.frame_ids
end

---@param texture string
---@return string texture, number frame
function Assets.getFramesFor(texture)
    for bucket_n = #self.buckets, 1, -1 do
        local bucket = self.buckets[bucket_n]
        if bucket:hasExactSprite(texture) then
            return bucket:getFramesForExactSprite(texture)
        end
    end
    return nil, nil
end

---@param path string
---@return love.Image[]
function Assets.getFramesOrTexture(path)
    local exact_texture = self.internalGetExactSprite(path)
    if exact_texture then return { exact_texture } end
    return self.getFrames(path)
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param sw number
---@param sh number
---@return love.Quad
function Assets.getQuad(x, y, w, h, sw, sh)
    local key = x .. "," .. y .. "," .. w .. "," .. h .. "," .. sw .. "," .. sh
    if not self.quads[key] then
        self.quads[key] = love.graphics.newQuad(x, y, w, h, sw, sh)
    end
    return self.quads[key]
end

---@param sound string
---@return Sound
function Assets.getSound(sound)
    return self.tryGet("sound", sound)
end

function Assets.hasSound(sound)
    return self.internalHas("sound", sound)
end

---@param sound string
---@return Sound
function Assets.newSound(sound)
    local source = self.getSound(sound)
    if not source then return end
    return source:clone()
end

---@param sound string
---@return Sound?
function Assets.startSound(sound)
    local src = self.getSound(sound)
    if not src then
        Kristal.Console:warn("Sound not found: \"" .. sound .. "\"")
        return nil
    end
    src:stop()
    src:play()
    return src
end

---@param sound string
---@param actually_stop? boolean
function Assets.stopSound(sound, actually_stop)
    for _, src in ipairs(self.sound_instances[sound] or {}) do
        if actually_stop then
            src:stop()
        else
            src:setVolume(0)
            if src:isLooping() then
                src:setLooping(false)
            end
        end
    end
    if actually_stop then
        self.sound_instances[sound] = {}
    end
end

function Assets.stopAllSounds()
    for key,_ in pairs(Assets.sound_instances) do
        Assets.stopSound(key, true)
    end
end

---@param sound string
---@param volume? number
---@param pitch? number
---@return Sound
function Assets.playSound(sound, volume, pitch)
    if self.hasSound(sound) then
        self.sound_instances[sound] = self.sound_instances[sound] or {}
        local src = self.getSound(sound):clone()

        if volume then
            src:setVolume(volume)
        end

        if pitch then
            src:setPitch(pitch)
        end

        src:play()

        table.insert(self.sound_instances[sound], src)

        return src
    else
        Kristal.Console:warn("Sound not found: \"" .. sound .. "\"")
    end
end

---@param sound string
---@param volume? number
---@param pitch? number
---@param actually_stop? boolean
---@return Sound
function Assets.stopAndPlaySound(sound, volume, pitch, actually_stop)
    self.stopSound(sound, actually_stop)
    return self.playSound(sound, volume, pitch)
end

---@param music string
---@return MusicAssetLoader.MusicResult
function Assets.getMusic(music)
    return self.get("music", music)
end

function Assets.hasMusic(music)
    return self.data.music[music] ~= nil or self.internalHas("music", music)
end

---@param music string
---@return string?
function Assets.getMusicPath(music)
    local injected = self.data.music[music]
    if injected then return injected end
    if not self.internalHas("music", music) then
        return nil
    end
    return self.getMusic(music).path
end

---@param video string
---@return string?
function Assets.getVideoPath(video)
    return self.data.videos[video] or self.tryGet("video", video)
end

---@param video string
---@param load_audio? boolean
---@return love.Video
function Assets.newVideo(video, load_audio)
    return love.graphics.newVideo(self.getVideoPath(video), { audio = load_audio })
end

---@param id string
---@return love.Shader
function Assets.getShader(id)
    local injected = self.data.shaders[id]
    if injected then return injected end
    if self.internalHas("shader", id) then
        return self.get("shader", id).shader
    end
end

function Assets.newShader(id)
    return love.graphics.newShader(self.get("shader", id).source)
end

function Assets.hasShader(id)
    return self.internalHas("shader", id)
end

return Assets
