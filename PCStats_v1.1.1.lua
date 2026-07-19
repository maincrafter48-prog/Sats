script_name("PC Stats")
script_description("Statistika personazha | Arizona PC | by Marco_Santiago (PC port)")
script_author("Marco_Santiago")
script_version("1.1.1")

pcall(require, 'lib.moonloader')
local _encoding = require('encoding')
if _encoding then _encoding.default = 'CP1251' end
local _u8_raw = _encoding and _encoding.UTF8 or function(s) return s end
local u8 = setmetatable({}, {
    __call  = function(_, s)
        if s == nil then return '' end
        if type(s) ~= 'string' then s = tostring(s) end
        local ok, result = pcall(_u8_raw, s)
        return ok and result or s
    end,
    __index = _u8_raw,
})

local function safeRequire(name)
    local ok, lib = pcall(require, name)
    if not ok then return nil end
    return lib
end

local sampev = safeRequire("lib.samp.events")
local imgui  = safeRequire("mimgui")
local inicfg = safeRequire("inicfg")

-- ŠµŃ�Š»Šø inicfg Š½Šµ Š·Š°Š³Ń€Ń�Š·ŠøŠ»Ń�Ń¸ ā€” Š·Š°Š³Š»Ń�Ń�ŠŗŠ° Ń‡Ń‚Š¾Š±Ń‹ Š½Šµ ŠŗŃ€Š°Ń�Š½Ń�Ń‚Ń�
if not inicfg then
    inicfg = {
        load = function() return nil end,
        save = function() end,
    }
end

if not imgui then
    function main()
        repeat wait(0) until isSampAvailable()
        wait(2000)
        sampAddChatMessage("{FF4444}[Stats] ERROR: mimgui not found!", -1)
    end
    return
end
if not sampev then
    function main()
        repeat wait(0) until isSampAvailable()
        wait(2000)
        sampAddChatMessage("{FF4444}[Stats] ERROR: lib.samp.events not found!", -1)
    end
    return
end

-- ============================================================
--  Š�Š˛Š¯Š¤Š�Š“
-- ============================================================
local CFG_FILE = "moonloader/config/PCStats.ini"
local cfg = {
    theme        = 1,
    autoRefresh  = false,
    autoInterval = 30,
    winWPct      = 0.0,
    winHPct      = 0.0,
    -- ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Šµ Ń†Š²ŠµŃ‚Š° Š°ŠŗŃ†ŠµŠ½Ń‚Š° (R,G,B 0..1)
    custR = -1, custG = -1, custB = -1,
    -- ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ (R,G,B 0..1, -1 = Š°Š²Ń‚Š¾ Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°)
    rowBgR  = -1, rowBgG = -1, rowBgB = -1,
    -- Š¼Š°Ń�Ń�Ń‚Š°Š± Ń�Ń€ŠøŃ„Ń‚Š° (0.7 .. 2.0, default 1.0)
    fontSize = 1.25,
    -- ŠŗŃ�Ń€Ń�Ń‹ Š¾Š±Š¼ŠµŠ½Š° Š²Š°Š»Ń�Ń‚ Š² SA$ Š·Š° 1 ŠµŠ´. (Š´Š»Ń¸ Š²ŠŗŠ»Š°Š´ŠŗŠø "Š’Ń�ŠµŠ³Š¾")
    rateAZ  = 35000.0,
    rateBTC = 0.0,
    rateEUR = 0.0,
    rateVC  = 1.0,
    -- ASC ne chitaetsya avtomaticheski iz staty servera, kolichestvo vvoditsya vruchnuyu
    ascAmount = 0.0,
    rateASC   = 112.0,
    -- imya servera Arizona RP dlya avtoobnovleniya kursov s arz-wiki.com (sm. fetchArzWikiRates)
    vcServerName = "Tucson",
    -- opredelyat' server avtomaticheski (po hostname/IP tekushchego SAMP-servera),
    -- a ne vvodit' vruchnuyu
    vcAutoDetectServer = true,
    -- pryatat rodnoe okno /stats servera poka skript schitivaet dannye (chtoby ne migalo)
    hideNativeStats = true,
    -- vkladka "Finansy": dvuhkolonochnyy rezhim (nalichnye/bank/depozit/scheta slева, valyuty справа)
    financeTwoCol = false,
    -- serializovannye kastomnye cveta otdelnyh tekstov/cifr (id=r,g,b;id=r,g,b;...)
    customColorsStr = "",
    -- vkladka "Finansy": kakie kategorii uchityvat v obschem itoge "Vsego virtov"
    incCash = true, incBank = true, incDep = true, incAcc = true,
    incAZ = true, incBTC = true, incEUR = true, incVC = true, incASC = true,
    -- globalnyy cvet cifr/znacheniy (perekryvaet avtocvet, no ne perekryvaet individualnyy klik-cvet)
    globalNumColorOn = false,
    globalNumR = -1, globalNumG = -1, globalNumB = -1,
    -- komanda otkrytiya telefona v igre (kursy valyut teper chitayutsya iz nego, bez CEF)
    phoneOpenCmd  = "/phone",
    phoneDebugLog = false,
}

-- kastomnye cveta konkretnyh tekstovyh elementov (klikom po tekstu/cifram),
-- id -> {r,g,b}; zapolnyaetsya iz cfg.customColorsStr pri zagruzke
local customColors = {}

local function serializeCustomColors()
    local parts = {}
    for id, c in pairs(customColors) do
        table.insert(parts, id.."="..string.format("%.3f,%.3f,%.3f", c[1], c[2], c[3]))
    end
    return table.concat(parts, ";")
end

local function deserializeCustomColors(s)
    customColors = {}
    if not s or s == "" then return end
    for id, rgb in tostring(s):gmatch("([^=;]+)=([^;]+)") do
        local rr,gg,bb = rgb:match("([%d%.]+),([%d%.]+),([%d%.]+)")
        if rr then customColors[id] = {tonumber(rr), tonumber(gg), tonumber(bb)} end
    end
end

local function loadCfg()
    local ok, data = pcall(function() return inicfg.load(CFG_FILE) end)
    if ok and data and data.main then
        cfg.theme        = tonumber(data.main.theme) or 1
        cfg.autoRefresh  = data.main.autoRefresh == "true"
        cfg.autoInterval = tonumber(data.main.autoInterval) or 30
        cfg.winWPct      = tonumber(data.main.winWPct) or 0.0
        cfg.winHPct      = tonumber(data.main.winHPct) or 0.0
        cfg.custR        = tonumber(data.main.custR) or -1
        cfg.custG        = tonumber(data.main.custG) or -1
        cfg.custB        = tonumber(data.main.custB) or -1
        cfg.rowBgR        = tonumber(data.main.rowBgR) or -1
        cfg.rowBgG        = tonumber(data.main.rowBgG) or -1
        cfg.rowBgB        = tonumber(data.main.rowBgB) or -1
        cfg.fontSize      = tonumber(data.main.fontSize) or 1.25
        cfg.rateAZ        = tonumber(data.main.rateAZ) or 35000.0
        cfg.rateBTC       = tonumber(data.main.rateBTC) or 0.0
        cfg.rateEUR       = tonumber(data.main.rateEUR) or 0.0
        cfg.rateVC        = tonumber(data.main.rateVC) or 1.0
        cfg.ascAmount     = tonumber(data.main.ascAmount) or 0.0
        cfg.rateASC       = tonumber(data.main.rateASC) or 112.0
        cfg.vcServerName  = (data.main.vcServerName and data.main.vcServerName ~= "") and data.main.vcServerName or "Tucson"
        cfg.vcAutoDetectServer = (data.main.vcAutoDetectServer ~= "false")
        if data.main.hideNativeStats == nil then
            cfg.hideNativeStats = true
        else
            cfg.hideNativeStats = data.main.hideNativeStats == "true"
        end
        cfg.financeTwoCol   = data.main.financeTwoCol == "true"
        if data.main.incCash == nil then cfg.incCash = true else cfg.incCash = data.main.incCash == "true" end
        if data.main.incBank == nil then cfg.incBank = true else cfg.incBank = data.main.incBank == "true" end
        if data.main.incDep  == nil then cfg.incDep  = true else cfg.incDep  = data.main.incDep  == "true" end
        if data.main.incAcc  == nil then cfg.incAcc  = true else cfg.incAcc  = data.main.incAcc  == "true" end
        if data.main.incAZ   == nil then cfg.incAZ   = true else cfg.incAZ   = data.main.incAZ   == "true" end
        if data.main.incBTC  == nil then cfg.incBTC  = true else cfg.incBTC  = data.main.incBTC  == "true" end
        if data.main.incEUR  == nil then cfg.incEUR  = true else cfg.incEUR  = data.main.incEUR  == "true" end
        if data.main.incVC   == nil then cfg.incVC   = true else cfg.incVC   = data.main.incVC   == "true" end
        if data.main.incASC  == nil then cfg.incASC  = true else cfg.incASC  = data.main.incASC  == "true" end
        cfg.globalNumColorOn = data.main.globalNumColorOn == "true"
        cfg.globalNumR = tonumber(data.main.globalNumR) or -1
        cfg.globalNumG = tonumber(data.main.globalNumG) or -1
        cfg.globalNumB = tonumber(data.main.globalNumB) or -1
        cfg.customColorsStr = data.main.customColorsStr or ""
        deserializeCustomColors(cfg.customColorsStr)
        cfg.phoneOpenCmd  = (data.main.phoneOpenCmd and data.main.phoneOpenCmd ~= "") and data.main.phoneOpenCmd or "/phone"
        cfg.phoneDebugLog = data.main.phoneDebugLog == "true"
    end
end

local function saveCfg()
    cfg.customColorsStr = serializeCustomColors()
    pcall(function()
        inicfg.save({main={
            theme        = tostring(cfg.theme),
            autoRefresh  = tostring(cfg.autoRefresh),
            autoInterval = tostring(cfg.autoInterval),
            winWPct      = tostring(cfg.winWPct),
            winHPct      = tostring(cfg.winHPct),
            custR        = tostring(cfg.custR),
            custG        = tostring(cfg.custG),
            custB        = tostring(cfg.custB),
            rowBgR        = tostring(cfg.rowBgR),
            rowBgG        = tostring(cfg.rowBgG),
            rowBgB        = tostring(cfg.rowBgB),
            fontSize      = tostring(cfg.fontSize),
            rateAZ        = tostring(cfg.rateAZ),
            rateBTC       = tostring(cfg.rateBTC),
            rateEUR       = tostring(cfg.rateEUR),
            rateVC        = tostring(cfg.rateVC),
            ascAmount     = tostring(cfg.ascAmount),
            rateASC       = tostring(cfg.rateASC),
            vcServerName  = tostring(cfg.vcServerName or "Tucson"),
            vcAutoDetectServer = tostring(cfg.vcAutoDetectServer),
            hideNativeStats = tostring(cfg.hideNativeStats),
            financeTwoCol   = tostring(cfg.financeTwoCol),
            incCash = tostring(cfg.incCash), incBank = tostring(cfg.incBank),
            incDep  = tostring(cfg.incDep),  incAcc  = tostring(cfg.incAcc),
            incAZ   = tostring(cfg.incAZ),   incBTC  = tostring(cfg.incBTC),
            incEUR  = tostring(cfg.incEUR),  incVC   = tostring(cfg.incVC),
            incASC  = tostring(cfg.incASC),
            globalNumColorOn = tostring(cfg.globalNumColorOn),
            globalNumR = tostring(cfg.globalNumR),
            globalNumG = tostring(cfg.globalNumG),
            globalNumB = tostring(cfg.globalNumB),
            phoneOpenCmd  = tostring(cfg.phoneOpenCmd or "/phone"),
            phoneDebugLog = tostring(cfg.phoneDebugLog),
            customColorsStr = cfg.customColorsStr,
        }}, CFG_FILE)
    end)
end

