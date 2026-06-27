--[[ lib.locale(dict?) + global locale(key, ...) — i18n format engine (clean-room from the ox_lib Locale contract).
     locale(key, ...) looks up the phrase, resolves ${otherKey} references, then string.format's it with the varargs.
     lib.locale(dict) loads phrases into the store (accepts an injected table). Missing key -> returns the key itself.
     DEFERRED (Stage 2b): auto-loading locales/<lang>.json by convar — needs verified HELIX file IO; for now the host build
     bundles locale data as a table passed to lib.locale(). ]]

local store = {}

local function resolvePhrases(s)
    for _ = 1, 5 do                       -- resolve nested ${...} references, bounded
        local n
        s, n = s:gsub("%${([%w_%.]+)}", function(k) return store[k] or ("${" .. k .. "}") end)
        if n == 0 then break end
    end
    return s
end

function locale(key, ...)
    local s = store[key]
    if not s then return key end
    s = resolvePhrases(s)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, s, ...)
        if ok then return formatted end
    end
    return s
end

function lib.locale(dict)
    if type(dict) == "table" then
        for k, v in pairs(dict) do store[k] = v end
    end
    return store
end

-- lib.getLocale(resource, key): cross-resource lookup (simplified — returns from the shared store)
function lib.getLocale(resource, key) return store[key] end

return lib.locale
