local M = {}

---@param dir string
---@return boolean
function M.is_cmake_project(dir)
    return vim.fn.filereadable(dir .. '/CMakeLists.txt') == 1
end

---@return table?
local function tools()
    local ok, cmake_tools = pcall(require, 'cmake-tools')
    return ok and cmake_tools or nil
end

--- Preset names as cmake-tools parses them: CMakeUserPresets.json, `include`,
--- inheritance and hidden presets all resolved.
---@param kind string "configure" or "build"
---@return string[]
function M.preset_names(kind)
    local ok, presets_module = pcall(require, 'cmake-tools.presets')
    local cwd = vim.uv.cwd()
    if not ok or not presets_module.exists(cwd) then
        return {}
    end

    local presets = presets_module:parse(cwd)
    if kind == 'configure' then
        return presets:get_configure_preset_names({})
    end
    return presets:get_build_preset_names({})
end

--- The preset cmake-tools currently has selected, so a task defaults to the one
--- the :CMake* commands would use rather than to the first in the file.
---@param kind string "configure" or "build"
---@return string?
function M.selected_preset(kind)
    local cmake_tools = tools()
    if not cmake_tools then
        return nil
    end
    if kind == 'configure' then
        return cmake_tools.get_configure_preset()
    end
    return cmake_tools.get_build_preset()
end

--- cmake_build_directory is a template string, and cmake-tools only expands it
--- once it has configured the project in this session. Before that it hands back
--- the raw "out/${variant:buildType}", which cmake would take literally.
---@return string
function M.build_dir()
    local cmake_tools = tools()
    local dir = cmake_tools and cmake_tools.get_build_directory()
    if not dir then
        return 'build'
    end

    dir = tostring(dir):gsub('%${variant:buildType}', M.build_type())
    dir = dir:gsub('%${[^}]*}', '')
    return (dir:gsub('//+', '/'):gsub('/$', ''))
end

---@return string
function M.build_type()
    local cmake_tools = tools()
    return (cmake_tools and cmake_tools.get_build_type()) or 'Debug'
end

--- Buildable targets from the CMake file API. Empty until the tree has been
--- configured once, which is why the callers keep a free-text fallback.
---@return string[]
function M.build_targets()
    local cmake_tools = tools()
    if not cmake_tools then
        return {}
    end

    local ok, result = pcall(cmake_tools.get_build_targets)
    if not ok or not result or not result.data or not result.data.targets then
        return {}
    end
    return result.data.targets
end

---@return string[]
function M.generate_options()
    local cmake_tools = tools()
    return (cmake_tools and cmake_tools.get_generate_options()) or {}
end

---@return string[]
function M.build_options()
    local cmake_tools = tools()
    return (cmake_tools and cmake_tools.get_build_options()) or {}
end

return M
