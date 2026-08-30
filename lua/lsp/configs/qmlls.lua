local prototype_noise = {
    ['__defineGetter__'] = true,
    ['__defineSetter__'] = true,
    ['__lookupGetter__'] = true,
    ['__lookupSetter__'] = true,
    ['__proto__'] = true,
}

-- QML syntactic coloration palettes, extracted from QtCreator's styles.
local palettes = {}

-- creator-dark.xml, the "Qt Creator Dark" theme. Its Text is #d6cf9a.
palettes['creator-dark'] = {
    namespace                 = { fg = '#9aa7d6' },                -- Global
    type                      = { fg = '#66a334' },                -- QmlTypeId
    enum                      = { fg = '#ff8080' },                -- Type
    enumMember                = { fg = '#66a334', italic = true }, -- Static
    parameter                 = { fg = '#d6bb9a' },                -- Parameter
    variable                  = { fg = '#d6bb9a' },                -- Local
    method                    = { fg = '#d6cf9a' },                -- Function -> Text
    keyword                   = { fg = '#45c6d6', italic = true }, -- Keyword
    comment                   = { fg = '#a8abb0', italic = true }, -- Comment
    string                    = { fg = '#d69545' },                -- String
    number                    = { fg = '#8a602c' },                -- Number
    regexp                    = { fg = '#d69545' },                -- String
    operator                  = { fg = '#d6bb9a' },                -- Operator
    decorator                 = { fg = '#45c6d6', italic = true }, -- Attribute
    property                  = { fg = "#a26070", italic = true }, -- QmlScopeObjectProperty
    qmlLocalId                = { fg = '#9acfd6', italic = true }, -- QmlLocalId
    qmlExternalId             = { fg = '#9aa7d6', italic = true }, -- QmlExternalId
    qmlRootObjectProperty     = { fg = '#d6cf9a', italic = true }, -- QmlRootObjectProperty -> Text
    qmlScopeObjectProperty    = { fg = '#d6cf9a', italic = true }, -- QmlScopeObjectProperty -> Text
    qmlExternalObjectProperty = { fg = '#9aa7d6', italic = true }, -- QmlExternalObjectProperty
    qmlStateName              = { fg = '#45c6d6', italic = true }, -- QmlStateName
    jsScopeVar                = { fg = '#9acfd6', italic = true }, -- JsScopeVar
    jsImportVar               = { fg = '#4564d6', italic = true }, -- JsImportVar
    jsGlobalVar               = { fg = '#4564d6', italic = true }, -- JsGlobalVar
}

-- dark.xml, the plainer and far more saturated "Dark" theme. Its Text is
-- #aaaaaa, and it leaves many more categories to inherit it.
palettes['dark'] = {
    namespace                 = { fg = '#aaaaaa' },                -- Global -> Text
    type                      = { fg = '#55ff55' },                -- QmlTypeId
    enum                      = { fg = '#55ff55' },                -- Type
    enumMember                = { fg = '#55ff55', italic = true }, -- Static
    parameter                 = { fg = '#aaaaaa' },                -- Parameter -> Text
    variable                  = { fg = '#aaaaaa' },                -- Local -> Text
    method                    = { fg = '#aaaaaa' },                -- Function -> Text
    keyword                   = { fg = '#ffff55' },                -- Keyword
    comment                   = { fg = '#55ffff' },                -- Comment
    string                    = { fg = '#ff55ff' },                -- String
    number                    = { fg = '#ff55ff' },                -- Number
    regexp                    = { fg = '#ff55ff' },                -- String
    operator                  = { fg = '#aaaaaa' },                -- Operator
    decorator                 = { fg = '#ffff55' },                -- Attribute
    property                  = { fg = '#aaaaaa', italic = true }, -- QmlScopeObjectProperty -> Text
    qmlLocalId                = { fg = '#aaaaaa', italic = true }, -- QmlLocalId -> Text
    qmlExternalId             = { fg = '#aaaaff', italic = true }, -- QmlExternalId
    qmlRootObjectProperty     = { fg = '#aaaaaa', italic = true }, -- QmlRootObjectProperty -> Text
    qmlScopeObjectProperty    = { fg = '#aaaaaa', italic = true }, -- QmlScopeObjectProperty -> Text
    qmlExternalObjectProperty = { fg = '#aaaaff', italic = true }, -- QmlExternalObjectProperty
    qmlStateName              = { fg = '#aaaaaa', italic = true }, -- QmlStateName -> Text
    jsScopeVar                = { fg = '#8888ff', italic = true }, -- JsScopeVar
    jsImportVar               = { fg = '#8888ff', italic = true }, -- JsImportVar
    jsGlobalVar               = { fg = '#8888ff', italic = true }, -- JsGlobalVar
}

-- Qt Creator's "Binding" category, for the property name left of the colon.
-- It is not a semantic token: qmlls tags both sides of a binding "property",
-- so the distinction comes from the @qml.binding.target capture in
-- after/queries/qmljs/highlights.scm.
local binding_target = {
    ['creator-dark'] = { fg = '#ff6aad' }, -- Binding
    ['dark']         = { fg = '#ff5555' }, -- Binding
}

-- Swap the QML palette by changing this one line.
local current_palette = 'creator-dark'

assert(palettes[current_palette], ("unknown QML palette '%s'"):format(current_palette))

return {
    cmd = { 'qmlls' },
    filetypes = { 'qml', 'qmljs' },
    root_markers = { '.qmlls.ini', 'CMakeLists.txt', '.git' },
    workspace_required = false,
    on_init = function(client)
        local completion = client.server_capabilities.completionProvider
        if completion then
            completion.triggerCharacters = { '.', ':' }
        end
    end,
    filter_completion_item = function(item)
        return not prototype_noise[item.label]
    end,
    format_on_save = true,
    semantic_token_highlights = palettes[current_palette],
    highlights = {
        ['@qml.binding.target'] = binding_target[current_palette],
    },
}
