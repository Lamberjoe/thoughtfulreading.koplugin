--[[
Thoughtful Reading – book club style questions, offline.

At the end of a chapter a card shows two questions of the part of the book you
are in (beginning, middle, end), from different categories; a highlight you
made in that chapter can become a question too. Answer in a few words, attach
a highlight, or just tick "Noted in my journal". All questions and answers of
a book: Tools › Thoughtful Reading. Export as Markdown.

The questions are in questions.txt (copy it to
koreader/settings/thoughtfulreading_questions.txt to change them).
]]

local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local Blitbuffer = require("ffi/blitbuffer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Q = require("tr_questions")
local UI = require("tr_ui")

local KEY = "thoughtful_reading"           -- per book (doc settings)
local SETTINGS = "thoughtful_reading"      -- global (reader settings)
local MIN_CHAPTER_PAGES = 4                -- shorter TOC entries are not a chapter of their own

local FREQ = {
    { id = "chapter", text = _("At every chapter end") },
    { id = "third", text = _("Every 3rd chapter") },
    { id = "sections", text = _("Only beginning, middle, end") },
    { id = "never", text = _("Never (only from the menu)") },
}

local CAT_TITLE = {
    plot = "Plot", pov = "Point of view", characters = "Characters", world = "World", themes = "Themes",
    style = "Style", prediction = "Prediction", personal = "Personal", highlight = "Your highlight",
}

local Plugin = WidgetContainer:extend{
    name = "thoughtfulreading",
    is_doc_only = true,
}

-- ---- settings and state ---------------------------------------------------------------------

local function settings()
    local s = G_reader_settings:readSetting(SETTINGS)
    if type(s) ~= "table" then s = {} end
    s.frequency = s.frequency or "chapter"
    s.per_stop = tonumber(s.per_stop) or 2
    return s
end

local function saveSettings(s) G_reader_settings:saveSetting(SETTINGS, s) end

function Plugin:state()
    if self._state then return self._state end
    local st = self.ui.doc_settings and self.ui.doc_settings:readSetting(KEY)
    if type(st) ~= "table" then st = {} end
    st.answers = type(st.answers) == "table" and st.answers or {}
    st.shown = type(st.shown) == "table" and st.shown or {}
    st.stops = type(st.stops) == "table" and st.stops or {}
    st.sections = type(st.sections) == "table" and st.sections or {}
    self._state = st
    return st
end

function Plugin:save()
    if self.ui.doc_settings and self._state then self.ui.doc_settings:saveSetting(KEY, self._state) end
end

function Plugin:questions()
    if self._questions then return self._questions end
    local user = DataStorage:getSettingsDir() .. "/thoughtfulreading_questions.txt"
    local list, path = Q.load({ user, self.path .. "/questions.txt" })
    self._questions, self._questions_path = list, path
    return list
end

function Plugin:bookInfo()
    local p = self.ui.doc_props or {}
    local tags = Q.bookTags(p.keywords)
    return {
        title = p.display_title or p.title or "", author = p.authors or "",
        tags = tags, nonfiction = Q.isNonfiction(tags),
        series_volume = tonumber(p.series_index) or 0,
    }
end

-- ---- KOReader hooks ---------------------------------------------------------------------------

function Plugin:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Plugin:onDispatcherRegisterActions()
    Dispatcher:registerAction("thoughtful_reading_ask", { category = "none", event = "ThoughtfulReadingAsk",
        title = _("Thoughtful Reading: ask me now"), reader = true })
    Dispatcher:registerAction("thoughtful_reading_list", { category = "none", event = "ThoughtfulReadingList",
        title = _("Thoughtful Reading: questions & answers"), reader = true })
end

function Plugin:onReaderReady()
    self._last_page = nil
    self._ticks = nil
end

function Plugin:onCloseDocument()
    self:save()
    self._state = nil
end

function Plugin:onThoughtfulReadingAsk() self:askNow() return true end

--- For app launchers (ZenOS lists plugins with an open method): the overview.
function Plugin:open() self:showList() end
function Plugin:onThoughtfulReadingList() self:showList() return true end

-- ---- chapters ---------------------------------------------------------------------------------

-- First pages of the chapters (TOC), entries closer than MIN_CHAPTER_PAGES merged.
function Plugin:chapterStarts()
    if self._ticks then return self._ticks end
    local out = {}
    local ok, ticks = pcall(function() return self.ui.toc:getTocTicksFlattened() end)
    if ok and type(ticks) == "table" then
        for _i, p in ipairs(ticks) do
            if #out == 0 or p - out[#out] >= MIN_CHAPTER_PAGES then out[#out + 1] = p end
        end
    end
    self._ticks = out
    return out
end

function Plugin:chapterTitle(page)
    local ok, t = pcall(function() return self.ui.toc:getTocTitleByPage(page) end)
    return ok and t ~= "" and t or nil
end

--- A page turn forward onto the last page of a chapter (or of the book): a stop.
function Plugin:onPageUpdate(page)
    if not page or not self.ui.document then return end
    local prev = self._last_page
    self._last_page = page
    if not prev or page ~= prev + 1 then return end
    local s = settings()
    if s.frequency == "never" then return end
    local total = self.ui.document:getPageCount()
    local starts = self:chapterStarts()
    local is_end, n_chapter, start = page >= total, 0, 1
    for _i, p in ipairs(starts) do
        if p <= page then n_chapter = n_chapter + 1 start = p end
        if p - 1 == page then is_end = true end
    end
    if not is_end then return end
    local st = self:state()
    local key = tostring(start)
    if st.stops[key] then return end
    local pct = page / math.max(1, total)
    local section = Q.sectionAt(pct, page >= total)
    -- the three big stops: the first chapter end after 8 %, after 45 %, and the end
    local big = false
    if not st.sections[section] then
        if (section == "beginning" and pct >= 0.08) or (section == "middle" and pct >= 0.45) or section == "end" then
            big = true
        end
    end
    local go = s.frequency == "chapter" or (s.frequency == "third" and (n_chapter % 3 == 0 or big))
        or (s.frequency == "sections" and big)
    if not go then return end
    st.stops[key] = true
    if big then st.sections[section] = true end
    self:save()
    UIManager:nextTick(function() self:showStop(section, page) end)
end

-- ---- highlights -------------------------------------------------------------------------------

function Plugin:highlights()
    local out = {}
    local annos = self.ui.annotation and self.ui.annotation.annotations or {}
    for _i, a in ipairs(annos) do
        if a.text and a.text ~= "" then
            local page = a.pageno
            if not page and a.pos0 and self.ui.document.getPageFromXPointer then
                local ok, p = pcall(self.ui.document.getPageFromXPointer, self.ui.document, a.pos0)
                page = ok and p or nil
            end
            out[#out + 1] = { text = a.text:gsub("%s+", " "), page = page, id = a.datetime or a.pos0 or a.text,
                where = page and ("p. " .. page) or nil }
        end
    end
    return out
end

-- highlights made in the pages since the last stop
function Plugin:recentHighlights(page)
    local st = self:state()
    local from = st.last_stop_page or 0
    local out = {}
    for _i, h in ipairs(self:highlights()) do
        if h.page and h.page > from and h.page <= page and not st.answers["hl:" .. tostring(h.id)] then
            out[#out + 1] = h
        end
    end
    return out
end

-- ---- choosing ---------------------------------------------------------------------------------

function Plugin:pickFor(section, n, exclude)
    local st = self:state()
    local info = self:bookInfo()
    local answered = {}
    for id in pairs(st.answers) do answered[id] = true end
    return Q.pick(self:questions(), {
        section = section, tags = info.tags, nonfiction = info.nonfiction, series_volume = info.series_volume,
        answered = answered, shown = st.shown, exclude = exclude,
    }, n)
end

local function asCard(q, section)
    return { id = q.id, text = q.text, category = q.category, section = section,
        label = (CAT_TITLE[q.category] or q.category or ""):upper() }
end

-- ---- the card ---------------------------------------------------------------------------------

function Plugin:showStop(section, page)
    local st = self:state()
    local s = settings()
    local n = math.max(1, math.min(3, s.per_stop))
    local list = {}
    -- a highlight of this chapter can be one of the questions
    local hls = self:recentHighlights(page)
    if #hls > 0 and n >= 2 then
        local h = hls[#hls]
        list[1] = { id = "hl:" .. tostring(h.id), text = "Why did you mark this?", category = "highlight",
            section = "chapter", label = "YOUR HIGHLIGHT" .. (h.where and (" · " .. h.where) or ""),
            quote = { text = h.text, where = nil } }
        n = n - 1
    end
    for _i, q in ipairs(self:pickFor(section, n)) do
        list[#list + 1] = asCard(q, section)
        st.shown[q.id] = true
    end
    st.last_stop_page = page
    self:save()
    if #list == 0 then return end
    local chapter = self:chapterTitle(page)
    self:showCard(list, section, chapter, page)
end

function Plugin:showCard(list, section, chapter, page)
    local st = self:state()
    local title = "✎ " .. (chapter and (chapter .. " · ") or "") .. (Q.SECTION_TITLE[section] or "")
    UI.sheet{
        title = title,
        build = function(sheet, w)
            local vg = VerticalGroup:new{ align = "left" }
            for _i, q in ipairs(list) do
                local a = st.answers[q.id]
                local qq = { text = q.text, quote = q.quote,
                    label = q.label .. (a and "   ✓ " .. (a.journal and "journal" or "answered") or "") }
                vg[#vg + 1] = UI.questionBox(qq, w, function()
                    self:answer(q, { chapter = chapter, page = page, done = function() sheet:refresh() end })
                end)
                vg[#vg + 1] = VerticalSpan:new{ width = UI.s(10) }
            end
            vg[#vg + 1] = VerticalSpan:new{ width = UI.s(4) }
            vg[#vg + 1] = UI.buttonRow({
                { text = _("One more"), callback = function()
                    local ex = {}
                    for _i, q in ipairs(list) do ex[q.id] = true end
                    local more = self:pickFor(section == "chapter" and "chapter" or section, 1, ex)
                    if more[1] then
                        list[#list + 1] = asCard(more[1], section)
                        st.shown[more[1].id] = true
                        self:save()
                        sheet:refresh()
                    end
                end },
                { text = _("Answer"), callback = function()
                    for _i, q in ipairs(list) do
                        if not st.answers[q.id] then
                            return self:answer(q, { chapter = chapter, page = page, done = function() sheet:refresh() end })
                        end
                    end
                end },
                { text = _("Keep reading"), primary = true, callback = function() sheet:onClose() end },
            }, w)
            return vg
        end,
    }
end

--- Ask now: the part of the book you are in.
function Plugin:askNow()
    local page = self.ui:getCurrentPage()
    local total = self.ui.document:getPageCount()
    local section = Q.sectionAt(page / math.max(1, total), page >= total)
    self:showStop(section, page)
end

-- ---- answering --------------------------------------------------------------------------------

--- q: { id, text, category, section, quote }; o: { chapter, page, done, text, hl }
function Plugin:answer(q, o)
    local st = self:state()
    local old = st.answers[q.id] or {}
    local hl = o.hl or old.hl
    local desc = q.text
    if q.quote then desc = desc .. "\n»" .. q.quote.text .. "«" end
    if hl then desc = desc .. "\n\n+ »" .. hl.text .. "«" .. (hl.where and (" (" .. hl.where .. ")") or "") end
    local dlg
    local function store(extra)
        local page = o.page or self.ui:getCurrentPage()
        local total = self.ui.document:getPageCount()
        local a = {
            q = q.text, cat = q.category, sec = q.section or Q.sectionAt(page / math.max(1, total), false),
            text = dlg:getInputText(), hl = hl, quote = q.quote and q.quote.text or nil,
            page = page, pct = math.floor(page * 100 / math.max(1, total)), chapter = o.chapter or self:chapterTitle(page),
            time = os.time(),
        }
        for k, v in pairs(extra or {}) do a[k] = v end
        st.answers[q.id] = a
        self:save()
        UIManager:close(dlg)
        if o.done then o.done() end
    end
    dlg = InputDialog:new{
        title = _("Answer"),
        description = desc,
        input = o.text or old.text or "",
        allow_newline = true,
        text_height = require("device").screen:scaleBySize(130),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("+ Highlight"), callback = function()
                local text = dlg:getInputText()
                UIManager:close(dlg)
                self:pickHighlight(function(h)
                    local oo = {}
                    for k, v in pairs(o) do oo[k] = v end
                    oo.text, oo.hl = text, h or hl
                    self:answer(q, oo)
                end)
            end },
        }, {
            { text = _("Noted in my journal"), callback = function() store({ journal = true }) end },
            { text = _("Save"), is_enter_default = false, callback = function() store() end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

--- Choose one of the book's highlights (the newest first).
function Plugin:pickHighlight(done)
    local hls = self:highlights()
    table.sort(hls, function(a, b) return (a.page or 0) > (b.page or 0) end)
    if #hls == 0 then
        UIManager:show(InfoMessage:new{ text = _("No highlights in this book yet."), timeout = 2 })
        return done(nil)
    end
    local Menu = require("ui/widget/menu")
    local menu
    local items = {}
    local answered = false
    local function finish(h)
        if answered then return end
        answered = true
        done(h)
    end
    for _i, h in ipairs(hls) do
        local t = h.text
        if #t > 120 then t = t:sub(1, 117) .. "…" end
        items[#items + 1] = { text = "»" .. t .. "«", mandatory = h.where, callback = function()
            finish(h)
            UIManager:close(menu)
        end }
    end
    menu = Menu:new{
        title = _("Add a highlight"), item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = true, close_callback = function() UIManager:close(menu) finish(nil) end,
    }
    UIManager:show(menu)
end

-- ---- all questions ----------------------------------------------------------------------------

function Plugin:entries(section)
    local st = self:state()
    local info = self:bookInfo()
    local out, seen = {}, {}
    for _i, q in ipairs(self:questions()) do
        local sec = q.section == "series" and "beginning" or q.section
        if sec == section and Q.fits(q, info.tags, info.nonfiction)
            and (q.section ~= "series" or info.series_volume > 1) then
            out[#out + 1] = { q = asCard(q, section), a = st.answers[q.id], idx = #out + 1 }
            seen[q.id] = true
        end
    end
    -- answers to questions not in the list (highlights, a changed question file)
    for id, a in pairs(st.answers) do
        local sec = a.cat == "highlight" and "chapter" or a.sec
        if not seen[id] and sec == section then
            out[#out + 1] = { q = { id = id, text = a.q, category = a.cat, section = sec,
                quote = a.quote and { text = a.quote } or nil, label = "" }, a = a, idx = 9999 }
        end
    end
    -- answered first (in reading order), then open
    table.sort(out, function(x, y)
        if (x.a ~= nil) ~= (y.a ~= nil) then return x.a ~= nil end
        if x.a and y.a and (x.a.page or 0) ~= (y.a.page or 0) then return (x.a.page or 0) < (y.a.page or 0) end
        return x.idx < y.idx
    end)
    return out
end

function Plugin:count()
    local n, done = 0, 0
    for _i, sec in ipairs(Q.SECTIONS) do
        for _j, e in ipairs(self:entries(sec)) do
            n = n + 1
            if e.a then done = done + 1 end
        end
    end
    return done, n
end

function Plugin:entryWidget(e, w, on_tap)
    local mark = e.a and "✓" or "○"
    local mw = UI.s(26)
    local vg = VerticalGroup:new{ align = "left" }
    vg[#vg + 1] = HorizontalGroup:new{ align = "top",
        TextWidget:new{ text = mark, face = Font:getFace("cfont", 17), bold = true },
        HorizontalSpan:new{ width = mw - UI.s(14) },
        TextBoxWidget:new{ text = e.q.text, face = Font:getFace("cfont", 17), bold = true, width = w - mw } }
    local function indent(wdg)
        return HorizontalGroup:new{ HorizontalSpan:new{ width = mw }, wdg }
    end
    if e.q.quote then
        vg[#vg + 1] = VerticalSpan:new{ width = UI.s(4) }
        vg[#vg + 1] = indent(UI.quote(e.q.quote, w - mw))
    end
    if e.a and e.a.text and e.a.text ~= "" then
        vg[#vg + 1] = VerticalSpan:new{ width = UI.s(4) }
        vg[#vg + 1] = indent(TextBoxWidget:new{ text = e.a.text, width = w - mw,
            face = Font:getFace("NotoSerif-Regular.ttf", 16) })
    end
    if e.a and e.a.hl then
        vg[#vg + 1] = VerticalSpan:new{ width = UI.s(4) }
        vg[#vg + 1] = indent(UI.quote(e.a.hl, w - mw))
    end
    local meta
    if e.a then
        meta = (e.a.journal and "✓ journal · " or "") .. (e.a.chapter and (e.a.chapter .. " · ") or "") .. (e.a.pct or 0) .. " %"
    else
        meta = _("open – tap to answer")
    end
    vg[#vg + 1] = VerticalSpan:new{ width = UI.s(2) }
    vg[#vg + 1] = indent(TextWidget:new{ text = meta, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_GRAY_5,
        max_width = w - mw })
    local box = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = UI.s(8) }, vg, VerticalSpan:new{ width = UI.s(8) } }
    return UI.tap(box, w, box:getSize().h, on_tap)
end

function Plugin:showList(section)
    if not section then
        local page = self.ui:getCurrentPage()
        local total = self.ui.document:getPageCount()
        section = Q.sectionAt(page / math.max(1, total), false)
    end
    local page_widget
    local function reopen(sec, p)
        if page_widget then
            page_widget.on_close = nil
            page_widget:onClose()
        end
        page_widget = nil
        self:showList(sec)
        if p and self._list then self._list:gotoPage(p) end
    end
    local done, n = self:count()
    local tabs = {}
    for _i, sec in ipairs(Q.SECTIONS) do
        tabs[#tabs + 1] = { text = Q.SECTION_TITLE[sec], on = sec == section, callback = function() reopen(sec) end }
    end
    page_widget = UI.page{
        title = _("Thoughtful Reading"),
        subtitle = done .. " of " .. n,
        tabs = tabs,
        empty = _("No questions here."),
        items = function(w)
            local out = {}
            for _i, e in ipairs(self:entries(section)) do
                out[#out + 1] = self:entryWidget(e, w, function()
                    local cur = page_widget and page_widget.page
                    self:answer(e.q, { chapter = e.a and e.a.chapter, page = e.a and e.a.page,
                        done = function() reopen(section, cur) end })
                end)
            end
            return out
        end,
        on_close = function() self._list = nil end,
    }
    self._list = page_widget
end

-- ---- export -----------------------------------------------------------------------------------

function Plugin:export()
    local st = self:state()
    local info = self:bookInfo()
    local lines = { "# " .. info.title .. (info.author ~= "" and (" — " .. info.author:gsub("\n", ", ")) or ""), "",
        "_Thoughtful Reading · " .. os.date("%Y-%m-%d") .. "_", "" }
    local any = false
    for _i, sec in ipairs(Q.SECTIONS) do
        local part = {}
        for _j, e in ipairs(self:entries(sec)) do
            if e.a then
                any = true
                part[#part + 1] = "**" .. e.q.text .. "**"
                part[#part + 1] = ""
                if e.q.quote then part[#part + 1] = "> " .. e.q.quote.text part[#part + 1] = "" end
                if e.a.text and e.a.text ~= "" then part[#part + 1] = e.a.text part[#part + 1] = "" end
                if e.a.hl then
                    part[#part + 1] = "> " .. e.a.hl.text .. (e.a.hl.where and (" (" .. e.a.hl.where .. ")") or "")
                    part[#part + 1] = ""
                end
                part[#part + 1] = "_" .. (e.a.journal and "noted in my journal · " or "") .. (e.a.chapter or "")
                    .. " · " .. (e.a.pct or 0) .. " %_"
                part[#part + 1] = ""
            end
        end
        if #part > 0 then
            lines[#lines + 1] = "## " .. Q.SECTION_TITLE[sec]
            lines[#lines + 1] = ""
            for _j, l in ipairs(part) do lines[#lines + 1] = l end
        end
    end
    if not any then
        UIManager:show(InfoMessage:new{ text = _("No answers yet."), timeout = 2 })
        return
    end
    local dir = DataStorage:getFullDataDir() .. "/clipboard"
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local name = (info.title ~= "" and info.title or "book"):gsub("[/\\:*?\"<>|]", "_")
    local path = dir .. "/" .. name .. ".thoughtful.md"
    local f = io.open(path, "w")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not write ") .. path })
        return
    end
    f:write(table.concat(lines, "\n"))
    f:close()
    UIManager:show(InfoMessage:new{ text = _("Exported:") .. "\n" .. path, timeout = 4 })
    logger.info("Thoughtful Reading: exported", path)
end

-- ---- menu -------------------------------------------------------------------------------------

function Plugin:addToMainMenu(menu_items)
    menu_items.thoughtful_reading = {
        text = _("Thoughtful Reading"),
        sorting_hint = "tools",
        sub_item_table_func = function()
            local items = {
                { text_func = function()
                    local done, n = self:count()
                    return _("Questions & answers") .. "  (" .. done .. "/" .. n .. ")"
                end, callback = function(tm) if tm then tm:closeMenu() end self:showList() end },
                { text = _("Ask me now"), callback = function(tm) if tm then tm:closeMenu() end self:askNow() end },
                { text = _("Export answers"), callback = function() self:export() end, separator = true },
            }
            local freq = { text_func = function()
                local f = settings().frequency
                for _i, x in ipairs(FREQ) do if x.id == f then return _("Show questions: ") .. x.text end end
                return _("Show questions")
            end, sub_item_table = {} }
            for _i, x in ipairs(FREQ) do
                freq.sub_item_table[#freq.sub_item_table + 1] = {
                    text = x.text, radio = true,
                    checked_func = function() return settings().frequency == x.id end,
                    callback = function() local s = settings() s.frequency = x.id saveSettings(s) end,
                }
            end
            items[#items + 1] = freq
            local per = { text_func = function() return _("Questions per stop: ") .. settings().per_stop end,
                sub_item_table = {} }
            for n = 1, 3 do
                per.sub_item_table[#per.sub_item_table + 1] = {
                    text = tostring(n), radio = true,
                    checked_func = function() return settings().per_stop == n end,
                    callback = function() local s = settings() s.per_stop = n saveSettings(s) end,
                }
            end
            items[#items + 1] = per
            items[#items + 1] = { text = _("Question file"), keep_menu_open = true, callback = function()
                self:questions()
                UIManager:show(InfoMessage:new{ text = _("Questions from:") .. "\n" .. tostring(self._questions_path)
                    .. "\n\n" .. _("Own list: copy questions.txt from the plugin folder to\nkoreader/settings/thoughtfulreading_questions.txt and change it there.") })
            end }
            return items
        end,
    }
end

return Plugin