-- ============================================================
--  Š¢Š•Š�Š«
-- ============================================================
local THEMES = {
    {name="Night",  bg={0.00,0.00,0.00}, acc={0.43,0.71,1.0},  tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Forest", bg={0.00,0.00,0.00}, acc={0.30,0.85,0.45}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Sunset", bg={0.00,0.00,0.00}, acc={1.0, 0.55,0.20}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Purple", bg={0.00,0.00,0.00}, acc={0.75,0.45,1.0},  tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Gold",   bg={0.00,0.00,0.00}, acc={1.0, 0.80,0.25}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
    {name="Blood",  bg={0.00,0.00,0.00}, acc={1.0, 0.25,0.25}, tile={0.00,0.00,0.00}, txt={1.0, 1.0, 1.0}},
}
local function getTheme() return THEMES[cfg.theme] or THEMES[1] end

-- Š�Š¾Š»Ń�Ń‡ŠøŃ‚Ń� Š°ŠŗŃ†ŠµŠ½Ń‚Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ (ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ ŠøŠ»Šø ŠøŠ· Ń‚ŠµŠ¼Ń‹)
local function getAcc()
    if cfg.custR >= 0 then return cfg.custR, cfg.custG, cfg.custB end
    local t = getTheme(); local a = t.acc
    return a[1], a[2], a[3]
end

-- ============================================================
--  Š¦Š’Š•Š¢Š�
-- ============================================================
local function iv4(r,g,b,a) return imgui.ImVec4(r,g,b,a or 1.0) end
local function thBg()    local t=getTheme(); return iv4(t.bg[1],t.bg[2],t.bg[3],1.0) end
local function thAcc()   local r,g,b=getAcc(); return iv4(r,g,b,1.0) end
local function thTxt()   local t=getTheme(); return iv4(t.txt[1],t.txt[2],t.txt[3],1.0) end
local function thDim()   return iv4(0.85,0.87,0.95,1.0) end
local function thSep()   local r,g,b=getAcc(); return iv4(r*0.30,g*0.30,b*0.30,0.7) end
local function thGreen() return iv4(0.25,0.92,0.48,1.0) end
local function thGold()  return iv4(1.0, 0.82,0.20,1.0) end
local function thRed()   return iv4(1.0, 0.30,0.30,1.0) end
local function thAccBright()
    local r,g,b=getAcc()
    return iv4(math.min(1,r*1.15),math.min(1,g*1.15),math.min(1,b*1.15))
end

-- Š�Š¾Š»Ń�Ń‡ŠøŃ‚Ń� Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ dataRow (R,G,B)
local function getRowBgColor()
    if cfg.rowBgR >= 0 then
        return cfg.rowBgR, cfg.rowBgG, cfg.rowBgB
    end
    local r,g,b = getAcc()
    return r, g, b
end
-- Š�Š¾Š²Š¼ŠµŃ�Ń‚ŠøŠ¼Š¾Ń�Ń‚Ń�: alpha Š¾Š±Š²Š¾Š´ŠŗŠø Ń‚ŠµŠŗŃ�Ń‚Š° (Š´Š»Ń¸ Š¼ŠµŃ�Ń‚ Š³Š´Šµ Š½Ń�Š¶Š½Š¾ Š¾Š´Š½Š¾ Ń‡ŠøŃ�Š»Š¾)
local function getTextBorderA()
    return 0.85
end

-- ============================================================
--  AUTO UI SCALE (masshtabirovanie pod razreshenie ekrana)
-- ============================================================
local UI_SCALE      = 1.0   -- pereschityvaetsya kazhdyi kadr po DisplaySize
local UI_SCALE_MIN  = 0.88
local UI_SCALE_MAX  = 1.65
local _lastSw, _lastSh = 0, 0  -- poslednie izvestnye razmery ekrana (detekt smeny razresheniya)

local function S(n)
    return math.floor(n * UI_SCALE + 0.5)
end
local function Sf(n)
    return n * UI_SCALE
end
-- kak S(), no dopolnitelno uchityvaet polzovatelskiy razmer shrifta (cfg.fontSize),
-- nuzhen dlya blokov s zharestko zadannymi otstupami mezhdu strokami teksta
-- (vkladka "O skripte"), gde pri uvelichenii shrifta stroki nachinali nalezat
-- drug na druga i obrezalis ramkoy kartochki
local function SFtext(n)
    local fs = (cfg.fontSize and cfg.fontSize > 0) and cfg.fontSize or 1.25
    return math.floor(n * UI_SCALE * fs + 0.5)
end

-- ============================================================
--  Š�Š˛Š�Š¢Š˛ŠÆŠ¯Š�Š•
-- ============================================================
local winOpen        = false
local activeTab      = 1
local waitingStats   = false
local captureStarted = false
local TD_DELAY       = 0.8
local REQ_TIMEOUT    = 7.0
local lastReqTime    = 0.0
local lastTdTime     = 0.0
local tdCollector    = {}
local tdCollectorSize = 0
local statsData      = nil
local statusMsg      = ""
local lastAutoTime   = 0.0
local finalizing     = false
_sw_win_init         = nil
local accExpanded    = false
local accPopupOpen   = false
local _accBtnScreenPos = nil  -- ŠæŠ¾Š·ŠøŃ†ŠøŃ¸ ŠŗŠ½Š¾ŠæŠŗŠø Ń�Ń‡ŠµŃ‚Š¾Š² Š² Ń�Š°ŠæŠŗŠµ
-- Š¯Š° Š�Š� Ń�ŠŗŃ€Š¾Š»Š» Š½Š°Ń‚ŠøŠ²Š½Ń‹Š¹ (ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø), Ń€Ń�Ń‡Š½Š¾Šµ Š¾Ń‚Ń�Š»ŠµŠ¶ŠøŠ²Š°Š½ŠøŠµ
-- ŠæŠ¾Š·ŠøŃ†ŠøŠø Ń�ŠŗŃ€Š¾Š»Š»Š° Šø Š²ŠøŃ€Ń‚Ń�Š°Š»Ń�Š½Ń‹Šµ Š´Š¶Š¾Š¹Ń�Ń‚ŠøŠŗŠø (Š½Ń�Š¶Š½Ń‹Šµ Š½Š° Ń‚Š°Ń‡Ń�ŠŗŃ€ŠøŠ½Šµ) Š±Š¾Š»Ń�Ń�Šµ Š½Šµ Š½Ń�Š¶Š½Ń‹.
-- Š•Š´ŠøŠ½Ń�Ń‚Š²ŠµŠ½Š½Š¾Šµ, Ń‡Ń‚Š¾ Š½Ń�Š¶Š½Š¾ Ń�Š¾Ń…Ń€Š°Š½ŠøŃ‚Ń� ā€” Ń�Š±Ń€Š¾Ń� Ń�ŠŗŃ€Š¾Š»Š»Š° Š² 0 ŠæŃ€Šø Ń�Š¼ŠµŠ½Šµ Š²ŠŗŠ»Š°Š´ŠŗŠø.
local _resetCharScroll = false
local _resetSettScroll = false

-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Ń€Ń�Ń‡Š½Š¾Š³Š¾ Š²Š²Š¾Š´Š° RGB Š² Š½Š°Ń�Ń‚Ń€Š¾Š¹ŠŗŠ°Ń…
local custRbuf = imgui.new.float(1.0)
local custGbuf = imgui.new.float(0.5)
local custBbuf = imgui.new.float(0.2)

-- Š±Ń�Ń„ŠµŃ€Ń‹ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ (R,G,B)
local _custPickerVec  = nil
local _rowBgPickerVec = nil
local rowBgRbuf = imgui.new.float(0.43)
local rowBgGbuf = imgui.new.float(0.71)
local rowBgBbuf = imgui.new.float(1.0)

-- bufery dlya globalnogo cveta cifr + sostoyanie razvorota paneli v Nastroykah
local globalNumRbuf   = imgui.new.float(1.0)
local globalNumGbuf   = imgui.new.float(1.0)
local globalNumBbuf   = imgui.new.float(1.0)
local globalNumOnBuf  = imgui.new.bool(false)
local _globalNumColorExpanded = false

-- ============================================================
--  Š£Š¢Š�Š›Š�Š¢Š«
-- ============================================================
-- Š�ŠµŃ�ŠøŃ€Ń�ŠµŠ¼ socket Š¾Š´ŠøŠ½ Ń€Š°Š· ŠæŃ€Šø Ń�Ń‚Š°Ń€Ń‚Šµ, Š½Šµ Š²Ń‹Š·Ń‹Š²Š°ŠµŠ¼ require ŠŗŠ°Š¶Š´Ń‹Š¹ Ń‚ŠøŠŗ
local _socket_gettime = nil
do
    local ok, sock = pcall(require, "socket")
    if ok and sock and sock.gettime then
        _socket_gettime = sock.gettime
    end
end
local function getTime()
    if _socket_gettime then return _socket_gettime() end
    return os.clock()
end
local function now() return getTime() end
local function trim(s) return (tostring(s or "")):match("^%s*(.-)%s*$") end

local function stripColor(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("{%x%x%x%x%x%x}", "")
    s = s:gsub("{%x%x%x%x%x%x%x%x}", "")
    s = s:gsub("{#[%x%d]+}", "")
    s = s:gsub("~[rgbypwsh]~", "")
    s = s:gsub("~n~", "\n")
    return s
end

local function stripBrackets(s)
    s = trim(s or "")
    if s:match("^%b[]$") then s=s:sub(2,-2) end
    return s
end

local function vOrDash(v)
    v = trim(stripBrackets(v or ""))
    return v ~= "" and v or "-"
end

local function hasVal(v)
    return trim(stripBrackets(v or "")) ~= ""
end

local function fmtDots(s)
    -- s Ń�Š¶Šµ Š´Š¾Š»Š¶Š½Š° Ń�Š¾Š´ŠµŃ€Š¶Š°Ń‚Ń� Ń‚Š¾Š»Ń�ŠŗŠ¾ Ń†ŠøŃ„Ń€Ń‹
    s = tostring(s or ""):gsub("%D","")
    if s=="" then return "0" end
    if #s<4 then return s end
    -- Š Š°Š·Š±ŠøŠ²Š°ŠµŠ¼ Ń�ŠæŃ€Š°Š²Š° Š³Ń€Ń�ŠæŠæŠ°Š¼Šø ŠæŠ¾ 3:
    -- reverse -> Š²Ń�Ń‚Š°Š²ŠøŃ‚Ń� Ń‚Š¾Ń‡ŠŗŃ� Š�Š˛Š�Š›Š• ŠŗŠ°Š¶Š´Ń‹Ń… 3 Ń†ŠøŃ„Ń€ -> reverse -> Ń�Š±Ń€Š°Ń‚Ń� Š½Š°Ń‡Š°Š»Ń�Š½Ń�Ńˇ Ń‚Š¾Ń‡ŠŗŃ� ŠµŃ�Š»Šø ŠµŃ�Ń‚Ń�
    local rev = s:reverse()
    local out = rev:gsub("(%d%d%d)", "%1.")
    -- Ń�Š±ŠøŃ€Š°ŠµŠ¼ Ń‚Š¾Ń‡ŠŗŃ� Š² ŠŗŠ¾Š½Ń†Šµ (Š¾Š½Š° Ń�Ń‚Š°Š»Š° Š±Ń‹ Š² Š½Š°Ń‡Š°Š»Šµ ŠæŠ¾Ń�Š»Šµ reverse)
    if out:sub(-1)=="." then out = out:sub(1,-2) end
    local result = out:reverse()
    -- Ń�Š±ŠøŃ€Š°ŠµŠ¼ Ń‚Š¾Ń‡ŠŗŃ� Š² Š½Š°Ń‡Š°Š»Šµ ŠµŃ�Š»Šø Š²Š´Ń€Ń�Š³ Š¾Ń�Ń‚Š°Š»Š°Ń�Ń�
    if result:sub(1,1)=="." then result = result:sub(2) end
    return result
end

local function fmtMoney(v)
    if v == nil then return "-" end
    local s = trim(stripBrackets(tostring(v)))
    if s=="" or s=="-" then return "-" end
    local neg = s:match("^%-")
    -- Š•Ń�Š»Šø Ń�Ń‚Ń€Š¾ŠŗŠ° Ń�Š¾Š´ŠµŃ€Š¶ŠøŃ‚ 'e' ŠøŠ»Šø 'E' ā€” Ń¨Ń‚Š¾ Š½Š°Ń�Ń‡Š½Š°Ń¸ Š½Š¾Ń‚Š°Ń†ŠøŃ¸, ŠŗŠ¾Š½Š²ŠµŃ€Ń‚ŠøŃ€Ń�ŠµŠ¼ Ń‡ŠµŃ€ŠµŠ· tonumber
    if s:find("[eE]") then
        local n = tonumber(s)
        if n then s = string.format("%.0f", math.abs(n))
        else s = "0" end
    else
        -- Š£Š±ŠøŃ€Š°ŠµŠ¼ Š²Ń�Ń‘ Š½ŠµŃ†ŠøŃ„Ń€Š¾Š²Š¾Šµ (Ń‚Š¾Ń‡ŠŗŠø, ŠæŃ€Š¾Š±ŠµŠ»Ń‹, Š·Š½Š°ŠŗŠø ā€” Ń€Š°Š·Š´ŠµŠ»ŠøŃ‚ŠµŠ»Šø Ń�Š¶Šµ Ń�Ń‚Š¾Ń¸Ń‚ ŠøŠ»Šø Š½ŠµŃ‚)
        s = s:gsub("%D","")
    end
    if s=="" or s=="0" then return "$0" end
    return (neg and "-$" or "$") .. fmtDots(s)
end

-- Vytaskivaet chislo (s drobnoy chastyu) iz stroki staty (dlya konvertacii valyut)
-- ponimaet sokrascheniya tipa "54kkk"/"54\xea\xea\xea"/"1.5m"/"2kk" (k/\xea=tys., kk/\xea\xea/m=mln, kkk/\xea\xea\xea/b=mlrd)
local function toNum(v)
    if v == nil then return 0 end
    local s = trim(stripBrackets(tostring(v)))
    if s == "" then return 0 end
    local neg = s:match("^%-") ~= nil
    s = s:gsub(",", ".")
    local numPart, suf = s:match("^([%d%.]+)%s*([%a\xe0-\xff]*)$")
    if numPart and suf and suf ~= "" then
        local lsuf = suf:lower()
        local mult = nil
        if lsuf:find("^kkk") or lsuf:find("^\xea\xea\xea") or lsuf == "b" then
            mult = 1e9
        elseif lsuf:find("^kk") or lsuf:find("^\xea\xea") or lsuf == "m" then
            mult = 1e6
        elseif lsuf:find("^k") or lsuf:find("^\xea") then
            mult = 1e3
        end
        if mult then
            local n2 = tonumber(numPart)
            if n2 then
                if neg then n2 = -n2 end
                return n2 * mult
            end
        end
    end
    s = s:gsub("[^%d%.]", "")
    -- ГЛАВНОЕ ИСПРАВЛЕНИЕ: раньше при нескольких точках последняя группа
    -- из 3 цифр ошибочно принималась за дробную часть и "съедалась" —
    -- из-за этого суммы вида 45.000.000.000 показывались как 45.000.000.
    -- Теперь: если последний сегмент после точки состоит РОВНО из 3 цифр
    -- (типичный признак разделителя тысяч) — все точки считаются
    -- разделителями тысяч. Иначе последняя точка — это десятичный разделитель
    -- (например "103.78" AZ или "572.53" VC$), а более ранние точки (если
    -- есть) — разделители тысяч.
    if s:find("%.") then
        local segs = {}
        for part in (s.."."):gmatch("([^%.]*)%.") do segs[#segs+1] = part end
        local lastSeg = segs[#segs]
        if lastSeg and #lastSeg == 3 and #segs >= 2 then
            s = table.concat(segs)
        else
            local intSegs = {}
            for i=1,#segs-1 do intSegs[#intSegs+1] = segs[i] end
            s = table.concat(intSegs) .. "." .. (lastSeg or "")
        end
    end
    local n = tonumber(s) or 0
    if neg then n = -n end
    return n
end

local function fmtInt(n)
    n = tonumber(n) or 0
    local neg = n < 0
    local s = fmtDots(string.format("%.0f", math.abs(n)))
    return (neg and "-" or "") .. s
end

-- Š¡Ń�Š¼Š¼Š° Š²Š°Š»Ń�Ń‚Ń‹: Ń†ŠµŠ»Š¾Šµ ŠµŃ�Š»Šø Š±ŠµŠ· Š´Ń€Š¾Š±Š½Š¾Š¹ Ń‡Š°Ń�Ń‚Šø, ŠøŠ½Š°Ń‡Šµ 2 Š·Š½Š°ŠŗŠ° ŠæŠ¾Ń�Š»Šµ Š·Š°ŠæŃ¸Ń‚Š¾Š¹
local function fmtAmt(n)
    n = tonumber(n) or 0
    if math.abs(n - math.floor(n+0.5)) < 0.001 then
        return fmtInt(math.floor(n+0.5))
    else
        return string.format("%.2f", n)
    end
end

local function looksTexture(t)
    if t == nil then return true end
    local s = tostring(t)
    return s == "" or s == " " or s == "null"
        or s:find("LD_", 1, true) or s:find("ld_", 1, true)
        or s:find(".txd", 1, true) or s:find(".saa", 1, true)
        or s:find("preview", 1, true)
end

local function isStatsPiece(t)
    local s = stripColor(t or "")
    return s:find("\xce\xf1\xed\xee\xe2\xed\xe0\xff \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe0",1,true)
        or s:find("\xcd\xee\xec\xe5\xf0 \xe0\xea\xea\xe0\xf3\xed\xf2\xe0",1,true)
        or s:find("\xc8\xec\xff:",1,true)
        or s:find("\xcf\xee\xeb:",1,true)
        or s:find("\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5:",1,true)
        or s:find("\xd3\xf0\xee\xe2\xe5\xed\xfc:",1,true)
        or s:find("\xd0\xe0\xe1\xee\xf2\xe0:",1,true)
        or s:find("AZ%-Coins",1,true)
        or s:find("\xc7\xe0\xf9\xe8\xf2\xe0:",1,true)
        or s:find("\xd3\xe4\xe0\xf7\xe0:",1,true)
end

-- ============================================================
--  Š�Š�Š Š�Š•Š 
-- ============================================================
local function parseStats(raw)
    local p = {
        accountNumber="",authDate="",accountState="",
        x3Payday="",x4Payday="",
        name="",gender="",health="",level="",respect="",
        cashSas="",cashVcs="",euro="",btc="",azCoins="",
        phone="",bank="",moneyDay="",bankCard="",
        acc={},
        job="",org="",position="",status="",citizenship="",family="",
        wanted="",lawfulness="",warnings="",addiction="",
        protection="",regen="",damage="",luck="",
        maxHp="",maxArmor="",stunChance="",bleedChance="",
        dodgeChance="",reflectDamage="",blockDamage="",
        fireRate="",recoil="",fruitStun="",
        hotel="",hotelRoom="",trailer="",
        extra={}
    }
    for line in (raw.."\n"):gmatch("([^\n]*)\n") do
        local cl = trim(stripColor(line))
        if cl and cl ~= "" then
            local k,v = cl:match("^(.-):%s*(.+)$")
            if k and v then
                k=trim(k); v=trim(v)
                local ai = k:match("^\xd1\xee\xf1\xf2\xee\xff\xed\xe8\xe5 \xeb\xe8\xf7\xed\xee\xe3\xee \xf1\xf7\xe5\xf2[\xe0\xb8]%s*\xb9%s*(%d+)$")
                if ai then p.acc[tonumber(ai)] = v
                elseif cl:find("PayDay",1,true) or cl:find("PAYDAY",1,true) then
                    local s2 = cl:lower():gsub("[\xd7\xd5\xf5]","x"):gsub("%s","")
                    if s2:find("x4") or s2:find("4x") then p.x4Payday=v
                    elseif s2:find("x3") or s2:find("3x") then p.x3Payday=v end
                elseif k:find("\xcd\xee\xec\xe5\xf0 \xe0\xea\xea\xe0\xf3\xed\xf2\xe0",1,true) then p.accountNumber=v
                elseif k:find("\xc0\xe2\xf2\xee\xf0\xe8\xe7\xe0\xf6\xe8\xff",1,true) then p.authDate=v
                elseif k:find("\xd2\xe5\xea\xf3\xf9\xe5\xe5 \xf1\xee\xf1\xf2\xee\xff\xed\xe8\xe5",1,true) then p.accountState=v
                elseif k=="\xc8\xec\xff" then p.name=v
                elseif k=="\xcf\xee\xeb" then p.gender=v
                elseif k=="\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5" then p.health=v
                elseif k=="\xd3\xf0\xee\xe2\xe5\xed\xfc" then p.level=v
                elseif k=="\xd3\xe2\xe0\xe6\xe5\xed\xe8\xe5" then p.respect=v
                elseif k:find("\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xe4\xe5\xed\xfc\xe3\xe8 %(SA%$%)") then p.cashSas=v
                elseif k:find("\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xe4\xe5\xed\xfc\xe3\xe8 %(VC%$%)") then p.cashVcs=v
                elseif k=="\xc5\xe2\xf0\xee" then p.euro=v
                elseif k=="BTC" then p.btc=v
                elseif k:find("AZ",1,true) and k:find("oin",1,true) then p.azCoins=v
                elseif k=="\xcd\xee\xec\xe5\xf0 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0" then p.phone=v
                elseif k=="\xc4\xe5\xed\xfc\xe3\xe8 \xe2 \xe1\xe0\xed\xea\xe5" then p.bank=v
                elseif k:find("\xc4\xe5\xed\xfc\xe3\xe8 \xed\xe0 \xe4\xe5\xef\xee\xe7\xe8\xf2",1,true) then p.moneyDay=v
                elseif k=="\xc1\xe0\xed\xea\xee\xe2\xf1\xea\xe0\xff \xea\xe0\xf0\xf2\xe0" then p.bankCard=v
                elseif k=="\xd0\xe0\xe1\xee\xf2\xe0" then p.job=v
                elseif k=="\xce\xf0\xe3\xe0\xed\xe8\xe7\xe0\xf6\xe8\xff" then p.org=v
                elseif k=="\xc4\xee\xeb\xe6\xed\xee\xf1\xf2\xfc" then p.position=v
                elseif k=="\xd1\xf2\xe0\xf2\xf3\xf1" then p.status=v
                elseif k=="\xc3\xf0\xe0\xe6\xe4\xe0\xed\xf1\xf2\xe2\xee" then p.citizenship=v
                elseif k=="\xd1\xe5\xec\xfc\xff" then p.family=v
                elseif k=="\xd3\xf0\xee\xe2\xe5\xed\xfc \xf0\xee\xe7\xfb\xf1\xea\xe0" then p.wanted=v
                elseif k=="\xc7\xe0\xea\xee\xed\xee\xef\xee\xf1\xeb\xf3\xf8\xed\xee\xf1\xf2\xfc" then p.lawfulness=v
                elseif k=="\xcf\xf0\xe5\xe4\xf3\xef\xf0\xe5\xe6\xe4\xe5\xed\xe8\xff" then p.warnings=v
                elseif k:find("\xc7\xe0\xe2\xe8\xf1\xe8\xec\xee\xf1\xf2\xfc",1,true) then p.addiction=v
                elseif k=="\xc7\xe0\xf9\xe8\xf2\xe0" then p.protection=v
                elseif k=="\xd0\xe5\xe3\xe5\xed\xe5\xf0\xe0\xf6\xe8\xff" then p.regen=v
                elseif k=="\xd3\xf0\xee\xed" then p.damage=v
                elseif k=="\xd3\xe4\xe0\xf7\xe0" then p.luck=v
                elseif k=="\xcc\xe0\xea\xf1. HP" then p.maxHp=v
                elseif k:find("\xcc\xe0\xea\xf1.",1,true) and k:find("\xf0\xee\xed",1,true) then p.maxArmor=v
                elseif k=="\xd8\xe0\xed\xf1 \xee\xe3\xeb\xf3\xf8\xe5\xed\xe8\xff" then p.stunChance=v
                elseif k:find("\xd8\xe0\xed\xf1 \xee\xef",1,true) then p.bleedChance=v
                elseif k:find("\xd8\xe0\xed\xf1 \xe8\xe7\xe1\xe5\xe6",1,true) then p.dodgeChance=v
                elseif k=="\xce\xf2\xf0\xe0\xe6\xe5\xed\xe8\xe5 \xf3\xf0\xee\xed\xe0" then p.reflectDamage=v
                elseif k=="\xc1\xeb\xee\xea\xe8\xf0\xee\xe2\xea\xe0 \xf3\xf0\xee\xed\xe0" then p.blockDamage=v
                elseif k=="\xd1\xea\xee\xf0\xee\xf1\xf2\xf0\xe5\xeb\xfc\xed\xee\xf1\xf2\xfc" then p.fireRate=v
                elseif k=="\xce\xf2\xea\xe0\xf2" then p.recoil=v
                elseif k:find("\xcf\xeb\xee\xe4",1,true) then p.fruitStun=v
                elseif k=="\xce\xf2\xe5\xeb\xfc" then p.hotel=v
                elseif k:find("\xca\xee\xec\xed\xe0\xf2\xe0",1,true) then p.hotelRoom=v
                elseif k=="\xd2\xf0\xe5\xe9\xeb\xe5\xf0" then p.trailer=v
                else table.insert(p.extra,{k,v}) end
            end
        end
    end
    local total=0; local found=false
    for i=1,6 do
        local v=p.acc[i]
        if v and trim(v)~="" then
            local n=tonumber((v:gsub("%D","")))
            if n then total=total+n; found=true end
        end
    end
    p.totalAcc = found and fmtMoney(string.format("%.0f", total)) or ""
    return p
end

-- ============================================================
--  Š�Š¢Š�Š›Š¬
-- ============================================================
-- Š�Ń€ŠøŠ¼ŠµŠ½Ń¸ŠµŠ¼ Ń�Ń‚ŠøŠ»Ń� Š³Š»Š¾Š±Š°Š»Ń�Š½Š¾ Ń‡ŠµŃ€ŠµŠ· GetStyle() ā€” ŠŗŠ°Šŗ MarketHelper, Š±ŠµŠ· Push/Pop Ń�Š¾Š²Ń�ŠµŠ¼
local function applyStyle()
    local s   = imgui.GetStyle()
    local r,g,b = getAcc()
    local t   = getTheme()
    local C   = s.Colors
    -- Š·Š°Š´Š½ŠøŠ¹ Ń„Š¾Š½ ā€” Ń‡Ń‘Ń€Š½Ń‹Š¹ (WindowBg ŠæŠ¾Š»Š½Š¾Ń�Ń‚Ń�Ńˇ Ń‡Ń‘Ń€Š½Ń‹Š¹)
    C[imgui.Col.WindowBg]             = iv4(0.00, 0.00, 0.00, 1.0)
    C[imgui.Col.TitleBg]              = iv4(r*0.08, g*0.08, b*0.08, 1.0)
    C[imgui.Col.TitleBgActive]        = iv4(r*0.14, g*0.14, b*0.14, 1.0)
    C[imgui.Col.ChildBg]              = iv4(0.00,   0.00,   0.00,   0.55)
    C[imgui.Col.Button]               = iv4(r*0.10, g*0.10, b*0.10, 1.0)
    C[imgui.Col.ButtonHovered]        = iv4(r*0.45, g*0.45, b*0.45, 1.0)
    C[imgui.Col.ButtonActive]         = iv4(r*0.70, g*0.70, b*0.70, 1.0)
    C[imgui.Col.ScrollbarBg]          = iv4(0, 0, 0, 0.15)
    C[imgui.Col.ScrollbarGrab]        = iv4(r*0.45, g*0.45, b*0.45, 0.70)
    C[imgui.Col.ScrollbarGrabHovered] = iv4(r*0.65, g*0.65, b*0.65, 0.85)
    C[imgui.Col.ScrollbarGrabActive]  = iv4(r,      g,      b,      1.0)
    C[imgui.Col.Separator]            = thSep()
    C[imgui.Col.Header]               = iv4(r*0.15, g*0.15, b*0.15, 1.0)
    C[imgui.Col.HeaderHovered]        = iv4(r*0.28, g*0.28, b*0.28, 1.0)
    -- Š¾Š±Š²Š¾Š´ŠŗŠ° Š¾ŠŗŠ½Š° ā€” Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°
    C[imgui.Col.Border]               = iv4(r*0.45, g*0.45, b*0.45, 0.90)
    C[imgui.Col.Text]                 = iv4(t.txt[1], t.txt[2], t.txt[3], 1.0)
    s.WindowRounding   = Sf(16.0)
    s.ChildRounding    = Sf(10.0)
    s.FrameRounding    = Sf(12.0)
    s.GrabRounding     = Sf(12.0)
    s.GrabMinSize      = Sf(14.0)
    s.ScrollbarSize    = Sf(10.0)
    s.ItemSpacing      = imgui.ImVec2(S(6), S(5))
    s.WindowPadding    = imgui.ImVec2(S(12), S(10))
    s.FramePadding     = imgui.ImVec2(S(8), S(6))
    -- Ń‚Š¾Š»Ń‰ŠøŠ½Š° Ń€Š°Š¼ŠŗŠø Š¾ŠŗŠ½Š° (Š½Šµ Š¼Š°Ń�Ń¨Ń‚Š°Š±ŠøŃ€Ń�ŠµŠ¼ Š½ŠøŠ¶Šµ 1px, ŠøŠ½Š°Ń‡Šµ ŠæŃ€Š¾ŠæŠ°Š´Š°ŠµŃ‚)
    s.WindowBorderSize = math.max(1.0, Sf(1.2))
    s.ChildBorderSize  = 0.0
end

-- ============================================================
--  UI Š�Š˛Š�Š�Š˛Š¯Š•Š¯Š¢Š«
-- ============================================================

-- Š—Š°Š³Š¾Š»Š¾Š²Š¾Šŗ Ń�ŠµŠŗŃ†ŠøŠø Ń� Š»ŠµŠ²Š¾Š¹ ŠæŠ¾Š»Š¾Ń�Š¾Š¹
local function secTitle(title)
    imgui.Spacing()
    local r,g,b = getAcc()
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(30)
    -- Ń„Š¾Š½: Š¼ŠøŠ½ŠøŠ¼Ń�Š¼ 0.10 Ń¸Ń€ŠŗŠ¾Ń�Ń‚Šø Ń‡Ń‚Š¾Š±Ń‹ Š±Ń‹Š» Š²ŠøŠ´ŠµŠ½ Š½Š° Ń‡Ń‘Ń€Š½Š¾Š¼
    local br = math.max(r*0.22, 0.10)
    local bg2 = math.max(g*0.22, 0.10)
    local bb  = math.max(b*0.22, 0.10)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(br,bg2,bb,0.97)), 5)
    -- Ń€Š°Š¼ŠŗŠ° Ń�ŠµŠŗŃ†ŠøŠø
    dl:AddRect(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.60,g*0.60,b*0.60,0.55)), 5, 0, 0.8)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+2),
        imgui.ImVec2(p.x+S(3), p.y+h-2),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
    dl:AddRectFilled(
        imgui.ImVec2(p.x+S(3),  p.y+2),
        imgui.ImVec2(p.x+S(18), p.y+h-2),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.55,g*0.55,b*0.55,0.45)), 0)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+4)
    imgui.SetCursorPosX(imgui.GetCursorPosX()+S(10))
    imgui.TextColored(thAccBright(), title)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+2)
end

-- ā–ŗ Š�Ń€Š°Ń�ŠøŠ²Š°Ń¸ ŠŗŠ°Ń€Ń‚Š¾Ń‡ŠŗŠ°-Š¾Š±Ń‘Ń€Ń‚ŠŗŠ° (Ń�ŠŗŃ€ŠøŠ½Ń�Š¾Ń‚ 3 ā€” Š²Ń�Šµ Š±Š»Š¾ŠŗŠø Ń� Ń€Š°Š¼ŠŗŠ¾Š¹)
local function infoCard(id, cardH, drawFn)
    cardH = SFtext(cardH)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local aw = imgui.GetContentRegionAvail().x
    -- Ń„Š¾Š½ ŠŗŠ°Ń€Ń‚Š¾Ń‡ŠŗŠø: ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
    local bgR = math.max(rr*0.15, 0.08)
    local bgG = math.max(rg*0.15, 0.08)
    local bgB = math.max(rb*0.15, 0.08)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- Ń€Š°Š¼ŠŗŠ° Ń� Š°ŠŗŃ†ŠµŠ½Ń‚Š½Ń‹Š¼ Ń†Š²ŠµŃ‚Š¾Š¼
    dl:AddRect(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.60,g*0.60,b*0.60,0.90)), 10, 0, 1.5)
    -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
    dl:AddRectFilled(
        imgui.ImVec2(p.x+12,    p.y),
        imgui.ImVec2(p.x+aw-12, p.y+2),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.95)), 2)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild(id, imgui.ImVec2(aw - 2, cardH), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        drawFn(aw, cardH)
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.Spacing()
end

local _rowIndex = 0

-- ============================================================
--  Š�Š›Š�Š� ŠŸŠž ŠŸŠ ŠžŠ˜Š—Š’ŠžŠ›Š¬ŠĄŠ˜ (klik po tekstu/cifram -> smena cveta)
-- ============================================================
local _colorPopupBufs = {}

-- vozvraschaet kastomnyy cvet elementa (esli zadan) libo peredannyy po umolchaniyu
local function getElemColor(id, colorDefault)
    local c = customColors[id]
    if c then
        local a = (colorDefault and colorDefault.w) or 1.0
        return iv4(c[1], c[2], c[3], a)
    end
    return colorDefault
end

-- delaet posledniy narisovannyy Text/TextColored "klikabelnym": klik levoy knopkoy
-- otkryvaet vseplyvayuschee menu s polzunkami R/G/B dlya smeny cveta imenno etogo
-- teksta ili cifr. cveta sohranyayutsya v cfg i primenyayutsya pri sleduyushchih zapuskah.
local _colorPickerVec = {}

local function recolorOnClick(id)
    if imgui.IsItemClicked and imgui.IsItemClicked() then
        imgui.OpenPopup(id)
    end
    if imgui.IsItemHovered and imgui.IsItemHovered() then
        pcall(function()
            imgui.BeginTooltip()
            imgui.TextColored(iv4(0.75,0.80,0.90,1.0),
                u8"\xed\xe0\xe6\xec\xe8\xf2\xe5, \xf7\xf2\xee\xe1\xfb \xf1\xec\xe5\xed\xe8\xf2\xfc \xf6\xe2\xe5\xf2")
            imgui.EndTooltip()
        end)
    end
    pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(300), 0), imgui.Cond and imgui.Cond.Appearing or 0)
    if imgui.BeginPopup(id) then
        local buf = _colorPopupBufs[id]
        if not buf then
            local c = customColors[id]
            buf = { imgui.new.float(c and c[1] or 1.0),
                    imgui.new.float(c and c[2] or 1.0),
                    imgui.new.float(c and c[3] or 1.0) }
            _colorPopupBufs[id] = buf
        end
        imgui.TextColored(thDim(), u8"\xd6\xe2\xe5\xf2 \xfd\xf2\xee\xe3\xee \xf2\xe5\xea\xf1\xf2\xe0/\xf6\xe8\xf4\xf0\xfb:")
        imgui.Spacing()

        local changed = false

        -- пробуем полноценный визуальный пикер (квадрат насыщенности + вертикальная
        -- полоса тона + hex-поле), как в стандартном ImGui color picker
        local okPicker = pcall(function()
            local vec = _colorPickerVec[id]
            if not vec then
                vec = imgui.new("float[3]", {buf[1][0], buf[2][0], buf[3][0]})
                _colorPickerVec[id] = vec
            end
            imgui.PushItemWidth(S(220))
            local flags = 0
            pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
            if imgui.ColorPicker3("##cp"..id, vec, flags) then
                buf[1][0], buf[2][0], buf[3][0] = vec[0], vec[1], vec[2]
                changed = true
            end
            imgui.PopItemWidth()
        end)

        if not okPicker then
            -- запасной вариант (обычные ползунки), если ColorPicker3 недоступен в этой сборке mimgui
            imgui.PushItemWidth(150)
            if imgui.SliderFloat("R##rc"..id, buf[1], 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("G##rc"..id, buf[2], 0.0, 1.0) then changed = true end
            if imgui.SliderFloat("B##rc"..id, buf[3], 0.0, 1.0) then changed = true end
            imgui.PopItemWidth()
        end

        if changed then
            customColors[id] = {buf[1][0], buf[2][0], buf[3][0]}
            saveCfg()
        end

        imgui.Spacing()
        local awPop  = imgui.GetContentRegionAvail().x
        local halfWP = (awPop - 8) * 0.5
        imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.55,0.10,0.10,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.75,0.16,0.16,1.0))
        if imgui.Button(u8"\xd1\xe1\xf0\xee\xf1 \xf6\xe2\xe5\xf2\xe0##rcreset", imgui.ImVec2(halfWP, S(28))) then
            customColors[id] = nil
            _colorPopupBufs[id] = nil
            _colorPickerVec[id] = nil
            saveCfg()
            imgui.CloseCurrentPopup()
        end
        imgui.PopStyleColor(3)
        imgui.SameLine(0, 8)
        do
            local pr,pg,pb = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
            if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##rcclose", imgui.ImVec2(halfWP, S(28))) then
                imgui.CloseCurrentPopup()
            end
            imgui.PopStyleColor(3)
        end
        imgui.EndPopup()
    end
