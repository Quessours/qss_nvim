return {
    name = "Run all tests",
    builder = function()
        return {
            cmd = { "cargo" },
            args = { "nextest", "run" },
            --components = { { "on_output_quickfix", set_diagnostics = true }, "on_result_diagnostics", "default" }
        }
    end,
    components = { "on_output_quickfix" },
    --[[condition = {
        filetype = { "rs", "toml" }
    }--]]
}
