local inlay_hints_option =
{
    -- automatically set inlay hints (type hints)
    -- default: true
    auto = true,

    -- Only show inlay hints for the current line
    only_current_line = false,

    -- whether to show parameter hints with the inlay hints or not
    -- default: true
    show_parameter_hints = true,

    -- prefix for parameter hints
    -- default: "<-"
    parameter_hints_prefix = "<- ",

    -- prefix for all the other hints (type, chaining)
    -- default: "=>"
    other_hints_prefix = "=> ",

    -- whether to align to the length of the longest line in the file
    max_len_align = false,

    -- padding from the left if max_len_align is true
    max_len_align_padding = 1,

    -- whether to align to the extreme right or not
    right_align = false,

    -- padding from the right if right_align is true
    right_align_padding = 7,

    -- The color of the hints
    highlight = "LspInlayHint",
}

local M = {}
M.tables = {}

function M.new()
    M.namespace = vim.api.nvim_create_namespace("textDocument/inlayHints")
    local self = setmetatable({ cache = {}, enabled = false }, { __index = M })

    return self
end

local function parse_hint_label(hint_label)
    if type(hint_label) == "string" then
        return hint_label
    elseif type(hint_label) == "table" then
        return table.concat(vim.tbl_map(function(label_part)
            return label_part.value
        end, hint_label))
    end
end

function M.formatInlayHints(line_hints)
    local opts = inlay_hints_option
    local virt_text = ""

    local param_hints = {}
    local other_hints = {}

    -- segregate parameter hints and other hints
    for _, hint in ipairs(line_hints) do
        if hint.kind == "parameter" then
            table.insert(param_hints, parse_hint_label(hint.label))
        end

        if hint.kind == "type" then
            table.insert(other_hints, parse_hint_label(hint.label))
        end
    end

    -- show parameter hints inside brackets with commas and a thin arrow
    if not vim.tbl_isempty(param_hints) and opts.show_parameter_hints then
        virt_text = virt_text .. opts.parameter_hints_prefix .. "("
        for i, p_hint in ipairs(param_hints) do
            virt_text = virt_text .. p_hint:sub(1, -1)
            if i ~= #param_hints then
                virt_text = virt_text .. ", "
            end
        end
        virt_text = virt_text .. ") "
    end

    -- show other hints with commas and a thicc arrow
    if not vim.tbl_isempty(other_hints) then
        virt_text = virt_text .. opts.other_hints_prefix
        for i, o_hint in ipairs(other_hints) do
            virt_text = virt_text .. o_hint:gsub("^: ", "")
            if i ~= #other_hints then
                virt_text = virt_text .. ", "
            end
        end
    end

    -- set the virtual text if it is not empty
    if virt_text ~= "" then
        ---@diagnostic disable-next-line: param-type-mismatch
        if opts.right_align then
            virt_text = virt_text .. string.rep(" ", opts.right_align_padding)
        end
    end


    return { { virt_text, "LspInlayHint" } }
end

return M
