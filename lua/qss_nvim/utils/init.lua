local merge_tb = vim.tbl_deep_extend

function apply_mappings(mappings)
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

function dump_table(o)
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