end

-- Edinaya risovka kнopok-obraztsov stilya (aktsent sverhu / fon strok snizu),
-- ispolzuetsya i dlya "gotovyh tem", i dlya "kombo-presetov" v odnom popupe,
-- chtoby vse presety vyglyadeli odinakovo.
local function drawStyleSwatchButton(uid, label, aR,aG,aB, bR,bG,bB, btnW, bH_c, isAct, tooltipText)
    local dl_cb = imgui.GetWindowDrawList()
    local p_cb  = imgui.GetCursorScreenPos()
    local halfH = bH_c * 0.5
    local bgAlpha = isAct and 0.85 or 0.45
    dl_cb:AddRectFilled(
        imgui.ImVec2(p_cb.x,           p_cb.y),
        imgui.ImVec2(p_cb.x+btnW,      p_cb.y+halfH),
        imgui.ColorConvertFloat4ToU32(iv4(aR*0.55,aG*0.55,aB*0.55,bgAlpha)), 0)
    dl_cb:AddRectFilled(
        imgui.ImVec2(p_cb.x,           p_cb.y+halfH),
        imgui.ImVec2(p_cb.x+btnW,      p_cb.y+bH_c),
        imgui.ColorConvertFloat4ToU32(iv4(bR*0.55,bG*0.55,bB*0.55,bgAlpha)), 0)
    local borderCol = isAct and iv4(aR,aG,aB,1.0) or iv4(aR*0.65,aG*0.65,aB*0.65,0.70)
    dl_cb:AddRect(
        imgui.ImVec2(p_cb.x,       p_cb.y),
        imgui.ImVec2(p_cb.x+btnW,  p_cb.y+bH_c),
        imgui.ColorConvertFloat4ToU32(borderCol), 8, 0, isAct and 2.0 or 1.0)
    dl_cb:AddLine(
        imgui.ImVec2(p_cb.x+4,      p_cb.y+halfH),
        imgui.ImVec2(p_cb.x+btnW-4, p_cb.y+halfH),
        imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.12)), 1)
    imgui.PushStyleColor(imgui.Col.Button,        iv4(0,0,0,0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(aR*0.20,aG*0.20,aB*0.20,0.50))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(aR*0.40,aG*0.40,aB*0.40,0.80))
    local clicked = imgui.Button(label.."##"..uid, imgui.ImVec2(btnW, bH_c))
    if imgui.IsItemHovered() and tooltipText then
        imgui.BeginTooltip()
        imgui.Text(tooltipText)
        imgui.EndTooltip()
    end
    imgui.PopStyleColor(3)
    return clicked
end

-- esli v Nastroykah vklyuchen globalnyy cvet cifr -- primenyaet ego poverh
-- avto/temnovogo cveta (no individualnyy klik-cvet konkretnogo elementa,
-- zadavaemyy cherez getElemColor, vse ravno v prioritete -- sm. dataRow/metricTile)
local function applyGlobalNumColor(col)
    if cfg.globalNumColorOn and cfg.globalNumR >= 0 then
        local a = (col and col.w) or 1.0
        return iv4(cfg.globalNumR, cfg.globalNumG, cfg.globalNumB, a)
    end
    return col
end

local function dataRow(label, value, valColor)
    if not hasVal(value) then return end
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(36)
    _rowIndex = _rowIndex + 1
    -- Ń„Š¾Š½ Ń�Ń‚Ń€Š¾ŠŗŠø: ŠøŃ�ŠæŠ¾Š»Ń�Š·Ń�ŠµŠ¼ ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° (rowBg) Ń� Ń‡ŠµŃ€ŠµŠ´Š¾Š²Š°Š½ŠøŠµŠ¼ Ń¸Ń€ŠŗŠ¾Ń�Ń‚Šø
    local shade = (_rowIndex % 2 == 0) and 0.13 or 0.07
    local minV  = (_rowIndex % 2 == 0) and 0.10 or 0.05
    local bgR = math.max(rr*shade, minV)
    local bgG = math.max(rg*shade, minV)
    local bgB = math.max(rb*shade, minV)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.98)), 5)
    -- Ń‚Š¾Š½ŠŗŠ°Ń¸ Ń€Š°Š¼ŠŗŠ° Ń�Ń‚Ń€Š¾ŠŗŠø Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°
    dl:AddRect(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.40)), 5, 0, 0.7)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+3),
        imgui.ImVec2(p.x+2, p.y+h-3),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.85)), 1)
    -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾ŠŗŠø ā€” ŠµŃ�Š»Šø Ń�Š²ŠµŃ‚Š»Ń‹Š¹ Ń„Š¾Š½, Š´ŠµŠ»Š°ŠµŠ¼ Ń‚ŠµŠŗŃ�Ń‚ Ń‚Ń‘Š¼Š½Ń‹Š¼
    local bgBright = bgR*0.299 + bgG*0.587 + bgB*0.114
    local labelCol = bgBright > 0.35 and iv4(0.05,0.05,0.08,1.0) or iv4(0.95,0.95,0.98,1.0)
    -- Š´Š»Ń¸ valColor Ń‚Š¾Š¶Šµ ŠæŃ€Š¾Š²ŠµŃ€Ń¸ŠµŠ¼: ŠµŃ�Š»Šø Š½Šµ Š·Š°Š´Š°Š½ Ń¸Š²Š½Š¾ ā€” Š°Š²Ń‚Š¾
    local autoValCol
    if not valColor then
        autoValCol = bgBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or thTxt()
    else
        autoValCol = valColor
    end
    autoValCol = applyGlobalNumColor(autoValCol)
    local lblId = "lbl_"..label
    local valId = "val_"..label
    labelCol   = getElemColor(lblId, labelCol)
    autoValCol = getElemColor(valId, autoValCol)
    imgui.SetCursorPosY(imgui.GetCursorPosY()+S(6))
    imgui.SetCursorPosX(imgui.GetCursorPosX()+S(10))
    imgui.TextColored(labelCol, label)
    recolorOnClick(lblId)
    local valStr  = u8(tostring(vOrDash(value) or '-'))
    local labelW  = imgui.CalcTextSize(label).x
    local valW    = imgui.CalcTextSize(valStr).x
    -- avtoumenshenie shrifta znacheniya, esli ono ne pomeshchaetsya v stroku
    -- (posle ispravleniya toNum summy mogut byt ochen bolshimi -- millirdy/trilliony)
    local baseScale = UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
    local rightPad = S(12)
    local maxValW = avail - labelW - S(24) - rightPad
    local shrink = 1.0
    if valW > maxValW and maxValW > S(10) and valW > 0 then
        shrink = maxValW / valW
        if shrink < 0.55 then shrink = 0.55 end
    end
    if shrink < 0.999 then
        pcall(imgui.SetWindowFontScale, baseScale * shrink)
        valW = valW * shrink
    end
    imgui.SameLine(avail - valW - rightPad)
    imgui.SetCursorPosY(imgui.GetCursorPosY())
    imgui.TextColored(autoValCol, valStr)
    recolorOnClick(valId)
    if shrink < 0.999 then
        pcall(imgui.SetWindowFontScale, baseScale)
    end
    imgui.SetCursorPosY(imgui.GetCursorPosY()+2)
end

local _metricTileIdx = 0
local function metricTile(label, value, col, w, onClickFn)
    _metricTileIdx = _metricTileIdx + 1
    local h  = S(56)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    -- Ń„Š¾Š½ Ń‚Š°Š¹Š»Š°
    local bgR = math.max(rr*0.18, 0.09)
    local bgG = math.max(rg*0.18, 0.09)
    local bgB = math.max(rb*0.18, 0.09)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- Ń€Š°Š¼ŠŗŠ°
    dl:AddRect(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(
            math.max(r*0.65,0.22), math.max(g*0.65,0.22), math.max(b*0.65,0.22), 0.85)),
        10, 0, 1.5)
    -- Š»ŠµŠ²Š°Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�Š°
    local ac = col or thAcc()
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+6),
        imgui.ImVec2(p.x+3, p.y+h-6),
        imgui.ColorConvertFloat4ToU32(iv4(ac.x,ac.y,ac.z,1.0)), 2)

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##mt"..tostring(_metricTileIdx), imgui.ImVec2(w, h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

        -- Š�Š½Š¾ŠæŠŗŠ° Ń�ŠæŃ€Š°Š²Š° (ŠµŃ�Š»Šø ŠµŃ�Ń‚Ń�) ā€” Ń€ŠøŃ�Ń�ŠµŠ¼ ŠæŠµŃ€Š²Š¾Š¹ Ń‡Ń‚Š¾Š±Ń‹ Š·Š½Š°Ń‚Ń� ŠµŃ‘ Ń�ŠøŃ€ŠøŠ½Ń�
        local btnW = onClickFn and S(44) or 0
        local btnH = S(32)
        if onClickFn then
            imgui.SetCursorPos(imgui.ImVec2(w - btnW - S(6), (h - btnH)*0.5))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.25,g*0.25,b*0.25,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.65,g*0.65,b*0.65,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,      g,      b,      1.0))
            do local _sv=0
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,Sf(7.0)) then _sv=_sv+1 end
            -- Ń�ŠøŠ¼Š²Š¾Š» "ŠæŠ¾Š´ŠµŠ»ŠøŃ‚Ń�Ń�Ń¸/ŠŗŠ¾ŠæŠøŃ€Š¾Š²Š°Ń‚Ń�": Ń�Ń‚Ń€ŠµŠ»ŠŗŠ° Š²Š²ŠµŃ€Ń…
            if imgui.Button(">>##cp"..tostring(_metricTileIdx),
                            imgui.ImVec2(btnW, btnH)) then
                pcall(onClickFn)
            end
            if _sv>0 then pcall(imgui.PopStyleVar,_sv) end end
            imgui.PopStyleColor(3)
        end

        -- Š›ŠµŠ¹Š±Š» (Ń�Š²ŠµŃ€Ń…Ń� Ń�Š»ŠµŠ²Š°)
        local textAreaW = w - btnW - S(14)
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(7)))
        imgui.TextColored(thDim(), label)

        -- Š—Š½Š°Ń‡ŠµŠ½ŠøŠµ (Ń�Š½ŠøŠ·Ń� Ń�Š»ŠµŠ²Š°, ŠŗŃ€Ń�ŠæŠ½ŠµŠµ)
        local valStr = u8(value~="" and value or "-")
        local mtId = "mt_"..label
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(28)))
        imgui.TextColored(getElemColor(mtId, applyGlobalNumColor(col or thTxt())), valStr)
        recolorOnClick(mtId)

    imgui.EndChild()
    imgui.PopStyleColor()
end

local _chipIdx = 0
local chipSide = false
local function chip(label, value)
    if not hasVal(value) then return end
    _chipIdx = _chipIdx + 1
    local avail = imgui.GetContentRegionAvail().x
    local w  = (avail - S(6)) * 0.5
    local h  = S(54)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local doRender = function(side)
        local p = imgui.GetCursorScreenPos()
        -- Ń„Š¾Š½ chip: ŠŗŠ°Ń�Ń‚Š¾Š¼Š½Ń‹Š¹ Ń†Š²ŠµŃ‚ Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
        local bgR = math.max(rr*0.14, 0.08)
        local bgG = math.max(rg*0.14, 0.08)
        local bgB = math.max(rb*0.14, 0.08)
        dl:AddRectFilled(
            imgui.ImVec2(p.x,   p.y),
            imgui.ImVec2(p.x+w, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 8)
        -- Ń€Š°Š¼ŠŗŠ° Š¾Ń‚ Š°ŠŗŃ†ŠµŠ½Ń‚Š°
        local brR = math.max(r*0.55, 0.20)
        local brG = math.max(g*0.55, 0.20)
        local brB = math.max(b*0.55, 0.20)
        dl:AddRect(
            imgui.ImVec2(p.x,   p.y),
            imgui.ImVec2(p.x+w, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(brR,brG,brB,0.80)), 8, 0, 1)
        dl:AddRectFilled(
            imgui.ImVec2(p.x+8,   p.y+h-2),
            imgui.ImVec2(p.x+w-8, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.70)), 2)
        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        local cid = "##chip"..tostring(_chipIdx)..(side and "R" or "L")
        imgui.BeginChild(cid, imgui.ImVec2(w,h), false)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(6)))
            imgui.TextColored(thDim(), label)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(26)))
            imgui.TextColored(thAcc(), u8(vOrDash(value)))
        imgui.EndChild()
        imgui.PopStyleColor()
    end
    if chipSide then
        imgui.SameLine(0,S(6))
        doRender(true)
        imgui.Spacing()
        chipSide = false
    else
        chipSide = true
        doRender(false)
    end
end

local function tabButton(label, active, w, r,g,b)
    local ar,ag,ab = getAcc()
    local br = r or ar; local bg2 = g or ag; local bb = b or ab
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local h  = S(38)
    if active then
        imgui.PushStyleColor(imgui.Col.Button,        iv4(br*0.22,bg2*0.22,bb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(br*0.38,bg2*0.38,bb*0.38,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(br*0.55,bg2*0.55,bb*0.55,1.0))
    else
        imgui.PushStyleColor(imgui.Col.Button,        iv4(br*0.07,bg2*0.07,bb*0.07,0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(br*0.18,bg2*0.18,bb*0.18,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(br*0.30,bg2*0.30,bb*0.30,1.0))
    end
    local clicked = imgui.Button(label, imgui.ImVec2(w or 0, h))
    imgui.PopStyleColor(3)
    if active then
        dl:AddRectFilled(
            imgui.ImVec2(p.x+S(4),         p.y+h-3),
            imgui.ImVec2(p.x+(w or 0)-S(4), p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(br,bg2,bb,0.95)), 2)
    end
    return clicked
end

local function stepBtn(id, label, onClickFn, w, h2)
    local r,g,b = getAcc()
    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.18,g*0.18,b*0.18,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.45,g*0.45,b*0.45,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.75,g*0.75,b*0.75,1.0))
    local clicked = imgui.Button(label.."##"..id, imgui.ImVec2(S(w or 44), S(h2 or 38)))
    imgui.PopStyleColor(3)
    if clicked then pcall(onClickFn) end
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 1: Š�Š•Š Š�Š˛Š¯Š�Š–
-- ============================================================
local function drawChar(s, h)
    _rowIndex = 0
    local gap  = 6
    local colW = (imgui.GetContentRegionAvail().x - gap) * 0.5

    -- Š›Š•Š’Š�ŠÆ Š�Š˛Š›Š˛Š¯Š�Š� ā€” Š‘Š�Š›Š�Š¯Š� + Š�Š§Š•Š¢Š� (Š¾Š±Ń‹Ń‡Š½Ń‹Š¹ Ń�ŠŗŃ€Š¾Š»Š»: ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_left", imgui.ImVec2(colW, h), false)
    if _resetCharScroll then imgui.SetScrollY(0) end
                secTitle(u8"\xc1\xe0\xeb\xe0\xed\xf1")
                dataRow(u8"SA$",    s.cashSas~="" and fmtMoney(s.cashSas) or "-", thGreen())
                dataRow(u8"\xc1\xe0\xed\xea", s.bank~="" and fmtMoney(s.bank) or "-", thAcc())
                dataRow(u8"\xc4\xe5\xef.", s.moneyDay~="" and fmtMoney(s.moneyDay) or "-", thGold())
                dataRow(u8"\xca\xe0\xf0\xf2\xe0", s.bankCard)
                if hasVal(s.cashVcs) then dataRow(u8"VC$", fmtMoney(s.cashVcs)) end
                if hasVal(s.btc)     then dataRow("BTC", fmtAmt(toNum(s.btc))) end
                if hasVal(s.euro)    then dataRow(u8"\xc5\xe2\xf0\xee", fmtAmt(toNum(s.euro))) end
                if hasVal(s.azCoins) or hasVal(s.accountState) then
                    local azRaw = hasVal(s.accountState) and s.accountState or s.azCoins
                    dataRow("AZ", fmtAmt(toNum(azRaw)), thGold())
                end
                -- ā”€ā”€ Š›Š�Š§Š¯Š«Š• Š�Š§Š•Š¢Š� (Š²Ń�Ń‚Ń€Š¾ŠµŠ½Ń‹ Š² Š»ŠµŠ²Ń�Ńˇ ŠŗŠ¾Š»Š¾Š½ŠŗŃ�) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
                do
                    local hasAccLeft = false
                    for i=1,6 do if hasVal(s.acc[i]) then hasAccLeft=true; break end end
                    if hasAccLeft then
                        _rowIndex = 0
                        secTitle(u8"\xd1\xf7\xb8\xf2\xe0")
                        for i=1,6 do
                            if hasVal(s.acc[i]) then
                                dataRow(u8"\xb9"..i, fmtMoney(s.acc[i]), thAcc())
                            end
                        end
                        if s.totalAcc ~= "" then
                            _rowIndex = 0
                            dataRow(u8"\xc8\xf2\xee\xe3", s.totalAcc, thGold())
                        end
                    end
                end
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.SameLine(0, gap)

    -- Š�Š Š�Š’Š�ŠÆ Š�Š˛Š›Š˛Š¯Š�Š� ā€” Š�Š•Š Š�Š˛Š¯Š�Š– (Š¾Š±Ń‹Ń‡Š½Ń‹Š¹ Ń�ŠŗŃ€Š¾Š»Š»: ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_right", imgui.ImVec2(colW, h), false)
    if _resetCharScroll then imgui.SetScrollY(0) end
                secTitle(u8"\xcb\xe8\xf7\xed\xee\xe5")
                dataRow(u8"\xd2\xe5\xeb\xe5\xf4\xee\xed",    s.phone)
                dataRow(u8"\xcf\xee\xeb",                     s.gender)
                dataRow(u8"\xc7\xe4\xee\xf0\xee\xe2\xfc\xe5", s.health,
                    (tonumber((s.health or ""):match("%d+")) or 100)>=80 and thGreen() or thRed())
                dataRow(u8"\xd0\xe0\xe1\xee\xf2\xe0",         s.job)
                if hasVal(s.org) or hasVal(s.position) or hasVal(s.status) then
                    secTitle(u8"\xce\xf0\xe3\xe0\xed\xe8\xe7\xe0\xf6\xe8\xff")
                    dataRow(u8"\xce\xf0\xe3.",    s.org)
                    dataRow(u8"\xc4\xee\xeb\xe6.", s.position)
                    dataRow(u8"\xd1\xf2\xe0\xf2\xf3\xf1", s.status)
                end
                secTitle(u8"\xd1\xee\xf6\xe8\xe0\xeb\xfc\xed\xee\xe5")
                dataRow(u8"\xd1\xe5\xec\xfc\xff", s.family)
                dataRow(u8"\xc3\xf0\xe0\xe6\xe4.", s.citizenship)
                secTitle(u8"\xcf\xf0\xe0\xe2\xee\xe2\xee\xe9")
                dataRow(u8"\xd3\xf0. \xf0\xee\xe7.", s.wanted,
                    (s.wanted=="0" or s.wanted=="-") and thGreen() or thRed())
                dataRow(u8"\xc7\xe0\xea\xee\xed.", s.lawfulness)
                dataRow(u8"\xcf\xf0\xe5\xe4\xf3\xef\xf0.", s.warnings,
                    (s.warnings=="0" or s.warnings=="-") and thGreen() or thRed())
                dataRow(u8"\xc7\xe0\xe2\xe8\xf1\xe8\xec.", s.addiction)
                if hasVal(s.hotel) or hasVal(s.hotelRoom) or hasVal(s.trailer) then
                    secTitle(u8"\xc8\xec\xf3\xf9\xe5\xf1\xf2\xe2\xee")
                    dataRow(u8"\xce\xf2\xe5\xeb\xfc",     s.hotel)
                    dataRow(u8"\xca\xee\xec\xed\xe0\xf2\xe0", s.hotelRoom)
                    dataRow(u8"\xd2\xf0\xe5\xe9\xeb\xe5\xf0", s.trailer)
                end
                if #s.extra > 0 then
                    secTitle(u8"\xcf\xf0\xee\xf7\xe5\xe5")
                    for _, pair in ipairs(s.extra) do dataRow(u8(pair[1]), pair[2]) end
                end
    imgui.EndChild()
    imgui.PopStyleColor()

    _resetCharScroll = false
end
-- ============================================================
local function drawBattle(s, h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sb", imgui.ImVec2(0,h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        secTitle(u8"\xc1\xee\xe5\xe2\xfb\xe5 \xc1\xee\xed\xf3\xf1\xfb")
        chipSide = false
        chip(u8"\xc7\xe0\xf9\xe8\xf2\xe0",        s.protection)
        chip(u8"\xd0\xe5\xe3\xe5\xed\xe5\xf0.",    s.regen)
        chip(u8"\xd3\xf0\xee\xed",                  s.damage)
        chip(u8"\xd3\xe4\xe0\xf7\xe0",              s.luck)
        chip(u8"\xcc\xe0\xea\xf1. HP",              s.maxHp)
        chip(u8"\xcc\xe0\xea\xf1. \xc1\xf0\xee\xed\xff", s.maxArmor)
        chip(u8"\xd8. \xee\xe3\xeb\xf3\xf8.",      s.stunChance)
        chip(u8"\xd8. \xee\xef\xfc\xff\xed.",      s.bleedChance)
        chip(u8"\xd8. \xf3\xea\xeb\xee\xed.",      s.dodgeChance)
        chip(u8"\xce\xf2\xf0\xe0\xe6. \xf3\xf0.",  s.reflectDamage)
        chip(u8"\xc1\xeb\xee\xea. \xf3\xf0.",      s.blockDamage)
        chip(u8"\xd1\xea\xee\xf0\xee\xf1\xf2\xf0.", s.fireRate)
        chip(u8"\xce\xf2\xea\xe0\xf2",              s.recoil)
        chip(u8"\xcf\xeb\xee\xe4",                   s.fruitStun)
        if chipSide then chipSide=false end

    -- ── нижний отступ, чтобы последняя строка не прилипала к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
end

-- ============================================================
--  Š‘Š£Š¤Š•Š Š« Š�Š›Š�Š™Š”Š•Š Š˛Š’ Š Š�Š—Š�Š•Š Š� Š˛Š�Š¯Š�
-- ============================================================
local winWbuf = imgui.new.float(0.60)
local winHbuf = imgui.new.float(0.76)
local WIN_W_MIN = 0.38
local WIN_H_MIN = 0.42
local fontSizeBuf = imgui.new.float(1.25)
local FONT_SIZE_MIN = 0.7
local FONT_SIZE_MAX = 2.0
-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ Š°Š²Ń‚Š¾-Š¾Š±Š½Š¾Š²Š»ŠµŠ½ŠøŃ¸ (Š´Š¾Š»Š¶Š½Ń‹ Š±Ń‹Ń‚Ń� Š³Š»Š¾Š±Š°Š»Ń�Š½Ń‹Š¼Šø, Š½Šµ Š²Š½Ń�Ń‚Ń€Šø Ń€ŠµŠ½Š´ŠµŃ€Š°!)
local chkBuf = imgui.new.bool(false)
local chkBuf2 = imgui.new.bool(true)
local aBuf   = imgui.new.float(30.0)
-- Buffery kursov obmena valyut (celye chisla, chtoby ne bylo lishnih nulikov posle zapyatoy)
local rateAZBuf  = imgui.new.int(0)
local rateBTCBuf = imgui.new.int(0)
local rateEURBuf = imgui.new.int(0)
local rateVCBuf  = imgui.new.int(1)
local rateASCBuf = imgui.new.int(0)
local ascAmtBuf  = imgui.new.int(0)
-- bufer imeni servera dlya avtoobnovleniya kursov s arz-wiki.com
local vcServerNameBuf = imgui.new.char[32]("Tucson")
local _vcServerActive = false
local _arzFetching    = false
local _arzLastResult  = ""
-- otslezhivaem kakoe pole seychas redaktiruetsya, chtoby ne perezapisyvat bufer
-- kazhdyy kadr poka igrok pechataet (imenno eto vyzyvalo "migание"/skachushchie nuliki)
local _rateActive = {}
-- razvernuta li kartochka "Kursy valyut" na vkladke Finansy (po kliku)
local _ratesExpanded = false
local _financeFilterExpanded = false
local _financeFilterBufs = {}

-- ── состояние окна "Настройки" вкладки "Финансы": по умолчанию оно
-- прикреплено к главному окну справа и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно ──
local _financeSettingsOpen     = false
local _financeSettingsDetached = false
local _financeSettingsPos      = nil   -- {x=,y=} запоминается, только пока панель откреплена
local _mainWinPos  = nil
local _mainWinSize = nil

-- ============================================================
--  VKLADKA 5: VSEGO DENEG
-- ============================================================
local function rateInputRow(id, label, buf, cfgKey, suffix)
    local r,g,b = getAcc()
    imgui.TextColored(thDim(), label)
    if suffix and suffix ~= "" then
        imgui.SameLine(0, 4)
        imgui.TextColored(iv4(0.45,0.48,0.55,1.0), suffix)
    end
    -- dopolnitelnyy otstup mezhdu podpisyu i polem vvoda, chtoby oni ne slipalis
    imgui.Dummy(imgui.ImVec2(0, S(5)))
    -- poka pole aktivno (igrok pechataet) -- ne trogaem bufer, chtoby kursor ne skakal
    if not _rateActive[id] then
        buf[0] = math.floor((cfg[cfgKey] or 0) + 0.5)
    end
    imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.16,g*0.16,b*0.16,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.28,g*0.28,b*0.28,1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.40,g*0.40,b*0.40,1.0))
    imgui.PushStyleColor(imgui.Col.Border,         iv4(math.min(1,r*1.15),math.min(1,g*1.15),math.min(1,b*1.15),0.70))
    imgui.PushStyleColor(imgui.Col.Text,           iv4(1,1,1,1))
    local _svr = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameRounding, 8.0) then _svr = _svr + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameBorderSize, 1.6) then _svr = _svr + 1 end
    -- bolshe vertikalnogo padding'a vnutri polya -- cifry bolshe ne "prilipayut" k ramke sverhu/snizu
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FramePadding, imgui.ImVec2(12, 10)) then _svr = _svr + 1 end
    local ok, changed = pcall(imgui.InputInt, "##rate"..id, buf, 0, 0)
    if ok and changed then
        if buf[0] < 0 then buf[0] = 0 end
        cfg[cfgKey] = buf[0]
        saveCfg()
    end
    local okA, isActive = pcall(imgui.IsItemActive)
    _rateActive[id] = okA and isActive or false
    if _svr > 0 then pcall(imgui.PopStyleVar, _svr) end
    imgui.PopStyleColor(5)
    imgui.Spacing()
