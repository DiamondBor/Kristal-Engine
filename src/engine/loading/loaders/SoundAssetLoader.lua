---@class SoundAssetLoader : AssetLoader<Sound, SoundAssetLoader.Task, SoundAssetLoader.Result>
---@overload fun(valid_subfolders: string[], audio_extensions: string[], metadata_extension: string) : SoundAssetLoader
local SoundAssetLoader, super = Class(AssetLoader, "ShaderAssetLoader"), AssetLoader

---@class SoundAssetLoader.Task
---@field source_path string?
---@field metadata_path string?
---@field metadata_relative_path string?

---@class SoundAssetLoader.Result
---@field sound_data love.SoundData?
---@field metadata Assets.sound_settings?

function SoundAssetLoader:init(valid_subfolders, audio_extensions, metadata_extension)
    self.audio_extensions = audio_extensions
    self.metadata_extension = metadata_extension
    super.init(self, valid_subfolders, {metadata_extension, unpack(audio_extensions)})
end

function SoundAssetLoader:beginLoad(file, queue)
    -- Pass the file path to the load thread
    queue[file.identifier] = queue[file.identifier] or {}
    if file.extension == self.metadata_extension then
        queue[file.identifier].metadata_path = file.full_path
        queue[file.identifier].metadata_relative_path = file.relative_path
    else
        queue[file.identifier].source_path = file.full_path 
    end
end

function SoundAssetLoader:load(asset_id, task)
    ---@type SoundAssetLoader.Result
    local result = {}
    if task.source_path then
        local success, sound_data = pcall(love.sound.newSoundData, task.source_path)
        if success then
            result.sound_data = sound_data
        end
    end
    if task.metadata_path then
        local success, metadata = pcall(JSON.decode, love.filesystem.read(task.metadata_path))
        if not success then
            local path = task.metadata_relative_path or task.metadata_path
            error(string.format("Sound \"%s\" has an invalid json file!", path))
        end
        result.metadata = metadata
    end

    return result
end

function SoundAssetLoader:apply(asset_id, output)
    if not output.sound_data then return nil end
    return Sound(output.sound_data, output.metadata)
end

function SoundAssetLoader:release(asset)
    if asset.isDestroyed and asset:isDestroyed() then return end
    asset:stop()
    self:releaseObject(asset.source)
    self:releaseObject(asset.data)
end

function SoundAssetLoader:releaseOutput(output)
    self:releaseObject(output.sound_data)
end

return SoundAssetLoader
