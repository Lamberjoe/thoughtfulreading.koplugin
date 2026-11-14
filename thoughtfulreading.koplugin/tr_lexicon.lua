-- Thoughtful Reading: the book's lexicon, read only.
-- The Book Lexicon plugin (and the lexicon of the ZenOS fork) keep one file per book:
--   <koreader>/lexicon/Books/<Author - Title>/lexicon.md   (German: Bücher/)
-- Thoughtful Reading never writes to it. Without that file there are simply no
-- lexicon questions.
-- Pure Lua except M.path (KOReader's data folder), so it can be tested on its own.

local M = {}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function clean(s) return (tostring(s or ""):gsub("\194\173", "")) end   -- soft hyphens

-- words after "Kind:" (as in Book Lexicon)
local KIND = {
    person = "Person", people = "Person", figur = "Person", character = "Person",
    object = "Object", gegenstand = "Object", item = "Object", thing = "Object",
    group = "Group", gruppe = "Group", faction = "Group", fraktion = "Group",
    place = "Place", ort = "Place", location = "Place",
    other = "Other", sonstiges = "Other", andere = "Other",
}
local ALSO = { also = true, auch = true, ["other names"] = true, ["weitere namen"] = true, aliases = true }

--- "Main", "Side" or nil from a "Role:" fact on the card.
local function role(v)
    v = trim(v):lower()
    if v:find("^main") or v:find("^haupt") or v:find("^protagonist") then return "Main" end
    if v:find("^side") or v:find("^neben") or v:find("^minor") then return "Side" end
end

--- Cards: { { name, kind, also = {...}, role = "Main"|"Side"|nil, rels = { {type, target} } } }
function M.parse(text)
    local cards, card = {}, nil
    text = tostring(text or ""):gsub("\r\n", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local h2 = line:match("^##%s+(.-)%s*$")
        if h2 then
            card = { name = clean(h2), kind = "Other", also = {}, rels = {} }
            cards[#cards + 1] = card
        elseif card and not line:match("^[-*]%s") then
            local rel = line:match("^→%s*(.*)$") or line:match("^%->%s*(.*)$")
            if rel then
                rel = rel:gsub("%s*[%[{].*$", "")
                local t, target = rel:match("^(.-):%s*(.+)$")
                if t and trim(target) ~= "" then card.rels[#card.rels + 1] = { type = trim(t), target = trim(target) } end
            else
                local key, val = line:match("^([^:]+):%s*(.*)$")
                if key and #key <= 32 then
                    local k = trim(key):lower()
                    if (k == "kind" or k == "art") and KIND[trim(val):lower()] then
                        card.kind = KIND[trim(val):lower()]
                    elseif ALSO[k] then
                        for a in val:gmatch("[^,;]+") do
                            if trim(a) ~= "" then card.also[#card.also + 1] = clean(trim(a)) end
                        end
                    elseif k == "role" or k == "rolle" then
                        card.role = role(val)
                    end
                end
            end
        end
    end
    return cards
end

local function safeName(s)
    s = clean(s):gsub("[/\\:%*%?\"<>|]", "_")
    s = trim(s):gsub("%.+$", "")
    return s ~= "" and s or "_"
end

--- "Author - Title" as Book Lexicon names the folder.
function M.key(props, file)
    props = props or {}
    local title = clean(props.display_title or props.title or "")
    if title == "" and file then title = file:match("([^/]+)%.%w+$") or "?" end
    local author = props.authors and clean(tostring(props.authors):match("^[^\n]+") or "") or ""
    return (author ~= "" and (author .. " - ") or "") .. title
end

--- The lexicon file of a book, or nil.
function M.path(props, file)
    local lfs = require("libs/libkoreader-lfs")
    local root = require("datastorage"):getDataDir() .. "/lexicon"
    local name = safeName(M.key(props, file))
    for _i, dir in ipairs({ "Books", "Bücher" }) do
        local p = root .. "/" .. dir .. "/" .. name .. "/lexicon.md"
        if lfs.attributes(p, "mode") == "file" then return p end
    end
end

function M.load(path)
    if not path then return {} end
    local f = io.open(path, "r")
    if not f then return {} end
    local t = f:read("*a")
    f:close()
    return M.parse(t)
end

function M.persons(cards)
    local out = {}
    for _i, c in ipairs(cards) do
        if c.kind == "Person" then out[#out + 1] = c end
    end
    return out
end

-- ---- counting -----------------------------------------------------------------------------------

local QUOTES = { "„", "“", "”", "‚", "‘", "’", "»", "«", "›", "‹", "–", "—", "…" }

--- Text as " word word " (punctuation removed), for finding whole names.
function M.words(text)
    text = clean(text)
    for _i, q in ipairs(QUOTES) do text = text:gsub(q, " ") end
    text = text:gsub("['`]s%f[%A]", " ")      -- Cain's
    text = text:gsub("[%p%c%s]+", " ")
    return " " .. text .. " "
end

local function escape(s) return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")) end

--- Count the person cards in a text; adds to tally[name]. Longer names first,
--- so "Ciaphas Cain" is not counted again as "Cain". German genitive "Cains" counts.
function M.count(text, cards, tally)
    local t = M.words(text)
    local names = {}
    for _i, c in ipairs(M.persons(cards)) do
        for _j, n in ipairs({ c.name, unpack(c.also) }) do
            n = trim(M.words(n))
            if #n >= 2 then names[#names + 1] = { n = n, card = c.name } end
        end
    end
    table.sort(names, function(a, b) return #a.n > #b.n end)
    for _i, x in ipairs(names) do
        local p = escape(x.n)
        local k
        -- the space after the name stays, so "Sulla Sulla" counts twice
        t, k = t:gsub(" " .. p .. "s?%f[ ]", " ")
        if k > 0 then tally[x.card] = (tally[x.card] or 0) + k end
    end
    return tally
end

--- Roles from the counts: the 2–3 most named persons with at least 15 % of all
--- mentions are main characters, the others side characters. "Role:" on a card wins.
--- Returns { { name, card, count, share, role = "Main"|"Side"|nil, fixed } } (most named first)
function M.roles(cards, tally)
    local list, total = {}, 0
    for _i, c in ipairs(M.persons(cards)) do
        local n = tally[c.name] or 0
        total = total + n
        list[#list + 1] = { name = c.name, card = c, count = n }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local mains = 0
    for _i, e in ipairs(list) do
        e.share = total > 0 and math.floor(e.count * 100 / total + 0.5) or 0
        if e.card.role then
            e.role, e.fixed = e.card.role, true
        elseif e.count == 0 then
            e.role = nil
        elseif mains < 3 and e.count / total >= 0.15 then
            e.role = "Main"
            mains = mains + 1
        else
            e.role = "Side"
        end
    end
    return list
end

--- Are the two cards related (either direction)?
local function isCard(name, c)
    name = trim(name):lower()
    if name == c.name:lower() then return true end
    for _i, x in ipairs(c.also) do if name == x:lower() then return true end end
end

function M.related(a, b)
    for _i, r in ipairs(a.rels) do if isCard(r.target, b) then return r.type end end
    for _i, r in ipairs(b.rels) do if isCard(r.target, a) then return r.type end end
end

return M