end

-- ============================================================
--  ОБНОВЛЕНИЕ КУРСОВ ВАЛЮТ ЧЕРЕЗ ВНУТРИИГРОВОЙ ТЕЛЕФОН (без CEF)
-- ============================================================
-- В этой сборке MoonLoader модуль CEF недоступен, поэтому курсы
-- больше не берутся с внешних сайтов через скрытый браузер. Вместо
-- этого скрипт сам открывает телефон персонажа, заходит в раздел
-- финансов/курса валют и читает значения прямо из диалога сервера.
--
-- Точные ID диалогов и формулировки пунктов меню могут отличаться
-- между обновлениями Arizona RP, поэтому навигация ищет нужные пункты
-- по ключевым словам в тексте диалога, а не по жёстко заданным ID.
-- Если включить "Показывать лог диалогов" в настройках — в чат будет
-- выводиться ID/заголовок/текст каждого диалога во время обновления,
-- это нужно только для отладки, если авто-поиск пунктов меню не сработает.

local _cefFetching   = false
local _cefLastResult = ""  -- текстовый статус последней попытки (для UI)

-- состояние цепочки диалогов при автообновлении курса через телефон:
-- nil | "opening" (ждём главное меню телефона) | "in_menu" (ищем раздел
-- финансов) | "in_rates" (мы в разделе с курсами, разбираем текст)
local _phoneFetchState = nil

local function phoneDebugLog(msg)
    if cfg.phoneDebugLog then
        pcall(sampAddChatMessage, "{888888}[Stats:phone] " .. tostring(msg), -1)
    end
end

-- ищет в тексте диалога (пункты SAMP-списка разделены \n) индекс (с 0)
-- первой строки, содержащей любое слово из needles (без учёта регистра
-- и цветовых кодов). Возвращает индекс и саму строку, либо nil.
local function findPhoneListItem(text, needles)
    if not text or text == "" then return nil end
    local idx = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line):lower()
        if clean ~= "" then
            for _, n in ipairs(needles) do
                if clean:find(n, 1, true) then
                    return idx, clean
                end
            end
            idx = idx + 1
        end
    end
    return nil
end

-- вытаскивает число прямо перед/после ключевого слова currency в строке
-- вида "AZ-Coins   104.791 AZ - $3.667.685.000" или "Евро  44 EUR - $0" —
-- ищем именно курс (цену в SA$ за единицу), а не количество на руках,
-- поэтому берём число сразу после "$" в конце строки, если оно есть,
-- иначе — первое число в строке.
local function extractPhoneRate(text, needles)
    if not text or text == "" then return nil end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line)
        local low = clean:lower()
        for _, n in ipairs(needles) do
            if low:find(n, 1, true) then
                local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
                local numStr = afterDollar or clean:match("([%d%s%.,]+)")
                if numStr then
                    numStr = numStr:gsub("[%s,]", "")
                    local v = tonumber(numStr)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    return nil
end

-- разбирает текст диалога "курс валют" в телефоне и раскладывает найденные
-- значения по cfg.rateXXX/буферам полей ввода. Возвращает true, если хотя
-- бы один курс удалось распознать.
local function parsePhoneRatesText(text)
    if not text or text == "" then return false end
    local gotAny = false

    local rAZ  = extractPhoneRate(text, {"az-coin", "az \xea\xee\xe8\xed", "\xe0\xe7-\xea\xee\xe8\xed"})
    local rBTC = extractPhoneRate(text, {"btc", "bitcoin", "\xe1\xe8\xf2\xea\xee\xe9\xed"})
    local rEUR = extractPhoneRate(text, {"eur", "\xe5\xe2\xf0\xee"})
    local rVC  = extractPhoneRate(text, {"vc$", "vice city", "\xe2\xe0\xe9\xf1 \xf1\xe8\xf2\xe8"})
    local rASC = extractPhoneRate(text, {"asc", "\xe0\xf0\xe8\xe7\xee\xed\xe0 \xf1\xf2\xe5\xe9\xe1\xeb"})

    if rAZ  and rAZ  > 0 then cfg.rateAZ  = rAZ;  rateAZBuf[0]  = math.floor(rAZ  + 0.5); gotAny = true end
    if rBTC and rBTC > 0 then cfg.rateBTC = rBTC; rateBTCBuf[0] = math.floor(rBTC + 0.5); gotAny = true end
    if rEUR and rEUR > 0 then cfg.rateEUR = rEUR; rateEURBuf[0] = math.floor(rEUR + 0.5); gotAny = true end
    if rVC  and rVC  > 0 then cfg.rateVC  = rVC;  rateVCBuf[0]  = math.floor(rVC  + 0.5); gotAny = true end
    if rASC and rASC > 0 then cfg.rateASC = rASC; rateASCBuf[0] = math.floor(rASC + 0.5); gotAny = true end

    if gotAny then saveCfg() end
    return gotAny
end

-- Запускает автообновление: открывает телефон командой cfg.phoneOpenCmd,
-- дальше цепочку диалогов ведёт sampev.onShowDialog (ищет пункт "Финансы",
-- затем "Курс валют", читает текст, закрывает диалог, чтобы игрок его не
-- видел). Имя функции оставлено прежним, чтобы не менять остальной код —
-- по сути это уже не CEF, а телефон.
local function fetchRatesViaCEF()
    if _cefFetching then return end
    if not isSampAvailable() then
        _cefLastResult = u8"\xf1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    _cefFetching     = true
    _phoneFetchState = "opening"
    _cefLastResult   = u8"\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed..."
    pcall(sampAddChatMessage, "{FFD700}[Stats] " .. u8"\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed, \xf7\xf2\xee\xe1\xfb \xef\xf0\xee\xf7\xe8\xf2\xe0\xf2\xfc \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2...", -1)
    lua_thread.create(function()
        local cmd = (cfg.phoneOpenCmd and cfg.phoneOpenCmd ~= "") and cfg.phoneOpenCmd or "/phone"
        local okCmd = pcall(sampSendChat, cmd)
        if not okCmd then
            _phoneFetchState = nil
            _cefFetching     = false
            _cefLastResult   = u8"\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc \xea\xee\xec\xe0\xed\xe4\xf3 " .. cmd
            return
        end
        local waited = 0
        while _phoneFetchState ~= nil and waited < 7000 do
            wait(100); waited = waited + 100
        end
        if _phoneFetchState ~= nil then
            _phoneFetchState = nil
            _cefLastResult = u8"\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xed\xe0\xe9\xf2\xe8 \xea\xf3\xf0\xf1 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5 \xe7\xe0 7 \xf1\xe5\xea\xf3\xed\xe4"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. u8"\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8 \xed\xe0\xe9\xf2\xe8 \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5. \xc2\xea\xeb\xfe\xf7\xe8\xf2\xe5 \\\"\xcf\xee\xea\xe0\xe7\xfb\xe2\xe0\xf2\xfc \xeb\xee\xe3 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2\\\" \xe2 \xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe0\xf5 \xe8 \xef\xee\xef\xf0\xee\xe1\xf3\xe9\xf2\xe5 \xe5\xf9\xb8 \xf0\xe0\xe7 - \xf3\xe2\xe8\xe4\xe8\xf2\xe5 \xf1\xef\xe8\xf1\xee\xea \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2 \xe8 \xef\xee\xe4\xf1\xea\xe0\xe6\xe5\xf2\xe5, \xea\xe0\xea\xee\xe9 \xef\xf3\xed\xea\xf2 \xec\xe5\xed\xfe \xed\xf3\xe6\xe5\xed.", -1)
        end
        _cefFetching = false
    end)
end

-- ── старое имя оставлено как no-op обёртка (раньше отдельно ходила на
-- arz-wiki.com за VC$/AZ/BTC/EUR/ASC) — теперь весь набор курсов уже
-- приходит одним проходом через fetchRatesViaCEF() (телефон), повторный
-- сетевой запрос больше не нужен ──
local function fetchArzWikiRates()
end

-- ── круглый тумблер вкл/выкл: зелёный = включено, красный = выключено ──
local function drawToggleSwitch(id, isOn)
    local w, h2 = S(34), S(18)
    local p  = imgui.GetCursorScreenPos()
    local dl = imgui.GetWindowDrawList()
    imgui.InvisibleButton(id, imgui.ImVec2(w, h2))
    local clicked = imgui.IsItemClicked and imgui.IsItemClicked() or false
    local hovered = imgui.IsItemHovered and imgui.IsItemHovered() or false
    local bgCol
    if isOn then
        bgCol = hovered and iv4(0.30,0.90,0.46,1.0) or iv4(0.20,0.78,0.35,1.0)
    else
        bgCol = hovered and iv4(0.95,0.30,0.30,1.0) or iv4(0.80,0.20,0.20,1.0)
    end
    dl:AddRectFilled(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x+w, p.y+h2),
        imgui.ColorConvertFloat4ToU32(bgCol), h2/2)
    dl:AddRect(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x+w, p.y+h2),
        imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.45)), h2/2, 0, 1.4)
    local knobR = h2/2 - 2
    local knobX = isOn and (p.x + w - h2/2) or (p.x + h2/2)
    dl:AddCircleFilled(imgui.ImVec2(knobX, p.y + h2/2), knobR,
        imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.95)))
    return clicked
end

-- ── skruglenie uglov knopok (ispolzuyetsya tochechno tam, gde nuzhno "krasivee") ──
local function prettyBtnPush(round)
    local n = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameRounding, round or 8.0) then n = n + 1 end
    return n
end
local function prettyBtnPop(n)
    if n and n > 0 then pcall(imgui.PopStyleVar, n) end
end

-- ── всплывающее окно "Настройки" вкладки "Финансы": вынесено в отдельную
-- функцию, чтобы не раздувать список апвэлью drawTotal (лимит Lua — 60) ──
local function drawFinanceSettingsBlock(r, g, b)
    local avW  = imgui.GetContentRegionAvail().x

    -- ── единая кнопка "Настройки" — открывает/закрывает панель настроек
    -- вкладки "Финансы". Панель больше не всплывающий popup, а отдельное
    -- окно, прикреплённое справа от главного окна (см. drawFinanceSettingsPanel) ──
    local pr0,pg0,pb0 = getAcc()
    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr0*0.22,pg0*0.22,pb0*0.22,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr0*0.40,pg0*0.40,pb0*0.40,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr0*0.58,pg0*0.58,pb0*0.58,1.0))
    do local _pb = prettyBtnPush(10.0)
    if imgui.Button(u8"  \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8##financeSettingsBtn", imgui.ImVec2(avW, S(36))) then
        _financeSettingsOpen = not _financeSettingsOpen
    end
    prettyBtnPop(_pb) end
    imgui.PopStyleColor(3)
end

-- ── содержимое панели "Настройки" вкладки "Финансы" — вынесено отдельно
-- от самого окна (drawFinanceSettingsPanel), чтобы окно можно было рисовать
-- вне вкладки "Финансы" (оно теперь отдельное, пристыкованное окно) ──
local function drawFinanceSettingsPanelContent(r, g, b)
    imgui.TextColored(thDim(), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xe2\xea\xeb\xe0\xe4\xea\xe8 \xab\xd4\xe8\xed\xe0\xed\xf1\xfb\xbb:")
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- ── единая кнопка: обновляет и EUR/BTC, и VC$/AZ/EURO/ASC под сервер ──
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xca\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2")
    imgui.Spacing()

    -- переключатель: определять сервер автоматически (по текущему SAMP-серверу)
    -- или вводить название вручную
    if drawToggleSwitch("##vcAutoDetectSw", cfg.vcAutoDetectServer) then
        cfg.vcAutoDetectServer = not cfg.vcAutoDetectServer
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(0.85,0.87,0.95,1.0), u8"\xce\xef\xf0\xe5\xe4\xe5\xeb\xff\xf2\xfc \xf1\xe5\xf0\xe2\xe5\xf0 \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8")
    imgui.Spacing()

    if cfg.vcAutoDetectServer then
        -- автоматический режим: просто показываем, что определил скрипт прямо сейчас
        local detectedNow = detectArzServerName()
        if detectedNow then
            imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0: ")
            imgui.SameLine(0,4)
            imgui.TextColored(iv4(0.40,0.90,0.55,1.0), detectedNow)
        else
            imgui.TextColored(iv4(0.95,0.55,0.30,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0 \xed\xe5 \xee\xef\xf0\xe5\xe4\xe5\xeb\xb8\xed 3 \xe7\xe0\xe9\xe4\xe8\xf2\xe5 \xed\xe0 \xf1\xe5\xf0\xe2\xe5\xf0 \xe8\xeb\xe8 \xe2\xe2\xe5\xe4\xe8\xf2\xe5 \xe2\xf0\xf3\xf7\xed\xf3\xfe")
        end
    else
        imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0:")
        imgui.SameLine(0,6)
        imgui.PushItemWidth(S(150))
        imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.16,g*0.16,b*0.16,1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.26,g*0.26,b*0.26,1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.36,g*0.36,b*0.36,1.0))
        do local _svsn = 0
        if pcall(imgui.PushStyleVar, imgui.StyleVar.FrameRounding, 7.0) then _svsn = _svsn + 1 end
        if not _vcServerActive then
            pcall(function()
                local cur = cfg.vcServerName or "Tucson"
                for i=0,#cur-1 do vcServerNameBuf[i] = cur:byte(i+1) end
                vcServerNameBuf[#cur] = 0
            end)
        end
        local okVS, changedVS = pcall(imgui.InputText, "##vcServerName", vcServerNameBuf, 32)
        if okVS and changedVS then
            -- sobiraem stroku iz baytov bufera vruchnuyu (bez zavisimosti ot ffi.string)
            local chars = {}
            for i=0,31 do
                local by = tonumber(vcServerNameBuf[i]) or 0
                if by == 0 then break end
                chars[#chars+1] = string.char(by)
            end
            cfg.vcServerName = table.concat(chars)
            saveCfg()
        end
        local okVSA, isVSA = pcall(imgui.IsItemActive)
        _vcServerActive = okVSA and isVSA or false
        if _svsn > 0 then pcall(imgui.PopStyleVar, _svsn) end
        end
        imgui.PopStyleColor(3)
        imgui.PopItemWidth()
    end
    imgui.Spacing()
    do
        local busy = _cefFetching or _arzFetching
        local awBg = busy and {0.85,0.68,0.15} or {0.16,0.52,0.92}
        local awLbl = busy
            and u8"  \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
            or  u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc \xea\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2"
        imgui.PushStyleColor(imgui.Col.Button,        iv4(awBg[1]*0.55,awBg[2]*0.55,awBg[3]*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(awBg[1]*0.75,awBg[2]*0.75,awBg[3]*0.75,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(awBg[1],awBg[2],awBg[3],1.0))
        do local _pb2 = prettyBtnPush(9.0)
        if imgui.Button(awLbl.."##financeRefAll", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            fetchRatesViaCEF()
            fetchArzWikiRates()
        end
        prettyBtnPop(_pb2) end
        imgui.PopStyleColor(3)
        if _cefLastResult ~= "" then
            imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. _cefLastResult)
        end
        -- переключатель отладочного лога навигации по телефону (см. fetchRatesViaCEF)
        imgui.Spacing()
        if drawToggleSwitch("##phoneDebugSw", cfg.phoneDebugLog) then
            cfg.phoneDebugLog = not cfg.phoneDebugLog
            saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(iv4(0.85,0.87,0.95,1.0), u8"\xcf\xee\xea\xe0\xe7\xfb\xe2\xe0\xf2\xfc \xeb\xee\xe3 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0 \xe2 \xf7\xe0\xf2 (\xee\xf2\xeb\xe0\xe4\xea\xe0)")
    end
    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- 2) переключить раскладку (список / два столбика)
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd0\xe0\xf1\xea\xeb\xe0\xe4\xea\xe0")
    imgui.Spacing()
    if drawToggleSwitch("##financeColSw", cfg.financeTwoCol) then
        cfg.financeTwoCol = not cfg.financeTwoCol
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(0.85,0.87,0.95,1.0), cfg.financeTwoCol
        and u8"\xe4\xe2\xe0 \xf1\xf2\xee\xeb\xe1\xe8\xea\xe0"
        or  u8"\xee\xe1\xfb\xf7\xed\xfb\xe9 \xf1\xef\xe8\xf1\xee\xea")
    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- 3) выбор категорий для общего итога
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd7\xf2\xee \xf3\xf7\xe8\xf2\xfb\xe2\xe0\xf2\xfc \xe2 \xab\xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2\xbb")
    imgui.Spacing()
    local _flt = {
        { u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5", "incCash" },
        { u8"\xc1\xe0\xed\xea",                  "incBank" },
        { u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",       "incDep"  },
        { u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", "incAcc" },
        { "AZ-Coins", "incAZ"  },
        { "BTC",      "incBTC" },
        { u8"\xc5\xe2\xf0\xee", "incEUR" },
        { "VC$",      "incVC"  },
        { "ASC",      "incASC" },
    }
    for i, fl in ipairs(_flt) do
        local isOn = cfg[fl[2]]
        if drawToggleSwitch("##ftg"..fl[2], isOn) then
            cfg[fl[2]] = not isOn
            saveCfg()
        end
        imgui.SameLine(0, S(8))
        imgui.TextColored(isOn and iv4(0.85,0.95,0.88,1.0) or iv4(0.55,0.55,0.58,1.0), fl[1])
    end

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))
    do
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        do local _pbc = prettyBtnPush(8.0)
        if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeFinanceSettings", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
            _financeSettingsOpen = false
        end
        prettyBtnPop(_pbc) end
        imgui.PopStyleColor(3)
    end
end

-- ── отдельное окно панели настроек вкладки "Финансы". По умолчанию
-- пристыковано справа от главного окна и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно в любом месте экрана ──
local function drawFinanceSettingsPanel()
    if not _financeSettingsOpen then return end
    if not _mainWinPos or not _mainWinSize then return end

    local panelW = S(320)

    if not _financeSettingsDetached then
        imgui.SetNextWindowPos(imgui.ImVec2(_mainWinPos.x + _mainWinSize.x + S(10), _mainWinPos.y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, _mainWinSize.y), imgui.Cond.Always)
    else
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, _mainWinSize.y), imgui.Cond.FirstUseEver)
        if _financeSettingsPos then
            imgui.SetNextWindowPos(imgui.ImVec2(_financeSettingsPos.x, _financeSettingsPos.y), imgui.Cond.FirstUseEver)
        else
            imgui.SetNextWindowPos(imgui.ImVec2(_mainWinPos.x + _mainWinSize.x + S(10), _mainWinPos.y), imgui.Cond.FirstUseEver)
        end
    end

    applyStyle()
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
    if not _financeSettingsDetached then
        flags = flags + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
    end
    imgui.Begin("###financeSettingsPanel", nil, flags)
    imgui.SetWindowFontScale(UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

    if _financeSettingsDetached then
        local p = imgui.GetWindowPos()
        _financeSettingsPos = {x = p.x, y = p.y}
    end

    -- ── шапка панели: заголовок + кнопка "Открепить/Закрепить" ──
    do
        local aw = imgui.GetContentRegionAvail().x
        imgui.TextColored(iv4(1,1,1,1), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf4\xe8\xed\xe0\xed\xf1\xee\xe2")
        imgui.SameLine(math.max(0, aw - S(104)))
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        local detachLbl = _financeSettingsDetached
            and u8"\xc7\xe0\xea\xf0\xe5\xef\xe8\xf2\xfc"
            or  u8"\xce\xf2\xea\xf0\xe5\xef\xe8\xf2\xfc"
        if imgui.Button(detachLbl.."##financeDetachBtn", imgui.ImVec2(S(104), S(24))) then
            _financeSettingsDetached = not _financeSettingsDetached
            if _financeSettingsDetached then
                local p = imgui.GetWindowPos()
                _financeSettingsPos = {x = p.x, y = p.y}
            end
        end
        imgui.PopStyleColor(3)
    end
    imgui.Separator()
    imgui.Spacing()

    local r, g, b = getAcc()
    drawFinanceSettingsPanelContent(r, g, b)

    imgui.End()
end


-- ── кнопка-копия итога "ВСЕГО ВИРТОВ" в чат: тоже вынесена отдельно ──
local function drawGrandTotalCopyButton(aw, hh, r, g, b, bigTxt)
    local btnW2, btnH2 = S(44), S(32)
    imgui.SetCursorPos(imgui.ImVec2(aw - btnW2 - S(12), (hh - btnH2)*0.5))
    imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.25,g*0.25,b*0.25,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.65,g*0.65,b*0.65,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,      g,      b,      1.0))
    do local _svg = prettyBtnPush(7.0)
    if imgui.Button(">>##cpGrandTotal", imgui.ImVec2(btnW2, btnH2)) then
        pcall(sampAddChatMessage, "{FFD700}[MSW] \xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2: " .. bigTxt, -1)
    end
    prettyBtnPop(_svg) end
    imgui.PopStyleColor(3)
