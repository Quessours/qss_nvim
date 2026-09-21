-- https://github.com/redhat-developer/yaml-language-server
--
-- nvim-lspconfig ships the cmd and the filetypes, so this adds only the
-- schemas. kas validates its own config files against a JSON schema it ships,
-- and pointing the server at that file is what turns a kas config from plain
-- text into something that completes keys and reports a wrong one.

-- Where the kas package keeps its schema, for a pip install and a distribution
-- package alike.
local SCHEMA_PATTERNS = {
    '/usr/lib/python3*/dist-packages/kas/schema-kas.json',
    '/usr/lib/python3*/site-packages/kas/schema-kas.json',
    vim.fn.expand('~') .. '/opt/kas/kas/schema-kas.json',
    vim.fn.expand('~') .. '/.local/lib/python3*/site-packages/kas/schema-kas.json',
}

-- The kas config lives at the project root, or in a kas/ directory below it.
local KAS_FILES = {
    '/kas*.yml',
    '/kas*.yaml',
    '/kas/*.yml',
    '/kas/*.yaml',
    '/.config.yaml',
}

---@return string?
local function kas_schema()
    for _, pattern in ipairs(SCHEMA_PATTERNS) do
        local found = vim.fn.glob(pattern, true, true)[1]
        if found and vim.fn.filereadable(found) == 1 then
            return found
        end
    end
    return nil
end

---@return table<string, string[]>
local function schemas()
    local schema = kas_schema()
    if not schema then
        return {}
    end
    return { [schema] = KAS_FILES }
end

---@type vim.lsp.Config
return {
    settings = {
        yaml = {
            schemas = schemas(),
            schemaStore = {
                enable = true,
                url = 'https://www.schemastore.org/api/json/catalog.json',
            },
        },
    },
}
