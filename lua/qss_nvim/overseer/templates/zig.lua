return {
    name = "zig build",
    builder = function()
        return {
            cmd = { "zig" },
            args = { "build" },
            components = { "default" }
        }
    end,
    condition = {
        filetype = { "zig" }
    }
}