end

local function drawTotal(s, h)
    _rowIndex = 0
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##stot", imgui.ImVec2(0, h), false)
    if _resetCharScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()

        -- ── кнопки управления вкладкой "Всего": подписаны текстом, читаемый
        -- шрифт, толщина рамки 4px, ширина считается так, чтобы все кнопки
        -- помещались в один ряд ──────────────────────────────────────────
        drawFinanceSettingsBlock(r, g, b)

        local cash = toNum(s.cashSas)
        local bank = toNum(s.bank)
        local dep  = toNum(s.moneyDay)
        local accT = 0
        for i=1,6 do accT = accT + toNum(s.acc[i]) end

        local az  = toNum(hasVal(s.accountState) and s.accountState or s.azCoins)
        local btc = toNum(s.btc)
        local eur = toNum(s.euro)
        local vc  = toNum(s.cashVcs)
        local asc = tonumber(cfg.ascAmount) or 0

        local azSA  = az  * cfg.rateAZ
        local btcSA = btc * cfg.rateBTC
        local eurSA = eur * cfg.rateEUR
        local vcSA  = vc  * cfg.rateVC
        local ascSA = asc * cfg.rateASC

        -- итог считаем только по включённым в фильтре категориям
        local cashInc = cfg.incCash and cash or 0
        local bankInc = cfg.incBank and bank or 0
        local depInc  = cfg.incDep  and dep  or 0
        local accInc  = cfg.incAcc  and accT or 0
        local azInc   = cfg.incAZ  and azSA  or 0
        local btcInc  = cfg.incBTC and btcSA or 0
        local eurInc  = cfg.incEUR and eurSA or 0
        local vcInc   = cfg.incVC  and vcSA  or 0
        local ascInc  = cfg.incASC and ascSA or 0

        local curSum = azInc + btcInc + eurInc + vcInc + ascInc
        local grand  = cashInc + bankInc + depInc + accInc + curSum
        if grand < 0 then grand = 0 end

        -- bolshaya plashka "Vsego virtov" (s avtoumensheniem shrifta pod razmer okna)
        do
            local dl = imgui.GetWindowDrawList()
            local p  = imgui.GetCursorScreenPos()
            local aw = imgui.GetContentRegionAvail().x
            local hh = S(80)
            dl:AddRectFilled(
                imgui.ImVec2(p.x,      p.y),
                imgui.ImVec2(p.x+aw,   p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.20,g*0.20,b*0.20,0.97)), 12)
            dl:AddRect(
                imgui.ImVec2(p.x,      p.y),
                imgui.ImVec2(p.x+aw,   p.y+hh),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.90)), 12, 0, 1.5)
            dl:AddRectFilled(
                imgui.ImVec2(p.x,   p.y+6),
                imgui.ImVec2(p.x+4, p.y+hh-6),
                imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##totbig", imgui.ImVec2(aw, hh), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(10)))
                imgui.TextColored(thDim(), u8"\xc2\xd1\xc5\xc3\xce \xc2\xc8\xd0\xd2\xce\xc2")
                local bigTxt = fmtMoney(string.format("%.0f", grand))
                -- podgonyaem masshtab shrifta pod shirinu okna, chtoby ochen bolshie summy (trilliony) ne obrezalis
                local baseScale = UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
                local availTxtW = aw - S(28)
                local okCTS, tsz = pcall(imgui.CalcTextSize, bigTxt)
                local shrink = 1.0
                if okCTS and tsz and tsz.x and tsz.x > availTxtW and tsz.x > 0 then
                    shrink = availTxtW / tsz.x
                    if shrink < 0.45 then shrink = 0.45 end
                end
                if shrink < 0.999 then pcall(imgui.SetWindowFontScale, baseScale * shrink) end
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(32)))
                imgui.TextColored(getElemColor("grandtotal", thGold()), bigTxt)
                recolorOnClick("grandtotal")
                if shrink < 0.999 then pcall(imgui.SetWindowFontScale, baseScale) end

                -- кнопка-копия: вывести "ВСЕГО ВИРТОВ" в чат (как белые кнопки на вкладке "Персонаж")
                drawGrandTotalCopyButton(aw, hh, r, g, b, bigTxt)
            imgui.EndChild()
            imgui.PopStyleColor()

            -- "svoya fishka": polosa raspredeleniya bogatstva
            if grand > 0 then
                local segs = {
                    { v = cashInc, col = {0.30,0.85,0.50}, name = u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5" },
                    { v = bankInc, col = {0.35,0.62,0.95}, name = u8"\xc1\xe0\xed\xea" },
                    { v = depInc,  col = {0.95,0.78,0.25}, name = u8"\xc4\xe5\xef\xee\xe7\xe8\xf2" },
                    { v = accInc,  col = {0.65,0.55,0.95}, name = u8"\xd1\xf7\xe5\xf2\xe0" },
                    { v = curSum,  col = {0.95,0.45,0.55}, name = u8"\xc2\xe0\xeb\xfe\xf2\xfb" },
                }
                local by = p.y + hh + S(10)
                local bh = S(14)
                -- фон полосы (более крупная, с лёгкой рамкой снизу) — так проще разглядеть сегменты
                dl:AddRectFilled(imgui.ImVec2(p.x, by), imgui.ImVec2(p.x+aw, by+bh),
                    imgui.ColorConvertFloat4ToU32(iv4(0.08,0.08,0.10,1.0)), bh/2)
                local bx = p.x
                for i=1,#segs do
                    local sv = segs[i].v
                    if sv > 0 then
                        local sw2 = aw * (sv / grand)
                        local c = segs[i].col
                        dl:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx+sw2, by+bh),
                            imgui.ColorConvertFloat4ToU32(iv4(c[1],c[2],c[3],1.0)))
                        -- тонкий разделитель между сегментами, чтобы было видно границы
                        if bx > p.x then
                            dl:AddLine(imgui.ImVec2(bx, by), imgui.ImVec2(bx, by+bh),
                                imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.35)), 1)
                        end
                        -- наведение мышью прямо на цвет в самом графике — показываем процент
                        do
                            imgui.SetCursorScreenPos(imgui.ImVec2(bx, by))
                            imgui.InvisibleButton("##segHover"..i, imgui.ImVec2(sw2, bh))
                            if imgui.IsItemHovered and imgui.IsItemHovered() then
                                imgui.BeginTooltip()
                                imgui.Text(string.format("%s: %.1f%%", segs[i].name, sv/grand*100))
                                imgui.EndTooltip()
                            end
                        end
                        bx = bx + sw2
                    end
                end
                dl:AddRect(imgui.ImVec2(p.x, by), imgui.ImVec2(p.x+aw, by+bh),
                    imgui.ColorConvertFloat4ToU32(iv4(1,1,1,0.14)), bh/2, 0, 1.2)
                imgui.SetCursorScreenPos(imgui.ImVec2(p.x, by+bh))
                imgui.Dummy(imgui.ImVec2(aw, S(10)))

                -- легенда: только цветной квадратик + название (без цифр); процент — во всплывающей подсказке при наведении
                do
                    local avL = imgui.GetContentRegionAvail().x
                    local usedX = 0
                    for i=1,#segs do
                        local sv = segs[i].v
                        if sv > 0 then
                            local c    = segs[i].col
                            local pct  = sv / grand * 100
                            local txt  = segs[i].name
                            local tw   = imgui.CalcTextSize(txt).x
                            local itemW = S(16) + 4 + tw + S(14)
                            if usedX > 0 and usedX + itemW > avL then
                                usedX = 0
                            elseif usedX > 0 then
                                imgui.SameLine(0, S(14))
                            end
                            local lp = imgui.GetCursorScreenPos()
                            dl:AddRectFilled(
                                imgui.ImVec2(lp.x, lp.y+2),
                                imgui.ImVec2(lp.x+S(10), lp.y+S(12)),
                                imgui.ColorConvertFloat4ToU32(iv4(c[1],c[2],c[3],1.0)), 3)
                            imgui.Dummy(imgui.ImVec2(S(14), S(14)))
                            if imgui.IsItemHovered() then
                                imgui.BeginTooltip()
                                imgui.Text(string.format("%s: %.0f%%", txt, pct))
                                imgui.EndTooltip()
                            end
                            imgui.SameLine(0,4)
                            imgui.TextColored(iv4(0.85,0.87,0.95,1.0), txt)
                            usedX = usedX + itemW
                        end
                    end
                end
                imgui.Spacing()
            end
        end
        imgui.Spacing()

        if cfg.financeTwoCol then
            -- ── ДВА СТОЛБИКА: слева наличные/банк/депозит/счета, справа валюты ──
            local okCols = pcall(imgui.Columns, 2, "##fincols", false)
            _rowIndex = 0
            secTitle(u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xf1\xf0\xe5\xe4\xf1\xf2\xe2\xe0")
            dataRow(u8"\xcd\xe0 \xf0\xf3\xea\xe0\xf5", fmtMoney(string.format("%.0f", cash)), thGreen())
            dataRow(u8"\xc1\xe0\xed\xea",              fmtMoney(string.format("%.0f", bank)), thAcc())
            dataRow(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",  fmtMoney(string.format("%.0f", dep)),  thGold())
            if accT > 0 then
                dataRow(u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", fmtMoney(string.format("%.0f", accT)), thAcc())
            end
            if okCols then pcall(imgui.NextColumn) end
            _rowIndex = 0
            secTitle(u8"\xc2\xe0\xeb\xfe\xf2\xfb")
            if az > 0 then
                dataRow("AZ-Coins", fmtAmt(az).." AZ  -  "..fmtMoney(string.format("%.0f", azSA)), thGold())
            end
            if btc > 0 then
                dataRow("BTC", fmtAmt(btc).." BTC  -  "..fmtMoney(string.format("%.0f", btcSA)), thGold())
            end
            if eur > 0 then
                dataRow(u8"\xc5\xe2\xf0\xee", fmtAmt(eur).." EUR  -  "..fmtMoney(string.format("%.0f", eurSA)), thGold())
            end
            if vc > 0 then
                dataRow("VC$", fmtAmt(vc).." VC$  -  "..fmtMoney(string.format("%.0f", vcSA)), thGold())
            end
            if asc > 0 then
                dataRow("ASC", fmtAmt(asc).." ASC  -  "..fmtMoney(string.format("%.0f", ascSA)), thGold())
            end
            if az<=0 and btc<=0 and eur<=0 and vc<=0 and asc<=0 then
                imgui.Spacing()
                imgui.TextColored(thDim(), u8"  \xed\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5 \xef\xee \xe2\xe0\xeb\xfe\xf2\xe0\xec")
            end
            if okCols then pcall(imgui.Columns, 1) end
            imgui.Spacing()
        else
        -- nalichnye sredstva (SA$)
        _rowIndex = 0
        secTitle(u8"\xcd\xe0\xeb\xe8\xf7\xed\xfb\xe5 \xf1\xf0\xe5\xe4\xf1\xf2\xe2\xe0")
        dataRow(u8"\xcd\xe0 \xf0\xf3\xea\xe0\xf5", fmtMoney(string.format("%.0f", cash)), thGreen())
        dataRow(u8"\xc1\xe0\xed\xea",              fmtMoney(string.format("%.0f", bank)), thAcc())
        dataRow(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2",  fmtMoney(string.format("%.0f", dep)),  thGold())
        if accT > 0 then
            dataRow(u8"\xcb\xe8\xf7\xed\xfb\xe5 \xf1\xf7\xe5\xf2\xe0", fmtMoney(string.format("%.0f", accT)), thAcc())
        end
        imgui.Dummy(imgui.ImVec2(0, S(6)))

        -- valyuty + formula konvertacii (tolko chtenie, kursy nastraivayutsya v Nastroykah)
        _rowIndex = 0
        secTitle(u8"\xc2\xe0\xeb\xfe\xf2\xfb")
        if az > 0 then
            dataRow("AZ-Coins", fmtAmt(az).." AZ  -  "..fmtMoney(string.format("%.0f", azSA)), thGold())
        end
        if btc > 0 then
            dataRow("BTC", fmtAmt(btc).." BTC  -  "..fmtMoney(string.format("%.0f", btcSA)), thGold())
        end
        if eur > 0 then
            dataRow(u8"\xc5\xe2\xf0\xee", fmtAmt(eur).." EUR  -  "..fmtMoney(string.format("%.0f", eurSA)), thGold())
        end
        if vc > 0 then
            dataRow("VC$", fmtAmt(vc).." VC$  -  "..fmtMoney(string.format("%.0f", vcSA)), thGold())
        end
        if asc > 0 then
            dataRow("ASC", fmtAmt(asc).." ASC  -  "..fmtMoney(string.format("%.0f", ascSA)), thGold())
        end
        if az<=0 and btc<=0 and eur<=0 and vc<=0 and asc<=0 then
            imgui.Spacing()
            imgui.TextColored(thDim(), u8"  \xed\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5 \xef\xee \xe2\xe0\xeb\xfe\xf2\xe0\xec")
        end
        end
        imgui.Spacing()
        do
            local btnLabel = _ratesExpanded
                and u8"  [-]  \xca\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2  "
                or  u8"  [+]  \xca\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2  "
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.16,g*0.16,b*0.16,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.28,g*0.28,b*0.28,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.38,g*0.38,b*0.38,1.0))
            if imgui.Button(btnLabel, imgui.ImVec2(imgui.GetContentRegionAvail().x, S(34))) then
                _ratesExpanded = not _ratesExpanded
            end
            imgui.PopStyleColor(3)

            if _ratesExpanded then
                imgui.Spacing()
                -- pokazyvaem pole kursa tolko dlya teh valyut, kotorye realno
                -- prisutstvuyut v state igroka (summa > 0), a ne dlya vseh podryad
                local rr_az, rr_btc, rr_eur, rr_vc, rr_asc = az>0, btc>0, eur>0, vc>0, asc>0
                local rowsCount = (rr_az and 1 or 0) + (rr_btc and 1 or 0) + (rr_eur and 1 or 0) + (rr_vc and 1 or 0) + (rr_asc and 1 or 0)
                local dl_r = imgui.GetWindowDrawList()
                local pp_r = imgui.GetCursorScreenPos()
                local aw_r = imgui.GetContentRegionAvail().x
                local extraFetchH = (_cefLastResult ~= "" and (rr_btc or rr_eur)) and S(24) or 0
                local cardHr = (rowsCount > 0 and (S(24) + rowsCount * S(62)) or S(56)) + extraFetchH
                dl_r:AddRectFilled(
                    imgui.ImVec2(pp_r.x,      pp_r.y),
                    imgui.ImVec2(pp_r.x+aw_r, pp_r.y+cardHr),
                    imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 10)
                dl_r:AddRect(
                    imgui.ImVec2(pp_r.x,      pp_r.y),
                    imgui.ImVec2(pp_r.x+aw_r, pp_r.y+cardHr),
                    imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.75)), 10, 0, 1.2)
                imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
                imgui.BeginChild("##ratec2", imgui.ImVec2(aw_r, cardHr), false,
                    imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                    imgui.SetCursorPos(imgui.ImVec2(S(14), S(10)))
                    imgui.PushItemWidth(aw_r - S(28))
                    if rr_az then
                        imgui.SetCursorPosX(S(14))
                        rateInputRow("az",  "AZ-Coins", rateAZBuf,  "rateAZ")
                    end
                    if rr_btc then
                        imgui.SetCursorPosX(S(14))
                        rateInputRow("btc", "BTC",      rateBTCBuf, "rateBTC")
                    end
                    if rr_eur then
                        imgui.SetCursorPosX(S(14))
                        rateInputRow("eur", u8"\xc5\xe2\xf0\xee", rateEURBuf, "rateEUR")
                    end
                    if rr_vc then
                        imgui.SetCursorPosX(S(14))
                        rateInputRow("vc",  "VC$",       rateVCBuf,  "rateVC")
                    end
                    if rr_asc then
                        imgui.SetCursorPosX(S(14))
                        rateInputRow("asc", u8"\xca\xf3\xf0\xf1 ASC", rateASCBuf, "rateASC")
                    end
                    imgui.PopItemWidth()
                    if rowsCount == 0 then
                        imgui.SetCursorPosX(S(14))
                        imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xed\xe5\xf2 \xe2\xe0\xeb\xfe\xf2 \xe4\xeb\xff \xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xea\xf3\xf0\xf1\xe0")
                    else
                        imgui.SetCursorPosX(S(14))
                        imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xe2\xe2\xe5\xe4\xe8 \xf6\xe8\xf4\xf0\xfb \xe1\xe5\xe7 \xf0\xe0\xe7\xe4\xe5\xeb\xe8\xf2\xe5\xeb\xe5\xe9 \xe8 \xef\xf0\xee\xe1\xe5\xeb\xee\xe2")
                    end
                    if _cefLastResult ~= "" and (rr_btc or rr_eur) then
        imgui.SetCursorPosX(S(14))
                        imgui.TextColored(iv4(0.5,0.52,0.58,1.0), _cefLastResult)
                    end
                imgui.EndChild()
                imgui.PopStyleColor()
            end
        end

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    _resetCharScroll = false
end


-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 3: Š¯Š�Š�Š¢Š Š˛Š™Š�Š�
-- ============================================================
local function drawSettings(h, sw, sh)
    -- ā”€ā”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ Š¯Š�Š�Š¢Š Š˛Š•Š� (Š¾Š±Ń‹Ń‡Š½Ń‹Š¹ Ń�ŠŗŃ€Š¾Š»Š»: ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø) ā”€ā”€
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sset", imgui.ImVec2(0, h), false)
    if _resetSettScroll then imgui.SetScrollY(0) end
            local r,g,b = getAcc()

        -- ā”€ā”€ Š Š�Š—Š�Š•Š  Š˛Š�Š¯Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xee\xea\xed\xe0")
        local curWPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local curHPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        winWbuf[0] = curWPct
        winHbuf[0] = curHPct

        -- Š�Š°Ń€Ń‚Š¾Ń‡ŠŗŠ° Ń� Š´Š²Ń�Š¼Ń¸ Ń�Š»Š°Š¹Š´ŠµŃ€Š°Š¼Šø
        do
            local dl_s = imgui.GetWindowDrawList()
            local pp_s = imgui.GetCursorScreenPos()
            local aw_s = imgui.GetContentRegionAvail().x
            local cardH = S(168)
            dl_s:AddRectFilled(
                imgui.ImVec2(pp_s.x,      pp_s.y),
                imgui.ImVec2(pp_s.x+aw_s, pp_s.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 10)
            dl_s:AddRect(
                imgui.ImVec2(pp_s.x,      pp_s.y),
                imgui.ImVec2(pp_s.x+aw_s, pp_s.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.75)), 10, 0, 1.2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##sizec", imgui.ImVec2(aw_s, cardH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                -- ŠØŠøŃ€ŠøŠ½Š°
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(14)))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd8\xe8\xf0\xe8\xed\xe0")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curWPct*100))
                imgui.SameLine(0,6)
                imgui.TextColored(iv4(0.45,0.48,0.55,1.0), string.format("(%.0fpx)", sw*curWPct))
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(44)))
                imgui.PushItemWidth(aw_s - S(32))
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 12)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sw2", winWbuf, WIN_W_MIN, 0.98)
                if winWbuf[0] < WIN_W_MIN then winWbuf[0] = WIN_W_MIN end
                cfg.winWPct = winWbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(5)
                imgui.PopItemWidth()

                -- Š’Ń‹Ń�Š¾Ń‚Š°
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(96)))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc2\xfb\xf1\xee\xf2\xe0")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curHPct*100))
                imgui.SameLine(0,6)
                imgui.TextColored(iv4(0.45,0.48,0.55,1.0), string.format("(%.0fpx)", sh*curHPct))
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(126)))
                imgui.PushItemWidth(aw_s - S(32))
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 12)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sh2", winHbuf, WIN_H_MIN, 0.98)
                if winHbuf[0] < WIN_H_MIN then winHbuf[0] = WIN_H_MIN end
                cfg.winHPct = winHbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(5)
                imgui.PopItemWidth()

            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ā”€ā”€ Š Š�Š—Š�Š•Š  ŠØŠ Š�Š¤Š¢Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xf8\xf0\xe8\xf4\xf2\xe0")
        do
            local curFS = cfg.fontSize > 0 and cfg.fontSize or 1.25
            fontSizeBuf[0] = curFS
            local dl_f = imgui.GetWindowDrawList()
            local pp_f = imgui.GetCursorScreenPos()
            local aw_f = imgui.GetContentRegionAvail().x
            local cardHf = S(94)
            dl_f:AddRectFilled(
                imgui.ImVec2(pp_f.x,      pp_f.y),
                imgui.ImVec2(pp_f.x+aw_f, pp_f.y+cardHf),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.10,g*0.10,b*0.10,0.92)), 10)
            dl_f:AddRect(
                imgui.ImVec2(pp_f.x,      pp_f.y),
                imgui.ImVec2(pp_f.x+aw_f, pp_f.y+cardHf),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.75)), 10, 0, 1.2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##fszc", imgui.ImVec2(aw_f, cardHf), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

                imgui.SetCursorPos(imgui.ImVec2(S(16), S(14)))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd8\xf0\xe8\xf4\xf2")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curFS*100))
                imgui.SameLine(0,6)
                -- ŠŗŠ½Š¾ŠæŠŗŠø -/+ Š´Š»Ń¸ Ń‚Š¾Ń‡Š½Š¾Š¹ Š½Š°Ń�Ń‚Ń€Š¾Š¹ŠŗŠø
                stepBtn("fs_minus", "-", function()
                    cfg.fontSize = math.max(FONT_SIZE_MIN, math.floor((cfg.fontSize - 0.05)*100+0.5)/100)
                    fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)
                imgui.SameLine(0,4)
                stepBtn("fs_plus", "+", function()
                    cfg.fontSize = math.min(FONT_SIZE_MAX, math.floor((cfg.fontSize + 0.05)*100+0.5)/100)
                    fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)
                imgui.SetCursorPos(imgui.ImVec2(S(16), S(48)))
                imgui.PushItemWidth(aw_f - S(32))
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                do local _sfc=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _sfc=_sfc+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _sfc=_sfc+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _sfc=_sfc+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 12)) then _sfc=_sfc+1 end
                if imgui.SliderFloat("##fsz2", fontSizeBuf, FONT_SIZE_MIN, FONT_SIZE_MAX) then
                    cfg.fontSize = math.floor(fontSizeBuf[0]*100+0.5)/100
                    saveCfg()
                end
                if _sfc>0 then pcall(imgui.PopStyleVar,_sfc) end end
                imgui.PopStyleColor(5)
                imgui.PopItemWidth()

            imgui.EndChild()
            imgui.PopStyleColor()
        end
        secTitle(u8"\xc3\xee\xf2\xee\xe2\xfb\xe5 \xf1\xf2\xe8\xeb\xe8")
        -- Edinyy spisok vseh presetov (temy + kombo), edinyy dizayn knopok,
        -- dubley po tsvetu aktsenta sredi presetov net (proverено vruchnuyu).
        -- Kazhdyy preset: {imya, accR,accG,accB, rowR,rowG,rowB, themeIdx (ili nil)}
        local ALL_STYLE_PRESETS = {
            {u8(THEMES[1].name), 0.43,0.71,1.0,  0.43*0.35,0.71*0.35,1.0*0.35,  1},
            {u8(THEMES[2].name), 0.30,0.85,0.45, 0.30*0.35,0.85*0.35,0.45*0.35, 2},
            {u8(THEMES[3].name), 1.0, 0.55,0.20, 1.0*0.35, 0.55*0.35,0.20*0.35, 3},
            {u8(THEMES[4].name), 0.75,0.45,1.0,  0.75*0.35,0.45*0.35,1.0*0.35,  4},
            {u8(THEMES[5].name), 1.0, 0.80,0.25, 1.0*0.35, 0.80*0.35,0.25*0.35, 5},
            {u8(THEMES[6].name), 1.0, 0.25,0.25, 1.0*0.35, 0.25*0.35,0.25*0.35, 6},
            {u8"\xce\xea\xe5\xe0\xed",         0.10,0.72,0.90, 0.05,0.35,0.55},  -- Ocean
            {u8"\xd0\xee\xe7\xe0",             0.98,0.35,0.65, 0.50,0.08,0.22},  -- Rose
            {u8"\xc4\xe6\xf3\xed\xe3\xeb\xe8", 0.35,0.88,0.55, 0.08,0.38,0.18},  -- Jungle
            {u8"\xc3\xf0\xee\xe7\xe0",         0.75,0.22,0.95, 0.28,0.05,0.42},  -- Thunder
            {u8"\xd5\xf0\xee\xec",             0.92,0.78,0.20, 0.42,0.32,0.04},  -- Chrome
            {u8"\xca\xf0\xee\xe2\xfc",         0.95,0.18,0.18, 0.42,0.04,0.04},  -- Blood
            {u8"\xd1\xed\xe5\xe3",             0.88,0.95,1.00, 0.22,0.38,0.52},  -- Snow
            {u8"\xd0\xf3\xf1\xf2\xfc",         0.60,0.88,0.35, 0.18,0.38,0.08},  -- Rust
        }
        do
            local pr0,pg0,pb0 = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr0*0.20,pg0*0.20,pb0*0.20,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr0*0.36,pg0*0.36,pb0*0.36,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr0*0.52,pg0*0.52,pb0*0.52,1.0))
            do local _pbs = prettyBtnPush(10.0)
            if imgui.Button(u8"\xc2\xfb\xe1\xf0\xe0\xf2\xfc \xf1\xf2\xe8\xeb\xfc \xee\xf4\xee\xf0\xec\xeb\xe5\xed\xe8\xff##openStylePopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(38))) then
                imgui.OpenPopup("##stylePickerPopup")
            end
            prettyBtnPop(_pbs) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(360), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            if imgui.BeginPopup("##stylePickerPopup") then
                imgui.TextColored(thDim(), u8"\xc2\xfb\xe1\xe5\xf0\xe8\xf2\xe5 \xf1\xf2\xe8\xeb\xfc \xee\xf4\xee\xf0\xec\xeb\xe5\xed\xe8\xff:")
                imgui.Spacing()
                local av_c  = imgui.GetContentRegionAvail().x
                local perRow = 3
                local gap    = 6
                local btnWC  = (av_c - (perRow-1)*gap) / perRow
                for i, cp in ipairs(ALL_STYLE_PRESETS) do
                    local col = (i-1) % perRow
                    if col > 0 then imgui.SameLine(0, gap) end
                    local cName = cp[1]
                    local aR,aG,aB = cp[2],cp[3],cp[4]
                    local bR,bG,bB = cp[5],cp[6],cp[7]
                    local themeIdx = cp[8]
                    local isAct
                    if themeIdx then
                        isAct = (cfg.theme == themeIdx and cfg.custR < 0)
                    else
                        isAct = math.abs((cfg.custR>=0 and cfg.custR or getTheme().acc[1])-aR)<0.01
                               and math.abs((cfg.custG>=0 and cfg.custG or getTheme().acc[2])-aG)<0.01
                               and math.abs((cfg.custB>=0 and cfg.custB or getTheme().acc[3])-aB)<0.01
                               and math.abs((cfg.rowBgR>=0 and cfg.rowBgR or aR)-bR)<0.01
                    end
                    local tip = u8"\xcf\xf0\xe5\xf1\xe5\xf2 \xab" .. cName .. u8"\xbb: \xed\xe0\xe6\xec\xe8\xf2\xe5, \xf7\xf2\xee\xe1\xfb \xef\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc"
                    if drawStyleSwatchButton("stylepreset"..i, cName, aR,aG,aB, bR,bG,bB, btnWC, 46, isAct, tip) then
                        if themeIdx then
                            cfg.theme=themeIdx; cfg.custR=-1; cfg.custG=-1; cfg.custB=-1
                        else
                            cfg.custR=aR; cfg.custG=aG; cfg.custB=aB
                            cfg.rowBgR=bR; cfg.rowBgG=bG; cfg.rowBgB=bB
                            custRbuf[0]=aR; custGbuf[0]=aG; custBbuf[0]=aB
                            rowBgRbuf[0]=bR; rowBgGbuf[0]=bG; rowBgBbuf[0]=bB
                        end
                        saveCfg()
                    end
                    if col == perRow-1 then imgui.Spacing() end
                end
                imgui.Spacing()
                do
                    local pr,pg,pb = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
                    do local _pbcs = prettyBtnPush(8.0)
                    if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeStylePopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                        imgui.CloseCurrentPopup()
                    end
                    prettyBtnPop(_pbcs) end
                    imgui.PopStyleColor(3)
                end
                imgui.EndPopup()
            end
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        secTitle(u8"\xd1\xe2\xee\xe9 \xf6\xe2\xe5\xf2 (RGB)")

        -- превью цвета + кнопка, которая открывает всплывающее окно с полноценным
        -- пикером цвета (вместо огромного встроенного пикера — короче, всё влезает в меню)
        do
            local pr,pg,pb = getAcc()
            local dl2  = imgui.GetWindowDrawList()
            local pp   = imgui.GetCursorScreenPos()
            local aw2  = imgui.GetContentRegionAvail().x
            local prevH = S(38)
            dl2:AddRectFilled(
                imgui.ImVec2(pp.x,    pp.y),
                imgui.ImVec2(pp.x+aw2, pp.y+prevH),
                imgui.ColorConvertFloat4ToU32(iv4(pr*0.16,pg*0.16,pb*0.16,1.0)), 10)
            dl2:AddRect(
                imgui.ImVec2(pp.x,    pp.y),
                imgui.ImVec2(pp.x+aw2, pp.y+prevH),
                imgui.ColorConvertFloat4ToU32(iv4(pr,pg,pb,0.95)), 10, 0, 1.8)
            dl2:AddRectFilled(
                imgui.ImVec2(pp.x+S(10),  pp.y+7),
                imgui.ImVec2(pp.x+S(34),  pp.y+prevH-7),
                imgui.ColorConvertFloat4ToU32(iv4(pr,pg,pb,1.0)), 6)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##prevclr", imgui.ImVec2(aw2, prevH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                imgui.SetCursorPos(imgui.ImVec2(S(44), (prevH-imgui.CalcTextSize("R").y)*0.5))
                imgui.TextColored(thAccBright(),
                    string.format("R=%.2f  G=%.2f  B=%.2f", pr, pg, pb))
            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()
        do
            local pr0,pg0,pb0 = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr0*0.20,pg0*0.20,pb0*0.20,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr0*0.36,pg0*0.36,pb0*0.36,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr0*0.52,pg0*0.52,pb0*0.52,1.0))
            do local _pba = prettyBtnPush(10.0)
            if imgui.Button(u8"\xc8\xe7\xec\xe5\xed\xe8\xf2\xfc \xf6\xe2\xe5\xf2 \xec\xe5\xed\xfe##openAccentPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(38))) then
                if cfg.custR < 0 then
                    local _a = getTheme().acc
                    custRbuf[0]=_a[1]; custGbuf[0]=_a[2]; custBbuf[0]=_a[3]
                end
                imgui.OpenPopup("##accentColorPopup")
            end
            prettyBtnPop(_pba) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            if imgui.BeginPopup("##accentColorPopup") then
                imgui.TextColored(thDim(), u8"\xc0\xea\xf6\xe5\xed\xf2\xed\xfb\xe9 \xf6\xe2\xe5\xf2 \xec\xe5\xed\xfe:")
                imgui.Spacing()
                if not _custPickerVec then
                    _custPickerVec = imgui.new("float[3]", {custRbuf[0], custGbuf[0], custBbuf[0]})
                end
                _custPickerVec[0], _custPickerVec[1], _custPickerVec[2] = custRbuf[0], custGbuf[0], custBbuf[0]
                local okPicker = pcall(function()
                    imgui.PushItemWidth(S(220))
                    local flags = 0
                    pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
                    if imgui.ColorPicker3("##accentpicker", _custPickerVec, flags) then
                        custRbuf[0], custGbuf[0], custBbuf[0] = _custPickerVec[0], _custPickerVec[1], _custPickerVec[2]
                        cfg.custR=custRbuf[0]; cfg.custG=custGbuf[0]; cfg.custB=custBbuf[0]
                        saveCfg()
                    end
                    imgui.PopItemWidth()
                end)
                if not okPicker then
                    imgui.PushItemWidth(150)
                    if imgui.SliderFloat("R##cr2", custRbuf, 0.0, 1.0) then
                        cfg.custR=custRbuf[0]; cfg.custG=custGbuf[0]; cfg.custB=custBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("G##cg2", custGbuf, 0.0, 1.0) then
                        cfg.custR=custRbuf[0]; cfg.custG=custGbuf[0]; cfg.custB=custBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("B##cb2", custBbuf, 0.0, 1.0) then
                        cfg.custR=custRbuf[0]; cfg.custG=custGbuf[0]; cfg.custB=custBbuf[0]; saveCfg()
                    end
                    imgui.PopItemWidth()
                end
                imgui.Spacing()
                do
                    local pr,pg,pb = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
                    do local _pbca = prettyBtnPush(8.0)
                    if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeAccentPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                        imgui.CloseCurrentPopup()
                    end
                    prettyBtnPop(_pbca) end
                    imgui.PopStyleColor(3)
                end
                imgui.EndPopup()
            end
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        secTitle(u8"\xd6\xe2\xe5\xf2 \xf4\xee\xed\xe0 \xf1\xf2\xf0\xee\xea")
        do
            if cfg.rowBgR < 0 then
                local _a2 = getTheme().acc
                rowBgRbuf[0]=_a2[1]; rowBgGbuf[0]=_a2[2]; rowBgBbuf[0]=_a2[3]
            end
            do
                local pr2,pg2,pb2 = getRowBgColor()
                local dl_rp = imgui.GetWindowDrawList()
                local pp_rp = imgui.GetCursorScreenPos()
                local aw_rp = imgui.GetContentRegionAvail().x
                local prevRpH = S(30)
                dl_rp:AddRectFilled(
                    imgui.ImVec2(pp_rp.x,     pp_rp.y),
                    imgui.ImVec2(pp_rp.x+aw_rp, pp_rp.y+prevRpH),
                    imgui.ColorConvertFloat4ToU32(iv4(pr2*0.13, pg2*0.13, pb2*0.13, 0.98)), 5)
                dl_rp:AddRect(
                    imgui.ImVec2(pp_rp.x,     pp_rp.y),
                    imgui.ImVec2(pp_rp.x+aw_rp, pp_rp.y+prevRpH),
                    imgui.ColorConvertFloat4ToU32(iv4(pr2*0.45, pg2*0.45, pb2*0.45, 0.40)), 5, 0, 0.7)
                imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
                imgui.BeginChild("##rowbgprev", imgui.ImVec2(aw_rp, prevRpH), false,
                    imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                    imgui.SetCursorPos(imgui.ImVec2(S(10), (prevRpH-imgui.CalcTextSize("R").y)*0.5))
                    local prevBgBright = (pr2*0.13)*0.299 + (pg2*0.13)*0.587 + (pb2*0.13)*0.114
                    local prevTxtCol = prevBgBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(0.95,0.95,0.98,1.0)
                    imgui.TextColored(prevTxtCol,
                        string.format(u8"\xcf\xf0\xe5\xe2\xfc\xfe: R=%.2f G=%.2f B=%.2f", pr2, pg2, pb2))
                imgui.EndChild()
                imgui.PopStyleColor()
            end
            imgui.Spacing()

            local pr0b,pg0b,pb0b = getAcc()
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr0b*0.20,pg0b*0.20,pb0b*0.20,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr0b*0.36,pg0b*0.36,pb0b*0.36,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr0b*0.52,pg0b*0.52,pb0b*0.52,1.0))
            do local _pbr = prettyBtnPush(10.0)
            if imgui.Button(u8"\xc8\xe7\xec\xe5\xed\xe8\xf2\xfc \xf6\xe2\xe5\xf2 \xf4\xee\xed\xe0 \xf1\xf2\xf0\xee\xea##openRowBgPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(38))) then
                imgui.OpenPopup("##rowBgColorPopup")
            end
            prettyBtnPop(_pbr) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            if imgui.BeginPopup("##rowBgColorPopup") then
                imgui.TextColored(thDim(), u8"\xd6\xe2\xe5\xf2 \xf4\xee\xed\xe0 \xf1\xf2\xf0\xee\xea:")
                imgui.Spacing()
                if not _rowBgPickerVec then
                    _rowBgPickerVec = imgui.new("float[3]", {rowBgRbuf[0], rowBgGbuf[0], rowBgBbuf[0]})
                end
                _rowBgPickerVec[0], _rowBgPickerVec[1], _rowBgPickerVec[2] = rowBgRbuf[0], rowBgGbuf[0], rowBgBbuf[0]
                local okPicker2 = pcall(function()
                    imgui.PushItemWidth(S(220))
                    local flags = 0
                    pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
                    if imgui.ColorPicker3("##rowbgpickerwidget", _rowBgPickerVec, flags) then
                        rowBgRbuf[0], rowBgGbuf[0], rowBgBbuf[0] = _rowBgPickerVec[0], _rowBgPickerVec[1], _rowBgPickerVec[2]
                        cfg.rowBgR=rowBgRbuf[0]; cfg.rowBgG=rowBgGbuf[0]; cfg.rowBgB=rowBgBbuf[0]
                        saveCfg()
                    end
                    imgui.PopItemWidth()
                end)
                if not okPicker2 then
                    imgui.PushItemWidth(150)
                    if imgui.SliderFloat("R##rbR", rowBgRbuf, 0.0, 1.0) then
                        cfg.rowBgR=rowBgRbuf[0]; cfg.rowBgG=rowBgGbuf[0]; cfg.rowBgB=rowBgBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("G##rbG", rowBgGbuf, 0.0, 1.0) then
                        cfg.rowBgR=rowBgRbuf[0]; cfg.rowBgG=rowBgGbuf[0]; cfg.rowBgB=rowBgBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("B##rbB", rowBgBbuf, 0.0, 1.0) then
                        cfg.rowBgR=rowBgRbuf[0]; cfg.rowBgG=rowBgGbuf[0]; cfg.rowBgB=rowBgBbuf[0]; saveCfg()
                    end
                    imgui.PopItemWidth()
                end
                imgui.Spacing()
                do
                    local pr,pg,pb = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
                    do local _pbcr = prettyBtnPush(8.0)
                    if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeRowBgPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                        imgui.CloseCurrentPopup()
                    end
                    prettyBtnPop(_pbcr) end
                    imgui.PopStyleColor(3)
                end
                imgui.EndPopup()
            end
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ── АВТО-ОБНОВЛЕНИЕ (перемещено сюда — в самый низ) ─────────
        secTitle(u8"\xc0\xe2\xf2\xee-\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5")
        -- НЕ перезаписываем chkBuf каждый кадр
        if imgui.Checkbox(u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc", chkBuf) then
            cfg.autoRefresh = chkBuf[0]
            saveCfg()
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))
        if imgui.Checkbox(u8"\xd1\xea\xf0\xfb\xe2\xe0\xf2\xfc \xee\xea\xed\xee \xf1\xf2\xe0\xf2\xee\xe2 \xf1\xe5\xf0\xe2\xe5\xf0\xe0", chkBuf2) then
            cfg.hideNativeStats = chkBuf2[0]
            saveCfg()
        end
        imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"  \xf7\xf2\xee\xe1\xfb \xed\xe0\xf2\xe8\xe2\xed\xee\xe5 \xee\xea\xed\xee /stats \xed\xe5 \xec\xe5\xeb\xfc\xea\xe0\xeb\xee \xef\xf0\xe8 \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe8")
        if cfg.autoRefresh then
            imgui.Spacing()
            imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc8\xed\xf2\xe5\xf0\xe2\xe0\xeb:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), cfg.autoInterval..u8" \xf1\xe5\xea")
            do
                imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
                imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
                imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 12)) then _svc2=_svc2+1 end
                if imgui.SliderFloat("##ai2", aBuf, 10.0, 300.0) then
                    cfg.autoInterval = math.floor(aBuf[0]+0.5); saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(5)
            end
        end

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()

    _resetSettScroll = false
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 4: Š˛ Š�Š�Š Š�Š�Š¢Š•  (Š²Ń�Šµ Š±Š»Š¾ŠŗŠø Ń� ŠŗŃ€Š°Ń�ŠøŠ²Š¾Š¹ Ń€Š°Š¼ŠŗŠ¾Š¹)
-- ============================================================
local function drawAbout(h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    -- ubrali NoScrollbar/NoScrollWithMouse: teper mozhno prokrutit koleskom
    -- myshi ili polosoy sprava, esli tekst ne pomeshchaetsya v okno
    imgui.BeginChild("##sabout", imgui.ImVec2(0,h), false)
    if _resetSettScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()
        local rra,rga,rba = getRowBgColor()
        local dl_a  = imgui.GetWindowDrawList()

        -- Š‘Š°Š½Š½ŠµŃ€
        imgui.Spacing()
        local bannerH = SFtext(86)
        local ps_a    = imgui.GetCursorScreenPos()
        local aw_a    = imgui.GetContentRegionAvail().x
        -- Š¤Š¾Š½ Š±Š°Š½Š½ŠµŃ€Š° Ń€ŠµŠ°Š³ŠøŃ€Ń�ŠµŃ‚ Š½Š° rowBg
        local banBgR = math.max(rra*0.22, 0.06)
        local banBgG = math.max(rga*0.22, 0.06)
        local banBgB = math.max(rba*0.22, 0.06)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(banBgR,banBgG,banBgB,1.0)), 14)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a*0.5, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(rra*0.10,rga*0.10,rba*0.10,0.5)), 14)
        -- Š±Š¾Š»ŠµŠµ Ń‚Š¾Š»Ń�Ń‚Š°Ń¸ Šø Ń¸Ń€ŠŗŠ°Ń¸ Š¾Š±Š²Š¾Š´ŠŗŠ° Š±Š°Š½Š½ŠµŃ€Š°
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 14, 0, 3.0)
        -- Š²Š½ŠµŃ�Š½ŠøŠ¹ Ń�Š²ŠµŃ‚ (glow effect)
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x-2,      ps_a.y-2),
            imgui.ImVec2(ps_a.x+aw_a+2, ps_a.y+bannerH+2),
            imgui.ColorConvertFloat4ToU32(iv4(r*0.70,g*0.70,b*0.70,0.45)), 16, 0, 1.5)
        -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+3),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
        -- Š½ŠøŠ¶Š½Ń¸Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y+bannerH-3),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.7)), 2)
        -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Š±Š°Š½Š½ŠµŃ€Š° Š´Š»Ń¸ Š°Š´Š°ŠæŃ‚Š°Ń†ŠøŠø Ń‚ŠµŠŗŃ�Ń‚Š°
        local banBright = banBgR*0.299 + banBgG*0.587 + banBgB*0.114
        local banTitleCol = banBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(1,1,1,1)

        imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
        imgui.BeginChild("##banner", imgui.ImVec2(aw_a, bannerH), false,
            imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
            local title1 = "PC Stats"
            local title2 = "v1.1.0  |  Arizona RP PC"
            local sz1 = imgui.CalcTextSize(title1)
            local sz2 = imgui.CalcTextSize(title2)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz1.x*0.5, SFtext(14)))
            imgui.TextColored(banTitleCol, title1)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz2.x*0.5, SFtext(44)))
            imgui.TextColored(thAccBright(), title2)
        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Spacing()

        -- Š�Š°Ń€Ń‚Š¾Ń‡ŠŗŠ° Ń€Š°Š·Ń€Š°Š±Š¾Ń‚Ń‡ŠøŠŗŠ°
        secTitle(u8"\xd0\xe0\xe7\xf0\xe0\xe1\xee\xf2\xf7\xe8\xea")
        infoCard("##devcard", 100, function(aw, ch)
            -- Š¯ŠøŠŗ
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(10)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcd\xe8\xea \xe2 \xe8\xe3\xf0\xe5:")
            imgui.SameLine(0,8)
            imgui.TextColored(thAccBright(), "Marco_Santiago")
            -- Š’ŠµŃ€Ń�ŠøŃ¸ + Š�Ń€Š¾ŠµŠŗŃ‚
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(40)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc2\xe5\xf0\xf1\xe8\xff:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v1.1.0")
            imgui.SameLine(0,14)
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcf\xf0\xee\xe5\xea\xf2:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.90,0.90,0.90,1.0), "Arizona RP PC")
            -- Š¢ŠøŠæ Ń�ŠŗŃ€ŠøŠæŃ‚Š°
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(70)))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0), "MoonLoader Lua Script")
        end)

        -- Š�Š°Ń€Ń‚Š¾Ń‡ŠŗŠ° Ń�Š²Ń¸Š·Šø ā€” Telegram Ń� ŠŗŠ¾Š¼ŠæŠ°ŠŗŃ‚Š½Š¾Š¹ ŠŗŠ½Š¾ŠæŠŗŠ¾Š¹
        secTitle(u8"\xd1\xe2\xff\xe7\xfc")
        infoCard("##tgcard", 100, function(aw, ch)
            -- "Telegram:" Š»ŠµŠ¹Š±Š» + Š½ŠøŠŗ + ŠŗŠ½Š¾ŠæŠŗŠ° ŠŗŠ¾ŠæŠøŃ€Š¾Š²Š°Ń‚Ń� Š½Š° Š¾Š´Š½Š¾Š¹ Ń�Ń‚Ń€Š¾ŠŗŠµ
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(14)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), "Telegram:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.18,0.75,0.98,1.0), "@Marco8877")
            imgui.SameLine(0,10)
            -- Š�Š¾Š¼ŠæŠ°ŠŗŃ‚Š½Š°Ń¸ ŠŗŠ½Š¾ŠæŠŗŠ° ŠŗŠ¾ŠæŠøŃ€Š¾Š²Š°Š½ŠøŃ¸
            do
                local tgHandle = "@Marco8877"
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.06,0.32,0.58,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.12,0.52,0.85,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.20,0.70,1.00,1.0))
                do local _pbtg = prettyBtnPush(7.0)
                if imgui.Button(u8"\xca\xee\xef\xe8\xf0##tgcopy", imgui.ImVec2(S(52), S(22))) then
                    local copied = false
                    pcall(function()
                        if imgui.SetClipboardText then
                            imgui.SetClipboardText(tgHandle)
                            copied = true
                        end
                    end)
                    -- teper' vsegda podtverzhdayem deystvie v chate, a ne tolko kogda
                    -- bufer obmena nedostupen
                    if copied then
                        pcall(sampAddChatMessage, "{00FF88}[MSW] \xd1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xee: " .. tgHandle, -1)
                    else
                        pcall(sampAddChatMessage, "{00CCFF}[MSW] Telegram: " .. tgHandle, -1)
                    end
                end
                prettyBtnPop(_pbtg) end
                imgui.PopStyleColor(3)
            end

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(48)))
            imgui.TextColored(iv4(1,1,1,1),
                u8"\xcf\xee \xe2\xf1\xe5\xec \xe2\xee\xef\xf1\xf0\xee\xf1\xe0\xec \xe8 \xef\xf0\xe5\xe4\xeb\xee\xe6\xe5\xed\xe8\xff\xec.")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(74)))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0),
                u8"\xd1\xea\xf0\xe8\xef\xf2: Arizona RP PC | MoonLoader")
        end)

        -- Š�Š°Ń€Ń‚Š¾Ń‡ŠŗŠ° Š¾ Ń�ŠŗŃ€ŠøŠæŃ‚Šµ
        secTitle(u8"\xce \xf1\xea\xf0\xe8\xef\xf2\xe5")
        local _descBullets = {
            u8"- \xf1\xe1\xee\xf0 \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe8 \xf7\xe5\xf0\xe5\xe7 /stats \xe2 \xee\xe4\xe8\xed \xea\xeb\xe8\xea, \xe2\xea\xeb\xfe\xf7\xe0\xff \xe0\xe2\xf2\xee-\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5 \xef\xee \xf2\xe0\xe9\xec\xe5\xf0\xf3",
            u8"- \xf1\xea\xf0\xfb\xf2\xe8\xe5 \xf0\xee\xe4\xed\xee\xe3\xee \xee\xea\xed\xe0 /stats \xf1\xe5\xf0\xe2\xe5\xf0\xe0, \xf7\xf2\xee\xe1\xfb \xe4\xe0\xed\xed\xfb\xe5 \xed\xe5 \xec\xe8\xe3\xe0\xeb\xe8 \xed\xe0 \xfd\xea\xf0\xe0\xed\xe5",
            u8"- \xe3\xe8\xe1\xea\xe0\xff \xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe0 \xf2\xe5\xec\xfb, \xe0\xea\xf6\xe5\xed\xf2\xed\xee\xe3\xee \xf6\xe2\xe5\xf2\xe0 \xe8 \xf6\xe2\xe5\xf2\xe0 \xf4\xee\xed\xe0 \xf1\xf2\xf0\xee\xea (\xe3\xee\xf2\xee\xe2\xfb\xe5 \xef\xf0\xe5\xf1\xe5\xf2\xfb \xe8\xeb\xe8 \xf1\xe2\xee\xe9 RGB)",
            u8"- \xe2\xea\xeb\xe0\xe4\xea\xe0 \xab\xd4\xe8\xed\xe0\xed\xf1\xfb\xbb: \xee\xe1\xf9\xe8\xe9 \xea\xe0\xef\xe8\xf2\xe0\xeb, \xf0\xe0\xe7\xe1\xe8\xe2\xea\xe0 \xef\xee \xf1\xf7\xe5\xf2\xe0\xec \xe8 \xea\xee\xed\xe2\xe5\xf0\xf2\xe0\xf6\xe8\xff \xe2\xe0\xeb\xfe\xf2 \xef\xee \xe2\xe0\xf8\xe8\xec \xea\xf3\xf0\xf1\xe0\xec",
            u8"- \xe2\xfb\xe1\xee\xf0, \xea\xe0\xea\xe8\xe5 \xf1\xf3\xec\xec\xfb \xe8 \xe2\xe0\xeb\xfe\xf2\xfb \xf3\xf7\xe8\xf2\xfb\xe2\xe0\xf2\xfc \xe2 \xee\xe1\xf9\xe5\xec \xe8\xf2\xee\xe3\xe5 \xab\xc2\xf1\xe5\xe3\xee \xe2\xe8\xf0\xf2\xee\xe2\xbb",
            u8"- \xe5\xe4\xe8\xed\xfb\xe9 \xf6\xe2\xe5\xf2 \xe4\xeb\xff \xe2\xf1\xe5\xf5 \xf6\xe8\xf4\xf0 \xf1\xea\xf0\xe8\xef\xf2\xe0 (\xef\xee \xe6\xe5\xeb\xe0\xed\xe8\xfe) \xe2 \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe0\xf5",
            u8"- \xe2\xf1\xe5 \xed\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf1\xee\xf5\xf0\xe0\xed\xff\xfe\xf2\xf1\xff \xe2 \xf4\xe0\xe9\xeb \xe8 \xef\xf0\xe8\xec\xe5\xed\xff\xfe\xf2\xf1\xff \xef\xf0\xe8 \xf1\xeb\xe5\xe4\xf3\xfe\xf9\xe5\xec \xe7\xe0\xef\xf3\xf1\xea\xe5",
        }
        -- Š²Ń‹Ń�Š¾Ń‚Š° ŠŗŠ°Ń€Ń‚Š¾Ń‡ŠŗŠø Š±Š°Š·Š¾Š²Š°Ń¸ ŠæŠ¾Š´ 2 Š²Ń�Ń‚Ń�ŠæŠ½Ń‹Ń… + Š·Š°Š³Š¾Š»Š¾Š²Š¾Šŗ + Š²Ń�Šµ Š±Ń�Š»Š»ŠµŃ‚Ń‹ + Š½ŠøŠ¶Š½ŠøŠ¹ Š¾Ń‚Ń�Ń‚Ń�Šæ,
        -- Ń‡Ń‚Š¾Š±Ń‹ ŠæŃ€Šø Š±Š¾Š»Ń�Ń¨Š¾Š¼ Ń€Š°Š·Š¼ŠµŃ€Šµ Ń¨Ń€ŠøŃ„Ń‚Š° Š½ŠøŃ‡ŠµŠ³Š¾ Š½Šµ Š¾Š±Ń€ŠµŠ·Š°Š»Š¾Ń�Ń�
        local _descCardH = 76 + (#_descBullets + 1) * 26
        infoCard("##desccard", _descCardH, function(aw, ch)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(14)))
            imgui.TextColored(iv4(1,1,1,1),
                u8"\xcf\xee\xeb\xed\xe0\xff \xe7\xe0\xec\xe5\xed\xe0 \xf1\xf2\xe0\xed\xe4\xe0\xf0\xf2\xed\xee\xe3\xee \xee\xea\xed\xe0 /stats.")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(38)))
            imgui.TextColored(iv4(1,1,1,1),
                u8"\xd1\xf7\xe8\xf2\xe0\xe5\xf2 \xee\xe1\xf9\xf3\xfe \xef\xf0\xe8\xe1\xfb\xeb\xfc \xe8 \xea\xe0\xef\xe8\xf2\xe0\xeb \xef\xf0\xff\xec\xee \xe2 \xf1\xea\xf0\xe8\xef\xf2\xe5, \xf1\xee \xe2\xf1\xe5\xec\xe8 \xe2\xe0\xeb\xfe\xf2\xe0\xec\xe8.")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(70)))
            imgui.TextColored(thAccBright(),
                u8"\xce\xf1\xed\xee\xe2\xed\xfb\xe5 \xf4\xf3\xed\xea\xf6\xe8\xe8 \xf1\xea\xf0\xe8\xef\xf2\xe0:")
            for i, bl in ipairs(_descBullets) do
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(70 + i*26)))
                imgui.TextColored(iv4(0.85,0.87,0.95,1.0), bl)
            end
        end)

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    _resetSettScroll = false
end

