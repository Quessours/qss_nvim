local merge_tb = vim.tbl_deep_extend


M = {}

M.apply_mappings = function(mappings)
    for mode, mode_values in pairs(mappings) do
        local default_opts = merge_tb("force", { mode = mode }, mapping_opt or {})
        for keybind, mapping_info in pairs(mode_values) do
            -- merge default + user opts
            local opts = merge_tb("force", default_opts, mapping_info.opts or {})

            mapping_info.opts, opts.mode = nil, nil
            opts.desc = mapping_info[2]
            vim.keymap.set(mode, keybind, mapping_info[1], opts)
        end
    end
end

dump_table = function(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump_table(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

M.dump_table = dump_table

M.scan_dir = function()
    local i, t, popen = 0, {}, io.popen
    local pfile = popen('find -maxdepth 1 -printf "%f\n"')
    for filename in pfile:lines() do
        i = i + 1
        t[i] = filename
    end
    pfile:close()
    return t
end
M.execute_and_capture_output = function(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end


return M
