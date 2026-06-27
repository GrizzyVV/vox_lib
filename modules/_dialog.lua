--[[ _dialog.lua — shared scaffolding for RETURN-VALUE WebUI dialogs (alert/input/context/menu/skillcheck/radial).
     The return-value pattern (probe-verified 2026-06-26): create a WebUI page, register a one-shot response handler on
     the proven page->Lua reverse channel (hEvent -> ui:RegisterEventHandler), SendEvent the show payload, then YIELD
     (Wait) until the page replies. Wait is the bundled coroutine+Timer scheduler — so a return-value dialog MUST be
     called from inside a thread (CreateThread / Timer.CreateThread); yielding on the main lua thread is illegal on HELIX.
     One Dialog instance per component; the WebUI page + handler are created lazily, once. ]]

local Dialog = {}
Dialog.__index = Dialog

-- uiName: unique WebUI id · page: package-relative html path · respEvent: the hEvent name the page emits on resolve
function Dialog.new(uiName, page, respEvent)
    return setmetatable({ name = uiName, page = page, respEvent = respEvent, ui = nil, pending = nil }, Dialog)
end

function Dialog:ensure()
    if self.ui or not WebUI then return self.ui end
    -- mode 1 set per-request; create at 0 so merely instantiating doesn't grab input.
    self.ui = WebUI(self.name, self.page, 0)
    local me = self
    -- ONE persistent handler resolves whichever request is currently pending (no per-call handler stacking).
    pcall(function()
        me.ui:RegisterEventHandler(self.respEvent, function(data)
            local p = me.pending; me.pending = nil
            if p then p.result = data; p.done = true end
        end)
    end)
    return self.ui
end

-- show + AWAIT one response. Returns the page's response payload (table) or nil. Must run in a thread.
function Dialog:request(showEvent, showData)
    local ui = self:ensure()
    if not ui then return nil end                       -- no WebUI (server state) — surfaced no-op
    -- supersede any stale pending request (e.g. a previous dialog never answered)
    if self.pending then self.pending.done = true end
    local p = { done = false, result = nil }
    self.pending = p
    if ui.SetInputMode then pcall(function() ui:SetInputMode(1) end) end   -- capture cursor for the dialog
    ui:SendEvent(showEvent, showData or {})
    if type(Wait) == "function" then
        while not p.done do Wait(20) end
    else
        -- no scheduler present (shouldn't happen in a converted consumer) — fail safe, don't hang
        p.done = true
    end
    if ui.SetInputMode then pcall(function() ui:SetInputMode(0) end) end   -- release control
    return p.result
end

-- fire-and-forget (e.g. external close/hide)
function Dialog:send(ev, data)
    if self.ui then pcall(function() self.ui:SendEvent(ev, data or {}) end) end
end

-- Bundled model has no require(): expose on `lib` so dialog modules loaded after this file can grab it
-- (all same-side files share one package state, so `lib._Dialog` is visible). Load _dialog BEFORE the dialogs.
lib._Dialog = Dialog
return Dialog