-- ============================================================
--  Š“Š›Š�Š’Š¯Š˛Š• Š˛Š�Š¯Š˛
-- ============================================================
imgui.OnFrame(
    function() return winOpen end,
    function(self)
        -- FIX: Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ Ń�Ń‡Ń‘Ń‚Ń‡ŠøŠŗŠø Ń�Š½ŠøŠŗŠ°Š»Ń�Š½Ń‹Ń… ID Š² Š½Š°Ń‡Š°Š»Šµ ŠŗŠ°Š¶Š´Š¾Š³Š¾ ŠŗŠ°Š´Ń€Š°
        _metricTileIdx = 0
        _chipIdx = 0
        chipSide = false
        local sw = imgui.GetIO().DisplaySize.x
        local sh = imgui.GetIO().DisplaySize.y

        -- Š°Š²Ń‚Š¾Š¼Š°Ń�Ń¨Ń‚Š°Š± Š²Ń�ŠµŠ³Š¾ UI ŠæŠ¾Š´ Ń‚ŠµŠŗŃ�Ń‰ŠµŠµ Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ (Š±Š°Š·Š° 1080p)
        if sh > 0 then
            UI_SCALE = math.max(UI_SCALE_MIN, math.min(UI_SCALE_MAX, sh / 1080.0))
        end

        -- ŠµŃ�Š»Šø Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ/Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ³Ń€Š¾Š²Š¾Š³Š¾ Š¾ŠŗŠ½Š° ŠøŠ·Š¼ŠµŠ½ŠøŠ»Š¾Ń�Ń� (Š²Ń‹Ń¨ŠµŠ» ŠøŠ· Š¾ŠŗŠ½Š° / Ń�Š¼ŠµŠ½ŠøŠ» Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ) ā€”
        -- Š·Š°Ń�Ń‚Š°Š²Š»Ń¸ŠµŠ¼ ŠæŠµŃ€ŠµŃ�Ń‡ŠøŃ‚Š°Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ¼ŠæŠ»Ń�Ń‚-Š¾ŠŗŠ½Š°, ŠøŠ½Š°Ń‡Šµ Cond.Once Š±Š¾Š»Ń�Ń¸Šµ Š½Šµ Š´Š°Ń�Ń‚ ŠµŠ¼Ń� ŠøŠ·Š¼ŠµŠ½ŠøŃ‚Ń�Ń�Ń¸
        if math.abs(sw - _lastSw) > 2 or math.abs(sh - _lastSh) > 2 then
            if _lastSw > 0 then _sw_win_init = nil end
            _lastSw, _lastSh = sw, sh
        end

        local wPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local hPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        local ww   = math.floor(sw * wPct)
        local wh   = math.floor(sh * hPct)
        -- Š¶Ń‘Ń�Ń‚ŠŗŠøŠµ Š³Ń€Š°Š½ŠøŃ†Ń‹, Ń‡Ń‚Š¾Š±Ń‹ Š¾ŠŗŠ½Š¾ Š½Šµ Ń�Ń‚Š°Š»Š¾ ŠŗŃ€Š¾Ń¨ŠµŃ‡Š½Ń‹Š¼ Š½Š° Š¼Š°Š»ŠµŠ½Ń�ŠŗŠøŃ… Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŃ¸Ń… (Š½Š°ŠæŃ€. 1280x720)
        -- ŠøŠ»Šø Š½Šµ Š²Ń‹Š»ŠµŠ·Š»Š¾ Š·Š° ŠæŃ€ŠµŠ´ŠµŠ»Ń‹ Ń�ŠŗŃ€Š°Š½Š° Š½Š° Ń�Š²ŠµŃ€Ń…Ń¨ŠøŃ€Š¾ŠŗŠøŃ… Š¼Š¾Š½ŠøŃ‚Š¾Ń€Š°Ń…
        ww = math.max(math.floor(sw * 0.30), math.min(ww, math.floor(sw * 0.98)))
        wh = math.max(math.floor(sh * 0.35), math.min(wh, math.floor(sh * 0.95)))

        if not _sw_win_init then
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(sw*0.5, sh*0.5), imgui.Cond.Always, imgui.ImVec2(0.5,0.5))
            _sw_win_init = true
        else
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Once)
        end

        applyStyle()
        -- Š¼Š°Ń�Ń�Ń‚Š°Š± Ń�Ń€ŠøŃ„Ń‚Š°: ŠæŃ€ŠøŠ¼ŠµŠ½Ń¸ŠµŠ¼ Ń‡ŠµŃ€ŠµŠ· SetWindowFontScale ŠæŠ¾Ń�Š»Šµ Begin
        -- Š¯Š° Š�Š� Š¾ŠŗŠ½Š¾ Š¼Š¾Š¶Š½Š¾ Š´Š²ŠøŠ³Š°Ń‚Ń� Šø Š¼ŠµŠ½Ń¸Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ Š¼Ń‹Ń�ŠŗŠ¾Š¹ (Š½Š° Š¼Š¾Š±ŠøŠ»Šµ Ń¨Ń‚Š¾
        -- Š±Ń‹Š»Š¾ Š¾Ń‚ŠŗŠ»ŃˇŃ‡ŠµŠ½Š¾, Ń‡Ń‚Š¾Š±Ń‹ Ń�Š»Ń�Ń‡Š°Š¹Š½Ń‹Šµ Ń‚Š°ŠæŃ‹ Š½Šµ Š´Š²ŠøŠ³Š°Š»Šø Š¾ŠŗŠ½Š¾ Š½Š° Ń‚Š°Ń‡Ń�ŠŗŃ€ŠøŠ½Šµ)
        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
        imgui.Begin("###sw", nil, flags)
        imgui.SetWindowFontScale(UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

        -- ā”€ā”€ Š�Š�Š�Š¢Š˛Š�Š¯Š«Š™ Š—Š�Š“Š˛Š›Š˛Š’Š˛Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        do
            local r0,g0,b0 = getAcc()
            local dl0 = imgui.GetWindowDrawList()
            local wp  = imgui.GetCursorScreenPos()
            local aw0 = imgui.GetContentRegionAvail().x
            local th0 = S(36)
            dl0:AddRectFilled(
                imgui.ImVec2(wp.x,      wp.y),
                imgui.ImVec2(wp.x+aw0,  wp.y+th0),
                imgui.ColorConvertFloat4ToU32(iv4(r0*0.12,g0*0.12,b0*0.12,1.0)), 10)
            dl0:AddRect(
                imgui.ImVec2(wp.x,      wp.y),
                imgui.ImVec2(wp.x+aw0,  wp.y+th0),
                imgui.ColorConvertFloat4ToU32(iv4(r0*0.55,g0*0.55,b0*0.55,0.60)), 10, 0, 1)
            dl0:AddRectFilled(
                imgui.ImVec2(wp.x,   wp.y+4),
                imgui.ImVec2(wp.x+4, wp.y+th0-4),
                imgui.ColorConvertFloat4ToU32(iv4(r0,g0,b0,1.0)), 2)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##titlebar", imgui.ImVec2(aw0, th0), false)
                local titleStr = u8"  PC Stats  v1.1.1"
                local tsz = imgui.CalcTextSize(titleStr)
                imgui.SetCursorPos(imgui.ImVec2(aw0*0.5 - tsz.x*0.5, (th0 - tsz.y)*0.5))
                imgui.TextColored(iv4(1,1,1,1), titleStr)
            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()

        -- ā”€ā”€ Š’Š�Š›Š�Š”Š�Š� (Š�Š�Š�Š«Š�Š� Š�Š•Š Š’Š«Š�Š�) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        do
            local av   = imgui.GetContentRegionAvail().x
            local nT   = 5
            local tw   = (av - (nT-1)*S(4)) / nT
            local tabDef = {
                { u8"\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6",    0.43,0.71,1.0  },
                { u8"\xc1\xee\xe9",                          1.0, 0.55,0.20 },
                { u8"\xd4\xe8\xed\xe0\xed\xf1\xfb",                  0.25,0.92,0.48 },
                { u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8", 0.75,0.75,0.80 },
                { u8"\xce \xf1\xea\xf0.",                    0.75,0.45,1.0  },
            }
            for i, td in ipairs(tabDef) do
                if i > 1 then imgui.SameLine(0,S(4)) end
                if tabButton(td[1], activeTab==i, tw, td[2],td[3],td[4]) then
                    if activeTab ~= i then _resetCharScroll = true; _resetSettScroll = true; accPopupOpen = false end
                    activeTab=i
                end
            end
        end

        -- Š´ŠµŠŗŠ¾Ń€Š°Ń‚ŠøŠ²Š½Š°Ń¸ Š»ŠøŠ½ŠøŃ¸ ŠæŠ¾Š´ Š²ŠŗŠ»Š°Š´ŠŗŠ°Š¼Šø
        do
            local r3,g3,b3 = getAcc()
            local dl3 = imgui.GetWindowDrawList()
            local ps  = imgui.GetCursorScreenPos()
            local aw3 = imgui.GetContentRegionAvail().x
            dl3:AddRectFilled(
                imgui.ImVec2(ps.x,     ps.y+2),
                imgui.ImVec2(ps.x+aw3, ps.y+3),
                imgui.ColorConvertFloat4ToU32(iv4(r3*0.45,g3*0.45,b3*0.45,0.60)))
        end
        imgui.Spacing()

        -- ā”€ā”€ ŠØŠ�Š�Š�Š� Š�Š•Š Š�Š˛Š¯Š�Š–Š� (Ń‚Š¾Š»Ń�ŠŗŠ¾ Š½Š° Š²ŠŗŠ»Š°Š´ŠŗŠµ 1) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        if activeTab == 1 and statsData and statsData.name ~= "" then
            local r2,g2,b2 = getAcc()
            local rr2,rg2,rb2 = getRowBgColor()
            local dl2 = imgui.GetWindowDrawList()
            local ph  = imgui.GetCursorScreenPos()
            local aw  = imgui.GetContentRegionAvail().x
            local hdrH = S(60)
            -- Ń„Š¾Š½ Ń�Š°ŠæŠŗŠø: Ń€ŠµŠ°Š³ŠøŃ€Ń�ŠµŃ‚ Š½Š° rowBg
            local hdrBgR = math.max(rr2*0.22, 0.06)
            local hdrBgG = math.max(rg2*0.22, 0.06)
            local hdrBgB = math.max(rb2*0.22, 0.06)
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(hdrBgR,hdrBgG,hdrBgB,0.97)), 12)
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw*0.6, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(rr2*0.10,rg2*0.10,rb2*0.10,0.40)), 12)
            dl2:AddRect(
                imgui.ImVec2(ph.x,    ph.y),
                imgui.ImVec2(ph.x+aw, ph.y+hdrH),
                imgui.ColorConvertFloat4ToU32(iv4(r2*0.60,g2*0.60,b2*0.60,0.80)), 12, 0, 1.4)
            -- Š»ŠµŠ²Š°Ń¸ Š°ŠŗŃ†ŠµŠ½Ń‚Š½Š°Ń¸ ŠæŠ¾Š»Š¾Ń�Š°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,   ph.y+6),
                imgui.ImVec2(ph.x+4, ph.y+hdrH-6),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,1.0)), 2)
            -- Š²ŠµŃ€Ń…Š½Ń¸Ń¸ Ń‚Š¾Š½ŠŗŠ°Ń¸ ŠæŠ¾Š»Š¾Ń�ŠŗŠ°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x+12,    ph.y),
                imgui.ImVec2(ph.x+aw-12, ph.y+2),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,0.85)), 2)
            -- Ń¸Ń€ŠŗŠ¾Ń�Ń‚Ń� Ń„Š¾Š½Š° Ń�Š°ŠæŠŗŠø Š´Š»Ń¸ Š°Š´Š°ŠæŃ‚Š°Ń†ŠøŠø Ń†Š²ŠµŃ‚Š° Ń‚ŠµŠŗŃ�Ń‚Š°
            local hdrBright = hdrBgR*0.299 + hdrBgG*0.587 + hdrBgB*0.114
            local hdrLabelCol = hdrBright > 0.35 and iv4(0.10,0.10,0.15,1.0) or thDim()
            local hdrTextCol  = hdrBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(0.48,0.48,0.55,1.0)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##hdr", imgui.ImVec2(aw, hdrH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                -- Š�Ń‚Ń€Š¾ŠŗŠ° 1: Š�Š•Š Š�Š˛Š¯Š�Š– + ŠøŠ¼Ń¸ + Š½Š¾Š¼ŠµŃ€ Š°ŠŗŠŗŠ°Ń�Š½Ń‚Š°
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(6)))
                imgui.TextColored(hdrLabelCol, u8"\xcf\xc5\xd0\xd1\xce\xcd\xc0\xc6")
                imgui.SameLine(0,7)
                imgui.TextColored(thAccBright(), u8(statsData.name))
                if statsData.accountNumber~="" then
                    imgui.SameLine(0,7)
                    imgui.TextColored(hdrTextCol, "["..statsData.accountNumber.."]")
                end
                -- Š�Ń‚Ń€Š¾ŠŗŠ° 2: Š£Ń€. + EXP + HP
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(28)))
                if statsData.level~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), u8"\xd3\xf0.")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thGold(), u8(statsData.level))
                    imgui.SameLine(0,14)
                end
                if statsData.respect~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "EXP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thAcc(), u8(statsData.respect))
                    imgui.SameLine(0,14)
                end
                if statsData.health~="" then
                    local hp    = tonumber((statsData.health or ""):match("%d+")) or 100
                    local maxhp = tonumber((statsData.health or ""):match("/(%d+)")) or 100
                    local hcol  = hp>=80 and thGreen() or hp>=40 and thGold() or thRed()
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "HP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(hcol, u8(statsData.health))
                    -- Š¼ŠøŠ½Šø HP-Š±Š°Ń€
                    imgui.SameLine(0,S(10))
                    local bw2 = S(80)
                    local bp  = imgui.GetCursorScreenPos()
                    local dl3 = imgui.GetWindowDrawList()
                    local bh2 = S(10)
                    imgui.SetCursorPos(imgui.ImVec2(imgui.GetCursorPosX(), imgui.GetCursorPosY()+3))
                    dl3:AddRectFilled(
                        imgui.ImVec2(bp.x,        bp.y+3),
                        imgui.ImVec2(bp.x+bw2,    bp.y+3+bh2),
                        imgui.ColorConvertFloat4ToU32(iv4(0.12,0.12,0.14,0.90)), 5)
                    local pct = math.max(0, math.min(1, hp / math.max(1, maxhp)))
                    local fc  = pct>=0.8 and iv4(0.20,0.88,0.40,0.95) or pct>=0.4 and iv4(0.95,0.75,0.10,0.95) or iv4(0.95,0.22,0.22,0.95)
                    if pct > 0 then
                        dl3:AddRectFilled(
                            imgui.ImVec2(bp.x,           bp.y+3),
                            imgui.ImVec2(bp.x+bw2*pct,   bp.y+3+bh2),
                            imgui.ColorConvertFloat4ToU32(fc), 5)
                    end
                    imgui.Dummy(imgui.ImVec2(bw2, bh2))
                end

            imgui.EndChild()
            imgui.PopStyleColor()
            imgui.Spacing()

        end

        -- Ń�Ń‚Š°Ń‚Ń�Ń� Š·Š°Š³Ń€Ń�Š·ŠŗŠø
        if waitingStats then
            imgui.TextColored(thGold(), u8"  \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            imgui.Spacing()
        elseif statusMsg ~= "" and statusMsg ~= u8"\xc3\xee\xf2\xee\xe2\xee" then
            imgui.TextColored(thGold(), "  "..statusMsg)
            imgui.Spacing()
        end

        -- ā”€ā”€ Š�Š•Š¢Š Š�Š�Š� (Ń‚Š¾Š»Ń�ŠŗŠ¾ Š²ŠŗŠ»Š°Š´ŠŗŠø 1-2) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        if statsData and activeTab <= 2 then
            local s    = statsData
            local av   = imgui.GetContentRegionAvail().x
            local hasAZ = hasVal(s.azCoins) or hasVal(s.accountState)
            local nTiles = hasAZ and 4 or 3
            local mw   = (av - (nTiles-1)*4) / nTiles
            local cashVal  = s.cashSas~="" and fmtMoney(s.cashSas) or "-"
            local bankVal  = s.bank~="" and fmtMoney(s.bank) or "-"
            local depVal   = s.moneyDay~="" and fmtMoney(s.moneyDay) or "-"
            local azVal    = hasVal(s.accountState) and u8(s.accountState) or (hasVal(s.azCoins) and u8(s.azCoins) or "-")
            metricTile(u8"\xcd\xe0\xeb. SA$", cashVal, thGreen(), mw, function()
                pcall(sampAddChatMessage, "{00FF88}[MSW] \xcd\xe0\xeb. SA$: " .. cashVal, -1)
            end)
            imgui.SameLine(0,4)
            metricTile(u8"\xc1\xe0\xed\xea", bankVal, thAcc(), mw, function()
                pcall(sampAddChatMessage, "{00AAFF}[MSW] \xc1\xe0\xed\xea: " .. bankVal, -1)
            end)
            imgui.SameLine(0,4)
            metricTile(u8"\xc4\xe5\xef\xee\xe7\xe8\xf2", depVal, thGold(), mw, function()
                pcall(sampAddChatMessage, "{FFD700}[MSW] \xc4\xe5\xef\xee\xe7\xe8\xf2: " .. depVal, -1)
            end)
            if hasAZ then
                imgui.SameLine(0,4)
                metricTile("AZ-Coins", azVal, thGold(), mw, function()
                    pcall(sampAddChatMessage, "{FFD700}[MSW] AZ-Coins: " .. azVal, -1)
                end)
            end
            imgui.Spacing()
        end

        -- ā”€ā”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        local contentH = imgui.GetContentRegionAvail().y - 46 - 20

        if activeTab == 4 then
            drawSettings(contentH, sw, sh)
        elseif activeTab == 5 then
            drawAbout(contentH)
        elseif activeTab == 3 and statsData then
            drawTotal(statsData, contentH)
        elseif not statsData then
            imgui.Spacing()
            if waitingStats then
                imgui.TextColored(thGold(), u8"  \xc7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            elseif statusMsg ~= "" then
                imgui.TextColored(thGold(), "  "..statusMsg)
            else
                imgui.TextColored(thDim(), u8"  \xcd\xe0\xe6\xec\xe8\xf2\xe5 \"\xce\xe1\xed\xee\xe2\xe8\xf2\xfc\" \xe4\xeb\xff \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe8 \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe8")
            end
        else
            local s = statsData
            if     activeTab == 1 then drawChar(s, contentH)
            elseif activeTab == 2 then drawBattle(s, contentH)
            end
        end

        imgui.Spacing()
        if activeTab == 4 then
            imgui.Dummy(imgui.ImVec2(0, S(10)))
        end

        -- ā”€ā”€ Š¯Š�Š–Š¯Š�Š• Š�Š¯Š˛Š�Š�Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        local r4,g4,b4 = getAcc()
        do
            if activeTab == 5 then
                -- Š’ŠŗŠ»Š°Š´ŠŗŠ° "Š¾ Ń�ŠŗŃ€ŠøŠæŃ‚Šµ": Š¢Š¾Š»Ń�ŠŗŠ¾ Š—Š°ŠŗŃ€Ń‹Ń‚Ń� (Š²Š¾ Š²Ń�Ńˇ Ń¨ŠøŃ€ŠøŠ½Ń�, Š±ŠµŠ· ŠŗŠ½Š¾ŠæŠŗŠø Š�Š±Š½Š¾Š²ŠøŃ‚Ń�)
                local awClose = imgui.GetContentRegionAvail().x
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
                if imgui.Button(u8"  \xc7\xe0\xea\xf0\xfb\xf2\xfc  ", imgui.ImVec2(awClose, S(40))) then
                    winOpen=false; activeTab=1; _sw_win_init=nil
                end
                imgui.PopStyleColor(3)
            else
                local bw = (imgui.GetContentRegionAvail().x - 6) * 0.5
                if activeTab == 4 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� + Š—Š°ŠŗŃ€Ń‹Ń‚Ń�
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.12,0.12,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.78,0.18,0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(1.0, 0.25,0.25,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc \xe2\xf1\xb8  ", imgui.ImVec2(bw, S(40))) then
                        cfg.winWPct    = 0.60; cfg.winHPct   = 0.76
                        cfg.custR      = -1;   cfg.custG      = -1;   cfg.custB = -1
                        cfg.rowBgR     = -1;   cfg.rowBgG     = -1;   cfg.rowBgB= -1
                        cfg.fontSize   = 1.25
                        winWbuf[0]=0.60; winHbuf[0]=0.76
                        fontSizeBuf[0] = 1.25
                        local a = getTheme().acc
                        custRbuf[0]=a[1]; custGbuf[0]=a[2]; custBbuf[0]=a[3]
                        rowBgRbuf[0]=a[1]; rowBgGbuf[0]=a[2]; rowBgBbuf[0]=a[3]
                        _sw_win_init=nil; saveCfg()
                    end
                    imgui.PopStyleColor(3)
                elseif activeTab == 3 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š¤ŠøŠ½Š°Š½Ń�Ń‹: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� ŠŗŃ�Ń€Ń�Š° Š²Š°Š»Ń�Ń‚ (Š²Š¼ŠµŃ�Ń‚Š¾ Š�Š±Š½Š¾Š²ŠøŃ‚Ń�)
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.35,0.05,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.75,0.50,0.08,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.95,0.65,0.12,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1 \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2  ", imgui.ImVec2(bw, S(40))) then
                        cfg.rateAZ = 35000.0; cfg.rateBTC = 0.0; cfg.rateEUR = 0.0
                        cfg.rateVC = 1.0;     cfg.rateASC = 112.0
                        rateAZBuf[0]  = 35000; rateBTCBuf[0] = 0; rateEURBuf[0] = 0
                        rateVCBuf[0]  = 1;     rateASCBuf[0] = 112
                        _cefLastResult = ""
                        saveCfg()
                        pcall(sampAddChatMessage, "{FFAA00}[Stats] \xea\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2 \xf1\xe1\xf0\xee\xf8\xe5\xed\xfb \xea \xe7\xed\xe0\xf7\xe5\xed\xe8\xff\xec \xef\xee \xf3\xec\xee\xeb\xf7\xe0\xed\xe8\xfe", -1)
                    end
                    imgui.PopStyleColor(3)
                else
                    -- ŠŸŠµŃ€Ń�Š¾Š½Š°Š¶/Š‘Š¾Ń¹: ŠŗŠ½Š¾ŠæŠŗŠ° Š˛Š±Š½Š¾Š²ŠøŃ‚Ń�
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(r4*0.18,g4*0.18,b4*0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r4*0.40,g4*0.40,b4*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r4*0.62,g4*0.62,b4*0.62,1.0))
                    if imgui.Button(u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc  ", imgui.ImVec2(bw, S(40))) then
                        requestStats()
                    end
                    imgui.PopStyleColor(3)
                end
                imgui.SameLine(0,6)
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
                if imgui.Button(u8"  \xc7\xe0\xea\xf0\xfb\xf2\xfc  ", imgui.ImVec2(bw, S(40))) then
                    winOpen=false; activeTab=1; _sw_win_init=nil
                end
                imgui.PopStyleColor(3)
            end
        end

        do
            local okP, p = pcall(imgui.GetWindowPos)
            local okS, s = pcall(imgui.GetWindowSize)
            if okP and okS then _mainWinPos, _mainWinSize = p, s end
        end
        imgui.End()

        drawFinanceSettingsPanel()
    end
)

-- ============================================================
--  Š—Š�Š�Š Š˛Š� Š�Š¢Š�Š¢Š�Š�Š¢Š�Š�Š�
-- ============================================================
function requestStats()
    if waitingStats then return end
    if not isSampAvailable() then
        statusMsg = u8"\xd1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    waitingStats    = true
    captureStarted  = false
    lastReqTime     = now()
    lastTdTime      = now()
    tdCollector     = {}
    tdCollectorSize = 0
    -- statsData Š¯Š• Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ ā€” Ń�Ń‚Š°Ń€Ń‹Šµ Š´Š°Š½Š½Ń‹Šµ Š²ŠøŠ´Š½Ń‹ ŠæŠ¾ŠŗŠ° Š½Šµ ŠæŠ¾Š»Ń�Ń‡ŠøŠ¼ Š½Š¾Š²Ń‹Šµ
    statusMsg       = u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
    lua_thread.create(function()
        wait(300)
        local ok, err = pcall(sampSendChat, "/stats")
        if not ok then
            waitingStats = false
            statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xea\xee\xec\xe0\xed\xe4\xfb: " .. tostring(err)
        end
    end)
end

local function finalize()
    if not waitingStats or finalizing then return end
    finalizing = true
    -- Š·Š°Ń‰ŠøŃ‚Š° Š¾Ń‚ ŠæŃ�Ń�Ń‚Š¾Š³Š¾ ŠŗŠ¾Š»Š»ŠµŠŗŃ‚Š¾Ń€Š°
    if next(tdCollector) == nil then
        waitingStats = false
        finalizing = false  -- Š˛Š‘ŠÆŠ—Š�Š¢Š•Š›Š¬Š¯Š˛ Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ Ń„Š»Š°Š³!
        return
    end
    local rows={}
    for _,td in pairs(tdCollector) do table.insert(rows,td) end
    table.sort(rows, function(a,b)
        local ay = tonumber(a.y) or 0
        local by2 = tonumber(b.y) or 0
        local ax = tonumber(a.x) or 0
        local bx = tonumber(b.x) or 0
        if math.abs(ay - by2) < 5 then return ax < bx end
        return ay < by2
    end)
    local lines,seen={},{}
    for _,td in ipairs(rows) do
        local t=trim(td.text)
        if t~="" and not seen[t]
            and t~="\xcf\xf0\xe5\xe4\xec\xe5\xf2\xfb"
            and t~="\xc7\xe0\xea\xf0\xfb\xf2\xfc" then
            seen[t]=true; table.insert(lines,t)
        end
    end
    local raw=table.concat(lines,"\n")
    if raw~="" then
        statsData=parseStats(raw)
        statusMsg=u8"\xc3\xee\xf2\xee\xe2\xee"
    else
        statusMsg=u8"\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5"
    end
    waitingStats=false; captureStarted=false; tdCollector={}; tdCollectorSize=0
    finalizing = false
end

-- ============================================================
--  Š˛Š‘Š Š�Š‘Š˛Š¢Š§Š�Š�Š� SAMP
-- ============================================================
function sampev.onShowDialog(id, style, title, btn1, btn2, text)
    -- ── автообновление курса валют через телефон: перехватываем диалоги,
    -- пока идёт навигация (см. fetchRatesViaCEF/_phoneFetchState) ──
    if _phoneFetchState then
        local handled = false
        pcall(function()
            local tT = tostring(title or "")
            local tX = tostring(text or "")
            phoneDebugLog(("id=%s style=%s title=%s text=%s")
                :format(tostring(id), tostring(style), stripColor(tT), stripColor(tX):sub(1, 80)))

            if _phoneFetchState == "opening" then
                -- сразу пробуем распознать курсы (вдруг открылся не список, а сразу нужный экран)
                if parsePhoneRatesText(tX) then
                    _phoneFetchState = nil
                    _cefLastResult = u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] " .. u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                    pcall(sampCloseCurrentDialog, -1)
                    handled = true
                    return
                end
                local idx = findPhoneListItem(tX, {
                    u8"\xf4\xe8\xed\xe0\xed\xf1", u8"\xe1\xe0\xed\xea", u8"\xea\xee\xf8\xe5\xeb\xb8\xea",
                })
                if idx then
                    _phoneFetchState = "in_menu"
                    pcall(sampSendDialogResponse, id, 1, idx, "")
                    handled = true
                end
            elseif _phoneFetchState == "in_menu" then
                if parsePhoneRatesText(tX) then
                    _phoneFetchState = nil
                    _cefLastResult = u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] " .. u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                    pcall(sampCloseCurrentDialog, -1)
                    handled = true
                    return
                end
                local idx = findPhoneListItem(tX, {
                    u8"\xea\xf3\xf0\xf1", u8"\xe2\xe0\xeb\xfe\xf2", u8"\xee\xe1\xec\xe5\xed",
                })
                if idx then
                    _phoneFetchState = "in_rates"
                    pcall(sampSendDialogResponse, id, 1, idx, "")
                    handled = true
                else
                    -- нужного пункта нет в этом меню — прекращаем и закрываем диалог,
                    -- чтобы не оставить телефон открытым поверх интерфейса игрока
                    _phoneFetchState = nil
                    _cefFetching = false
                    _cefLastResult = u8"\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xef\xf3\xed\xea\xf2 \\\"\xca\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2\\\" \xe2 \xec\xe5\xed\xfe \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{FF9900}[Stats] " .. u8"\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xef\xf3\xed\xea\xf2 \xec\xe5\xed\xfe \xf1 \xea\xf3\xf0\xf1\xee\xec \xe2\xe0\xeb\xfe\xf2, \xe2\xea\xeb\xfe\xf7\xe8\xf2\xe5 \xeb\xee\xe3 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2 \xe4\xeb\xff \xee\xf2\xeb\xe0\xe4\xea\xe8", -1)
                    pcall(sampCloseCurrentDialog, -1)
                    handled = true
                end
            elseif _phoneFetchState == "in_rates" then
                local got = parsePhoneRatesText(tX)
                _phoneFetchState = nil
                if got then
                    _cefLastResult = u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] " .. u8"\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                else
                    _cefLastResult = u8"\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xf2\xe5\xea\xf1\xf2 \xf1 \xea\xf3\xf0\xf1\xe0\xec\xe8"
                    pcall(sampAddChatMessage, "{FF6666}[Stats] " .. u8"\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xf1\xef\xee\xe7\xed\xe0\xf2\xfc \xea\xf3\xf1\xf0\xfb \xe2 \xf2\xe5\xea\xf1\xf2\xe5 \xe4\xe8\xe0\xeb\xee\xe3\xe0. \xc2\xea\xeb\xfe\xf7\xe8\xf2\xe5 \\\"\xcf\xee\xea\xe0\xe7\xfb\xe2\xe0\xf2\xfc \xeb\xee\xe3 \xe4\xe8\xe0\xeb\xee\xe3\xee\xe2\\\" \xe8 \xef\xf0\xe8\xf8\xeb\xe8\xf2\xe5 \xec\xed\xe5 \xf2\xe5\xea\xf1\xf2, \xf7\xf2\xee \xf2\xe0\xec \xe1\xfb\xeb\xee - \xef\xee\xe4\xef\xf0\xe0\xe2\xeb\xfe \xf0\xe0\xe7\xe1\xee\xf0.", -1)
                end
                pcall(sampCloseCurrentDialog, -1)
                handled = true
            end
        end)
        if handled then
            if _phoneFetchState == nil then _cefFetching = false end
            return false
        end
    end

    local isStatsDialog = false
    pcall(function()
        local tT  = tostring(title or "")
        local tX  = tostring(text or "")
        local tTl = tT:lower()
        local isStatsTitle = tTl:find("\xf1\xf2\xe0\xf2") or tTl:find("stat")
                          or tTl:find("\xce\xf1\xed\xee\xe2\xed\xe0\xff \xf1\xf2\xe0\xf2")
        if isStatsTitle or isStatsPiece(tX) then
            local cleaned = stripColor(tX)
            if isStatsPiece(cleaned) or (isStatsTitle and cleaned~="") then
                -- Ń�ŠŗŃ€Ń‹Š²Š°ŠµŠ¼ Š´ŠøŠ°Š»Š¾Š³ ŠµŃ�Š»Šø Ń�ŠŗŃ€ŠøŠæŃ‚ Ń�Š°Š¼ ŠµŠ³Š¾ Š·Š°ŠæŃ€Š¾Ń�ŠøŠ»
                if waitingStats then isStatsDialog = true end
                statsData       = parseStats(cleaned)
                statusMsg       = u8"\xc3\xee\xf2\xee\xe2\xee"
                waitingStats    = false
                tdCollector     = {}
                tdCollectorSize = 0
            end
        end
    end)
    if isStatsDialog and cfg.hideNativeStats then
        -- zakryvaem rodnoy dialog srazu, chtoby igrok ego ne uvidel na ekrane
        pcall(sampCloseCurrentDialog, -1)
        return false
    end
