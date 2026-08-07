---@class FontAssetLoader : AssetLoader< Partial< FontAssetLoader.Font >, FontAssetLoader.Task, FontAssetLoader.Output >
---@overload fun(valid_subfolders: string[], valid_extensions: string[]) : FontAssetLoader
local FontAssetLoader, super = Class(AssetLoader, "PathAssetLoader"), AssetLoader

---@alias FontAssetLoader.Output FontAssetLoader.OutputWithFontData | FontAssetLoader.OutputWithImageData | FontAssetLoader.OutputWithBMFont

---@class FontAssetLoader.OutputWithFontData
---@field font_data love.FileData
---@field settings FontAssetLoader.FontSettings?

---@class FontAssetLoader.OutputWithImageData
---@field image_data love.ImageData
---@field settings FontAssetLoader.FontSettings?

---@class FontAssetLoader.OutputWithBMFont
---@field bmfont_path string
---@field settings FontAssetLoader.FontSettings?

---@alias FontAssetLoader.FontSettings Assets.font_settings

---@alias FontAssetLoader.Task FontAssetLoader.TaskWithFontData | FontAssetLoader.TaskWithImageData | FontAssetLoader.TaskWithBMFont

---@class FontAssetLoader.TaskWithFontData
---@field font_path string
---@field settings_path string?
---@field settings_relative_path string?

---@class FontAssetLoader.TaskWithImageData
---@field image_path string
---@field settings_path string?
---@field settings_relative_path string?

---@class FontAssetLoader.TaskWithBMFont
---@field bmfont_path string
---@field settings_path string?
---@field settings_relative_path string?

---@class FontAssetLoader.Font
---@field image_data love.ImageData
---@field default integer
---@field font love.Font
---@field settings FontAssetLoader.FontSettings
---@field font_data love.FileData?

function FontAssetLoader:init(valid_subfolders, valid_extensions)
    super.init(self, valid_subfolders, valid_extensions)
end

function FontAssetLoader:beginLoad(file, queue)
    local task = queue[file.identifier] or {} ---@as FontAssetLoader.Task
    queue[file.identifier] = task

    if file.extension == "json" then
        task.settings_path = file.full_path
        task.settings_relative_path = file.relative_path
    elseif file.extension == "ttf" then
        task.font_path = file.full_path
    elseif file.extension == "png" and not love.filesystem.getInfo(file.base_path .. "/" .. file.identifier:sub(1, -3) .. ".fnt") then
        task.image_path = file.full_path
    elseif file.extension == "fnt" then
        task.bmfont_path = file.full_path
    end
end

function FontAssetLoader:load(asset_id, task)
    local output = {} ---@as FontAssetLoader.Output
    if task.bmfont_path then
        output.bmfont_path = task.bmfont_path
    end
    if task.font_path then
        local success, font_data = pcall(love.filesystem.newFileData, task.font_path)
        if success then
            output.font_data = font_data
        end
    end
    if task.image_path then
        local success, image_data = pcall(love.image.newImageData, task.image_path)
        if success then
            output.image_data = image_data
        end
    end
    if task.settings_path then
        local success, settings = pcall(JSON.decode, love.filesystem.read(task.settings_path))
        if not success then
            local path = task.settings_relative_path or task.settings_path
            error(string.format("Font \"%s\" has an invalid json file!", path))
        end
        output.settings = settings
    end
    return output
end

function FontAssetLoader:apply(asset_id, output)
    if not output.font_data and not output.image_data and not output.bmfont_path then
        return nil
    end
    if not output.font_data then
        output.settings = output.settings or {}
        output.settings.autoScale = output.settings.autoScale ~= false
    end
    local default = output.settings and output.settings.defaultSize or 12;
    ---@type Partial<FontAssetLoader.Font>
    local font = {
        image_data = output.image_data;
        default = default;
        settings = output.settings;
        font = (
            nil
            or (output.bmfont_path and love.graphics.newFont(output.bmfont_path))
            or (output.image_data and output.settings and love.graphics.newImageFont(output.image_data, output.settings.glyphs or ""))
        );
        font_data = output.font_data;
    } 
    return font
end

function FontAssetLoader:release(asset)
    for _, value in pairs({ asset.font, asset.image_data, asset.font_data }) do
        self:releaseObject(value)
    end
end

function FontAssetLoader:releaseOutput(output)
    for _, value in pairs({ output.image_data, output.font_data }) do
        self:releaseObject(value)
    end
end

return FontAssetLoader
