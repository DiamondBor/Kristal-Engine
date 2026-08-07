---@class Kristal.Mods
---
---@field loaded boolean
---@field list table[]
---@field data table<string, ProjectInfo>
---@field named table<string, string>
---@field failed_mods table[]
---
local Mods = {}
local self = Mods

local compile_state = nil

-- TODO: Document mod data

---@alias ProjectInfo table

function Mods.clear()
    self.loaded = false
    self.list = {}
    self.data = {}
    self.named = {}
    self.failed_mods = {}
end

---@param data table<string, ProjectInfo>
---@param failed_mods table[]
function Mods.loadData(data, failed_mods)
    self.failed_mods = failed_mods or {}
    for mod_id, mod_data in pairs(data) do
        if self.data[mod_id] then
            local old_mod = self.data[mod_id]
            if old_mod.name then
                self.named[old_mod.name] = nil
            end
            TableUtils.removeValue(self.list, old_mod)
        end

        -- convert image data into images
        if mod_data.preview_data then
            mod_data.preview = {}
            for _, img_data in ipairs(mod_data.preview_data) do
                table.insert(mod_data.preview, love.graphics.newImage(img_data))
            end
        end
        if mod_data.icon_data then
            mod_data.icon = {}
            for _, img_data in ipairs(mod_data.icon_data) do
                table.insert(mod_data.icon, love.graphics.newImage(img_data))
            end
        end
        if mod_data.logo_data then
            mod_data.logo = love.graphics.newImage(mod_data.logo_data)
        end

        mod_data.script_chunks = {}

        mod_data.libs = mod_data.libs or {}
        for _, lib_data in pairs(mod_data.libs) do
            lib_data.script_chunks = {}
        end

        if not mod_data.lib_order then
            mod_data.lib_order = self.sortLibraries(mod_data)
        end

        mod_data.loaded_scripts = false

        self.data[mod_id] = mod_data
        if mod_data.name then
            self.named[mod_data.name] = mod_id
        end
        table.insert(self.list, self.data[mod_id])
    end

    Input.loadBinds()
end

function Mods.sortLibraries(mod)
    local sorted = {}

    local unsorted = {}
    local sorted_lookup = {}

    for lib_id, _ in pairs(mod.libs) do
        table.insert(unsorted, lib_id)
    end

    while #unsorted > 0 do
        local new_unsorted = {}

        for _, lib_id in ipairs(unsorted) do
            local lib_data = mod.libs[lib_id]

            local failed = false

            for _, dependency in ipairs(lib_data["dependencies"] or {}) do
                if not sorted_lookup[dependency] then
                    failed = true
                    break
                end
            end

            for _, dependency in ipairs(lib_data["optionalDependencies"] or {}) do
                if mod.libs[dependency] and not sorted_lookup[dependency] then
                    failed = true
                    break
                end
            end

            if failed then
                table.insert(new_unsorted, lib_id)
            else
                table.insert(sorted, lib_id)
                sorted_lookup[lib_id] = true
            end
        end

        if #new_unsorted == #unsorted then
            for _, lib_id in ipairs(new_unsorted) do
                Kristal.Console:warn(
                    string.format(
                        "Issue loading mod '%s' - Dependencies for library '%s' failed to load, likely circular dependency",
                        mod.id,
                        lib_id
                    )
                )

                table.insert(sorted, lib_id)
            end
            break
        end

        unsorted = new_unsorted
    end

    return sorted
end

---@return ProjectInfo[]
function Mods.getMods()
    return self.list or {}
end

---@param id string
---@return ProjectInfo?
function Mods.getMod(id)
    return self.data[id] or (self.named[id] and self.data[self.named[id]])
end

local function compileStep()
    local state = compile_state
    if not state then return end
    local frame = FRAMERATE > 0 and (1 / FRAMERATE) or (1 / 60)
    if love.timer.getTime() - state.budget_at >= math.max(frame * 0.7, 0.012) then
        coroutine.yield()
        state.budget_at = love.timer.getTime()
    end
end

---@param id string
---@return ProjectInfo?
function Mods.getAndLoadMod(id)
    local mod = self.getMod(id)

    if not mod then
        return nil
    end

    if not mod.loaded_scripts then
        local files = FileSystemUtils.getFilesRecursive(mod.path, ".lua")
        for _, path in ipairs(files) do
            mod.script_chunks[path] = love.filesystem.load(mod.path .. "/" .. path .. ".lua")
            compileStep()
        end

        for _, lib in pairs(mod.libs) do
            local paths
            if lib.path:sub(1, #mod.path + 1) == mod.path .. "/" then
                local prefix = lib.path:sub(#mod.path + 2) .. "/"
                paths = {}
                for _, path in ipairs(files) do
                    if path:sub(1, #prefix) == prefix then
                        table.insert(paths, path:sub(#prefix + 1))
                    end
                end
                --if #paths == 0 then paths = nil end
            end
            for _, path in ipairs(paths or FileSystemUtils.getFilesRecursive(lib.path, ".lua")) do
                lib.script_chunks[path] = love.filesystem.load(lib.path .. "/" .. path .. ".lua")
                compileStep()
            end
        end

        mod.loaded_scripts = true
    end

    return mod
end

---@param id string
---@return ProjectInfo?
---@return table? steps
function Mods.loadModScriptSteps(id)
    local mod = self.getMod(id)

    if not mod or mod.loaded_scripts then return mod, nil end

    local steps = {}
    steps.thread = coroutine.create(function()
        compile_state = steps
        steps.budget_at = love.timer.getTime()
        self.getAndLoadMod(id)
        compile_state = nil
    end)

    return mod, steps
end

---@param id string
---@return string
function Mods.getName(id)
    return self.data[id].name or id
end

return Mods