end

function sampev.onShowTextDraw(id, data)
    -- Š¾Š±Ń€Š°Š±Š°Ń‚Ń‹Š²Š°ŠµŠ¼ Š¢Š˛Š›Š¬Š�Š˛ ŠŗŠ¾Š³Š´Š° Š°ŠŗŃ‚ŠøŠ²Š½Š¾ Š¶Š´Ń‘Š¼ Š¾Ń‚Š²ŠµŃ‚ /stats
    if not waitingStats then return end
    local hidden = false
    pcall(function()
        local raw = tostring((data and data.text) or "")
        local cl  = trim(stripColor(raw))
        if cl=="" or looksTexture(cl) then return end
        local x,y = 0,0
        if data then
            if type(data.position)=="table" then
                x=tonumber(data.position.x) or 0; y=tonumber(data.position.y) or 0
            elseif tonumber(data.x) then
                x=tonumber(data.x) or 0; y=tonumber(data.y) or 0
            end
        end
        if x > 550 then return end
        local matched = isStatsPiece(cl)
        if matched then captureStarted=true end
        local inZone  = x>=-10 and x<=550 and y>=-10 and y<=1200
        if matched or (captureStarted and inZone) then
            -- Š·Š°Ń‰ŠøŃ‚Š° Š¾Ń‚ ŠæŠµŃ€ŠµŠæŠ¾Š»Š½ŠµŠ½ŠøŃ¸: ŠøŃ�ŠæŠ¾Š»Ń�Š·Ń�ŠµŠ¼ Ń�Ń‡Ń‘Ń‚Ń‡ŠøŠŗ Š²Š¼ŠµŃ�Ń‚Š¾ pairs()
            if tdCollectorSize == nil then tdCollectorSize = 0 end
            if tdCollectorSize < 300 then
                if not tdCollector[id] then tdCollectorSize = tdCollectorSize + 1 end
                tdCollector[id]={id=id,x=x,y=y,text=cl}; lastTdTime=now()
            end
            if cfg.hideNativeStats then
                -- pryachem realnyy tekst textdrawa, chtoby on ne migal na ekrane
                pcall(sampTextdrawSetString, id, " ")
                hidden = true
            end
        end
    end)
    if hidden then return false end
end

function sampev.onSetTextDraw(id, data)
    -- Š¢Š˛Š›Š¬Š�Š˛ Š²Š¾ Š²Ń€ŠµŠ¼Ń¸ Š°ŠŗŃ‚ŠøŠ²Š½Š¾Š³Š¾ Š·Š°ŠæŃ€Š¾Ń�Š°
    if not waitingStats then return end
    local hidden = false
    pcall(function()
        if not tdCollector[id] then return end
        if not data or not data.text then return end
        local raw = tostring((data and data.text) or "")
        local cl  = trim(stripColor(raw))
        if cl=="" or looksTexture(cl) then return end
        tdCollector[id].text=cl; lastTdTime=now()
        if cfg.hideNativeStats then
            pcall(sampTextdrawSetString, id, " ")
            hidden = true
        end
    end)
    if hidden then return false end
end

-- ============================================================
--  MAIN
-- ============================================================
function main()
    -- 1. Š�Š½Š°Ń‡Š°Š»Š° Š³Ń€Ń�Š·ŠøŠ¼ ŠŗŠ¾Š½Ń„ŠøŠ³
    loadCfg()

    -- 2. Š�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·ŠøŃ€Ń�ŠµŠ¼ Š²Ń�Šµ Š±Ń�Ń„ŠµŃ€Ń‹
    winWbuf[0] = cfg.winWPct > 0 and cfg.winWPct or 0.60
    winHbuf[0] = cfg.winHPct > 0 and cfg.winHPct or 0.76
    if cfg.custR >= 0 then
        custRbuf[0] = cfg.custR
        custGbuf[0] = cfg.custG
        custBbuf[0] = cfg.custB
    else
        local a = getTheme().acc
        custRbuf[0] = a[1]; custGbuf[0] = a[2]; custBbuf[0] = a[3]
    end
    -- Ń�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·Š°Ń†ŠøŃ¸ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
    if cfg.rowBgR >= 0 then
        rowBgRbuf[0] = cfg.rowBgR
        rowBgGbuf[0] = cfg.rowBgG
        rowBgBbuf[0] = cfg.rowBgB
    else
        local a = getTheme().acc
        rowBgRbuf[0] = a[1]; rowBgGbuf[0] = a[2]; rowBgBbuf[0] = a[3]
    end
    chkBuf[0] = cfg.autoRefresh
    chkBuf2[0] = cfg.hideNativeStats
    aBuf[0]   = cfg.autoInterval
    fontSizeBuf[0] = cfg.fontSize > 0 and cfg.fontSize or 1.25

    -- 3. Š–Š´Ń‘Š¼ SAMP ā€” Š±ŠµŠ· Š»ŠøŃ�Š½ŠøŃ… Š·Š°Š´ŠµŃ€Š¶ŠµŠŗ
    repeat wait(100) until isSampAvailable()

    -- 4. Š ŠµŠ³ŠøŃ�Ń‚Ń€ŠøŃ€Ń�ŠµŠ¼ ŠŗŠ¾Š¼Š°Š½Š´Ń�
    sampRegisterChatCommand("sw", function()
        if not isSampAvailable() then return end
        winOpen = not winOpen
        if winOpen then
            _sw_win_init = nil
            requestStats()
        else
            activeTab = 1
        end
    end)

    -- 5. Š�Š¾Š¾Š±Ń‰ŠµŠ½ŠøŠµ Š² Ń‡Š°Ń‚ ā€” Š¶Š´Ń‘Š¼ Š Š•Š�Š›Š¬Š¯Š«Š™ Ń�ŠæŠ°Š²Š½ ŠøŠ³Ń€Š¾ŠŗŠ°
    lua_thread.create(function()
        for _i = 1, 120 do
            wait(500)
            local spawned = false
            pcall(function()
                local ok, res = pcall(function()
                    return sampIsLocalPlayerSpawned and sampIsLocalPlayerSpawned()
                end)
                if ok and res then spawned = true end
            end)
            if spawned then break end
        end
        wait(2000)
        pcall(sampAddChatMessage,
            "{00FF88}[MSW v1.1.0] {FFFFFF}PC Stats | Cmd: {00FF88}/sw", -1)
    end)

    -- 6. Š“Š»Š°Š²Š½Ń‹Š¹ Ń†ŠøŠŗŠ» ā€” Š² Š¾Ń‚Š´ŠµŠ»Ń�Š½Š¾Š¼ ŠæŠ¾Ń‚Š¾ŠŗŠµ, main() Š·Š°Š²ŠµŃ€Ń�Š°ŠµŃ‚Ń�Ń¸
    lastAutoTime = now()
    while true do
        wait(100)

        if waitingStats then
            local dt = now() - lastTdTime
            local dr = now() - lastReqTime
            if next(tdCollector) ~= nil and captureStarted and dt >= TD_DELAY then
                local ok2, err2 = pcall(finalize)
                if not ok2 then
                    waitingStats    = false
                    tdCollector     = {}
                    tdCollectorSize = 0
                    statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xef\xe0\xf0\xf1\xe8\xed\xe3\xe0"
                    pcall(sampAddChatMessage, "{FF6666}[MSW] finalize err: " .. tostring(err2), -1)
                end
            elseif dr >= REQ_TIMEOUT then
                waitingStats    = false
                tdCollector     = {}
                tdCollectorSize = 0
                if not statsData then
                    statusMsg = u8"\xcd\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc"
                end
            end
        end

        if cfg.autoRefresh and winOpen and statsData then
            if now() - lastAutoTime >= cfg.autoInterval then
                lastAutoTime = now()
                requestStats()
            end
        end
    end
end

function onScriptTerminate(s, q)
    if s == thisScript() then saveCfg() end
end
