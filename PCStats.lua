script_name("PC Stats")
script_description("Statistika personazha | Arizona PC | by Marco_Santiago (PC port)")
script_author("Marco_Santiago")
script_version("1.1.6")

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

-- opcionalnaya biblioteka dlya HTTP-zaprosov (nuzhna tolko dlya zhivoy
-- zagruzki kursov valyut s arz-wiki.com po knopke "Obnovit' kursy");
-- esli ne ustanovlena - skript prosto pokazhet ob etom soobshchenie i
-- prodolzhit rabotat' na vstroennoy tablitse kursov (ARZ_WIKI_RATES)
local _httpLib = safeRequire("requests")

-- opcionalnaya biblioteka effil - nuzhna, chtoby proverka/skachivanie
-- obnovleniy s GitHub shli v otdelnom OS-potoke i NE zaveshivali igru
-- poka zhdyom otvet servera; esli effil ne ustanovlen - avtomaticheski
-- otkatyvaemsya na staryy sinhronnyy sposob (httpGetGithub nizhe)
local effil = safeRequire("effil")

-- Šµť�Š»Šø inicfg Š½Šµ Š·Š°Š³ť€ť�Š·ŠøŠ»ť�ť¸ ĥ€” Š·Š°Š³Š»ť�ť�ŠŗŠ° ť‥ť‥Š¾Š±ť‹ Š½Šµ Šŗť€Š°ť�Š½ť�ť‥ť�
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
--  Š�Š˛Š¯Š¤Š�Š‥
-- ============================================================
local CFG_FILE = "moonloader/config/PCStats.ini"
local cfg = {
    theme        = 1,
    autoRefresh  = false,
    autoInterval = 30,
    winWPct      = 0.0,
    winHPct      = 0.0,
    -- ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Šµ ť†Š²Šµť‥Š° Š°Šŗť†ŠµŠ½ť‥Š° (R,G,B 0..1)
    custR = -1, custG = -1, custB = -1,
    -- ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Š¹ ť†Š²Šµť‥ ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ (R,G,B 0..1, -1 = Š°Š²ť‥Š¾ Š¾ť‥ Š°Šŗť†ŠµŠ½ť‥Š°)
    rowBgR  = -1, rowBgG = -1, rowBgB = -1,
    -- Š¼Š°ť�ť�ť‥Š°Š± ť�ť€Šøť„ť‥Š° (0.7 .. 2.0, default 1.0)
    fontSize = 1.25,
    -- Šŗť�ť€ť�ť‹ Š¾Š±Š¼ŠµŠ½Š° Š²Š°Š»ť�ť‥ Š² SA$ Š·Š° 1 ŠµŠ´. (Š´Š»ť¸ Š²ŠŗŠ»Š°Š´ŠŗŠø "Š’ť�ŠµŠ³Š¾")
    rateAZ  = 35000.0,
    rateBTC = 0.0,
    rateEUR = 0.0,
    rateVC  = 0.0,
    -- ASC ne chitaetsya avtomaticheski iz staty servera, kolichestvo vvoditsya vruchnuyu
    ascAmount = 0.0,
    rateASC   = 0.0,
    -- imya servera Arizona RP dlya avtoobnovleniya kursov s arz-wiki.com (sm. fetchArzWikiRates)
    vcServerName = "Tucson",
    -- opredelyat' server avtomaticheski (po hostname/IP tekushchego SAMP-servera),
    -- a ne vvodit' vruchnuyu
    vcAutoDetectServer = true,
    -- pryatat rodnoe okno /stats servera poka skript schitivaet dannye (chtoby ne migalo)
    hideNativeStats = true,
    -- vkladka "Finansy": dvuhkolonochnyy rezhim (nalichnye/bank/depozit/scheta slева, valyuty ѥправа)
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
        cfg.rateVC        = tonumber(data.main.rateVC) or 0.0
        cfg.ascAmount     = tonumber(data.main.ascAmount) or 0.0
        cfg.rateASC       = tonumber(data.main.rateASC) or 0.0
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

-- Š�Š¾Š»ť�ť‥Šøť‥ť� Š°Šŗť†ŠµŠ½ť‥Š½ť‹Š¹ ť†Š²Šµť‥ (ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Š¹ ŠøŠ»Šø ŠøŠ· ť‥ŠµŠ¼ť‹)
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

-- Š�Š¾Š»ť�ť‥Šøť‥ť� ť†Š²Šµť‥ ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ dataRow (R,G,B)
local function getRowBgColor()
    if cfg.rowBgR >= 0 then
        return cfg.rowBgR, cfg.rowBgG, cfg.rowBgB
    end
    local r,g,b = getAcc()
    return r, g, b
end
-- Š�Š¾Š²Š¼Šµť�ť‥ŠøŠ¼Š¾ť�ť‥ť�: alpha Š¾Š±Š²Š¾Š´ŠŗŠø ť‥ŠµŠŗť�ť‥Š° (Š´Š»ť¸ Š¼Šµť�ť‥ Š³Š´Šµ Š½ť�Š¶Š½Š¾ Š¾Š´Š½Š¾ ť‥Šøť�Š»Š¾)
local function getTextBorderA()
    return 0.85
end

-- ============================================================
--  AUTO UI SCALE (masshtabirovanie pod razreshenie ekrana)
-- ============================================================
 local St = {}  -- consolidated frame-state table (keeps OnFrame's upvalue count under LuaJIT's 60 limit)
St.UI_SCALE      = 1.0   -- pereschityvaetsya kazhdyi kadr po DisplaySize
 St.UI_SCALE_MIN  = 0.88
 St.UI_SCALE_MAX  = 1.65
 St._lastSw, St._lastSh = 0, 0  -- poslednie izvestnye razmery ekrana (detekt smeny razresheniya)

local function S(n)
    return math.floor(n * St.UI_SCALE + 0.5)
end
local function Sf(n)
    return n * St.UI_SCALE
end
-- kak S(), no dopolnitelno uchityvaet polzovatelskiy razmer shrifta (cfg.fontSize),
-- nuzhen dlya blokov s zharestko zadannymi otstupami mezhdu strokami teksta
-- (vkladka "O skripte"), gde pri uvelichenii shrifta stroki nachinali nalezat
-- drug na druga i obrezalis ramkoy kartochki
local function SFtext(n)
    local fs = (cfg.fontSize and cfg.fontSize > 0) and cfg.fontSize or 1.25
    return math.floor(n * St.UI_SCALE * fs + 0.5)
end

-- ============================================================
--  Š�Š˛Š�Š¢Š˛ŠÆŠ¯Š�Š•
-- ============================================================
 St.winOpen        = false
 St.activeTab      = 1
 St.waitingStats   = false
local captureStarted = false
local TD_DELAY       = 0.8
local REQ_TIMEOUT    = 7.0
local lastReqTime    = 0.0
local lastTdTime     = 0.0
local tdCollector    = {}
local tdCollectorSize = 0
 St.statsData      = nil
 St.statusMsg      = ""
local lastAutoTime   = 0.0
local finalizing     = false
_sw_win_init         = nil
local accExpanded    = false
 St.accPopupOpen   = false
local _accBtnScreenPos = nil  -- ŠæŠ¾Š·Šøť†Šøť¸ ŠŗŠ½Š¾ŠæŠŗŠø ť�ť‥Šµť‥Š¾Š² Š² ť�Š°ŠæŠŗŠµ
-- Š¯Š° Š�Š� ť�Šŗť€Š¾Š»Š» Š½Š°ť‥ŠøŠ²Š½ť‹Š¹ (ŠŗŠ¾Š»Šµť�Š¾ Š¼ť‹ť�Šø / ŠæŠ¾Š»Š¾ť�Š° Šæť€Š¾Šŗť€ť�ť‥ŠŗŠø), ť€ť�ť‥Š½Š¾Šµ Š¾ť‥ť�Š»ŠµŠ¶ŠøŠ²Š°Š½ŠøŠµ
-- ŠæŠ¾Š·Šøť†ŠøŠø ť�Šŗť€Š¾Š»Š»Š° Šø Š²Šøť€ť‥ť�Š°Š»ť�Š½ť‹Šµ Š´Š¶Š¾Š¹ť�ť‥ŠøŠŗŠø (Š½ť�Š¶Š½ť‹Šµ Š½Š° ť‥Š°ť‥ť�Šŗť€ŠøŠ½Šµ) Š±Š¾Š»ť�ť�Šµ Š½Šµ Š½ť�Š¶Š½ť‹.
-- Š•Š´ŠøŠ½ť�ť‥Š²ŠµŠ½Š½Š¾Šµ, ť‥ť‥Š¾ Š½ť�Š¶Š½Š¾ ť�Š¾ť…ť€Š°Š½Šøť‥ť� ĥ€” ť�Š±ť€Š¾ť� ť�Šŗť€Š¾Š»Š»Š° Š² 0 Šæť€Šø ť�Š¼ŠµŠ½Šµ Š²ŠŗŠ»Š°Š´ŠŗŠø.
 St._resetCharScroll = false
 St._resetSettScroll = false

-- Š±ť�ť„Šµť€ť‹ Š´Š»ť¸ ť€ť�ť‥Š½Š¾Š³Š¾ Š²Š²Š¾Š´Š° RGB Š² Š½Š°ť�ť‥ť€Š¾Š¹ŠŗŠ°ť…
 St.custRbuf = imgui.new.float(1.0)
 St.custGbuf = imgui.new.float(0.5)
 St.custBbuf = imgui.new.float(0.2)

-- Š±ť�ť„Šµť€ť‹ ť†Š²Šµť‥Š° ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ (R,G,B)
local _custPickerVec  = nil
local _rowBgPickerVec = nil
 St.rowBgRbuf = imgui.new.float(0.43)
 St.rowBgGbuf = imgui.new.float(0.71)
 St.rowBgBbuf = imgui.new.float(1.0)

-- bufery dlya globalnogo cveta cifr + sostoyanie razvorota paneli v Nastroykah
local globalNumRbuf   = imgui.new.float(1.0)
local globalNumGbuf   = imgui.new.float(1.0)
local globalNumBbuf   = imgui.new.float(1.0)
local globalNumOnBuf  = imgui.new.bool(false)
local _globalNumColorExpanded = false

-- ============================================================
--  Š£Š¢Š�Š›Š�Š¢Š«
-- ============================================================
-- Š�Šµť�Šøť€ť�ŠµŠ¼ socket Š¾Š´ŠøŠ½ ť€Š°Š· Šæť€Šø ť�ť‥Š°ť€ť‥Šµ, Š½Šµ Š²ť‹Š·ť‹Š²Š°ŠµŠ¼ require ŠŗŠ°Š¶Š´ť‹Š¹ ť‥ŠøŠŗ
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
    -- s ť�Š¶Šµ Š´Š¾Š»Š¶Š½Š° ť�Š¾Š´Šµť€Š¶Š°ť‥ť� ť‥Š¾Š»ť�ŠŗŠ¾ ť†Šøť„ť€ť‹
    s = tostring(s or ""):gsub("%D","")
    if s=="" then return "0" end
    if #s<4 then return s end
    -- Š Š°Š·Š±ŠøŠ²Š°ŠµŠ¼ ť�Šæť€Š°Š²Š° Š³ť€ť�ŠæŠæŠ°Š¼Šø ŠæŠ¾ 3:
    -- reverse -> Š²ť�ť‥Š°Š²Šøť‥ť� ť‥Š¾ť‥Šŗť� Š�Š˛Š�Š›Š• ŠŗŠ°Š¶Š´ť‹ť… 3 ť†Šøť„ť€ -> reverse -> ť�Š±ť€Š°ť‥ť� Š½Š°ť‥Š°Š»ť�Š½ť�ťˇ ť‥Š¾ť‥Šŗť� Šµť�Š»Šø Šµť�ť‥ť�
    local rev = s:reverse()
    local out = rev:gsub("(%d%d%d)", "%1.")
    -- ť�Š±Šøť€Š°ŠµŠ¼ ť‥Š¾ť‥Šŗť� Š² ŠŗŠ¾Š½ť†Šµ (Š¾Š½Š° ť�ť‥Š°Š»Š° Š±ť‹ Š² Š½Š°ť‥Š°Š»Šµ ŠæŠ¾ť�Š»Šµ reverse)
    if out:sub(-1)=="." then out = out:sub(1,-2) end
    local result = out:reverse()
    -- ť�Š±Šøť€Š°ŠµŠ¼ ť‥Š¾ť‥Šŗť� Š² Š½Š°ť‥Š°Š»Šµ Šµť�Š»Šø Š²Š´ť€ť�Š³ Š¾ť�ť‥Š°Š»Š°ť�ť�
    if result:sub(1,1)=="." then result = result:sub(2) end
    return result
end

local function fmtMoney(v)
    if v == nil then return "-" end
    local s = trim(stripBrackets(tostring(v)))
    if s=="" or s=="-" then return "-" end
    local neg = s:match("^%-")
    -- Š•ť�Š»Šø ť�ť‥ť€Š¾ŠŗŠ° ť�Š¾Š´Šµť€Š¶Šøť‥ 'e' ŠøŠ»Šø 'E' ĥ€” ť¨ť‥Š¾ Š½Š°ť�ť‥Š½Š°ť¸ Š½Š¾ť‥Š°ť†Šøť¸, ŠŗŠ¾Š½Š²Šµť€ť‥Šøť€ť�ŠµŠ¼ ť‥Šµť€ŠµŠ· tonumber
    if s:find("[eE]") then
        local n = tonumber(s)
        if n then s = string.format("%.0f", math.abs(n))
        else s = "0" end
    else
        -- Š£Š±Šøť€Š°ŠµŠ¼ Š²ť�ť‥ Š½Šµť†Šøť„ť€Š¾Š²Š¾Šµ (ť‥Š¾ť‥ŠŗŠø, Šæť€Š¾Š±ŠµŠ»ť‹, Š·Š½Š°ŠŗŠø ĥ€” ť€Š°Š·Š´ŠµŠ»Šøť‥ŠµŠ»Šø ť�Š¶Šµ ť�ť‥Š¾ť¸ť‥ ŠøŠ»Šø Š½Šµť‥)
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
    -- ГЛХВНОЕ ХХХРХВЛЕНХЕ: ранѥѥе при неѥколѥких точках поѥледняя грѥппа
    -- из 3 цифр оѥибочно принималаѥѥ за дробнѥю чаѥтѥ и "ѥѥедалаѥѥ" —
    -- из-за этого ѥѥммы вида 45.000.000.000 показывалиѥѥ как 45.000.000.
    -- Теперѥ: еѥли поѥледний ѥегмент поѥле точки ѥоѥтоит РОВНО из 3 цифр
    -- (типичный признак разделителя тыѥяч) — вѥе точки ѥчитаютѥя
    -- разделителями тыѥяч. Хначе поѥледняя точка — это деѥятичный разделителѥ
    -- (например "103.78" AZ или "572.53" VC$), а более ранние точки (еѥли
    -- еѥтѥ) — разделители тыѥяч.
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

-- Š¥ť�Š¼Š¼Š° Š²Š°Š»ť�ť‥ť‹: ť†ŠµŠ»Š¾Šµ Šµť�Š»Šø Š±ŠµŠ· Š´ť€Š¾Š±Š½Š¾Š¹ ť‥Š°ť�ť‥Šø, ŠøŠ½Š°ť‥Šµ 2 Š·Š½Š°ŠŗŠ° ŠæŠ¾ť�Š»Šµ Š·Š°Šæť¸ť‥Š¾Š¹
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
-- Š�ť€ŠøŠ¼ŠµŠ½ť¸ŠµŠ¼ ť�ť‥ŠøŠ»ť� Š³Š»Š¾Š±Š°Š»ť�Š½Š¾ ť‥Šµť€ŠµŠ· GetStyle() ĥ€” ŠŗŠ°Šŗ MarketHelper, Š±ŠµŠ· Push/Pop ť�Š¾Š²ť�ŠµŠ¼
local function applyStyle()
    local s   = imgui.GetStyle()
    local r,g,b = getAcc()
    local t   = getTheme()
    local C   = s.Colors
    -- Š·Š°Š´Š½ŠøŠ¹ ť„Š¾Š½ ĥ€” ť‥ť‥ť€Š½ť‹Š¹ (WindowBg ŠæŠ¾Š»Š½Š¾ť�ť‥ť�ťˇ ť‥ť‥ť€Š½ť‹Š¹)
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
    -- Š¾Š±Š²Š¾Š´ŠŗŠ° Š¾ŠŗŠ½Š° ĥ€” Š¾ť‥ Š°Šŗť†ŠµŠ½ť‥Š°
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
    -- ť‥Š¾Š»ť‰ŠøŠ½Š° ť€Š°Š¼ŠŗŠø Š¾ŠŗŠ½Š° (Š½Šµ Š¼Š°ť�ť¨ť‥Š°Š±Šøť€ť�ŠµŠ¼ Š½ŠøŠ¶Šµ 1px, ŠøŠ½Š°ť‥Šµ Šæť€Š¾ŠæŠ°Š´Š°Šµť‥)
    s.WindowBorderSize = math.max(1.0, Sf(1.2))
    s.ChildBorderSize  = 0.0
end

-- ============================================================
--  UI Š�Š˛Š�Š�Š˛Š¯Š•Š¯Š¢Š«
-- ============================================================

-- Š—Š°Š³Š¾Š»Š¾Š²Š¾Šŗ ť�ŠµŠŗť†ŠøŠø ť� Š»ŠµŠ²Š¾Š¹ ŠæŠ¾Š»Š¾ť�Š¾Š¹
local function secTitle(title)
    imgui.Spacing()
    local r,g,b = getAcc()
    local dl    = imgui.GetWindowDrawList()
    local p     = imgui.GetCursorScreenPos()
    local avail = imgui.GetContentRegionAvail().x
    local h     = S(30)
    -- ť„Š¾Š½: Š¼ŠøŠ½ŠøŠ¼ť�Š¼ 0.10 ť¸ť€ŠŗŠ¾ť�ť‥Šø ť‥ť‥Š¾Š±ť‹ Š±ť‹Š» Š²ŠøŠ´ŠµŠ½ Š½Š° ť‥ť‥ť€Š½Š¾Š¼
    local br = math.max(r*0.22, 0.10)
    local bg2 = math.max(g*0.22, 0.10)
    local bb  = math.max(b*0.22, 0.10)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(br,bg2,bb,0.97)), 5)
    -- ť€Š°Š¼ŠŗŠ° ť�ŠµŠŗť†ŠøŠø
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

-- ĥ–ŗ Š�ť€Š°ť�ŠøŠ²Š°ť¸ ŠŗŠ°ť€ť‥Š¾ť‥ŠŗŠ°-Š¾Š±ť‥ť€ť‥ŠŗŠ° (ť�Šŗť€ŠøŠ½ť�Š¾ť‥ 3 ĥ€” Š²ť�Šµ Š±Š»Š¾ŠŗŠø ť� ť€Š°Š¼ŠŗŠ¾Š¹)
local function infoCard(id, cardH, drawFn)
    cardH = SFtext(cardH)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    local aw = imgui.GetContentRegionAvail().x
    -- ť„Š¾Š½ ŠŗŠ°ť€ť‥Š¾ť‥ŠŗŠø: ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Š¹ ť†Š²Šµť‥ ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ
    local bgR = math.max(rr*0.15, 0.08)
    local bgG = math.max(rg*0.15, 0.08)
    local bgB = math.max(rb*0.15, 0.08)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- ť€Š°Š¼ŠŗŠ° ť� Š°Šŗť†ŠµŠ½ť‥Š½ť‹Š¼ ť†Š²Šµť‥Š¾Š¼
    dl:AddRect(
        imgui.ImVec2(p.x,    p.y),
        imgui.ImVec2(p.x+aw, p.y+cardH),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.60,g*0.60,b*0.60,0.90)), 10, 0, 1.5)
    -- Š²Šµť€ť…Š½ť¸ť¸ Š°Šŗť†ŠµŠ½ť‥Š½Š°ť¸ ŠæŠ¾Š»Š¾ť�ŠŗŠ°
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
--  Š�Š›Š�Š� ŠŸŠž ŠŸŠ ŠžŠ˥Š—Š’ŠžŠ›Š¬ŠĄŠ˥ (klik po tekstu/cifram -> smena cveta)
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

        -- пробѥем полноценный визѥалѥный пикер (квадрат наѥыщенноѥти + вертикалѥная
        -- полоѥа тона + hex-поле), как в ѥтандартном ImGui color picker
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
            -- запаѥной вариант (обычные ползѥнки), еѥли ColorPicker3 недоѥтѥпен в этой ѥборке mimgui
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
    -- ť„Š¾Š½ ť�ť‥ť€Š¾ŠŗŠø: Šøť�ŠæŠ¾Š»ť�Š·ť�ŠµŠ¼ ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Š¹ ť†Š²Šµť‥ ť„Š¾Š½Š° (rowBg) ť� ť‥Šµť€ŠµŠ´Š¾Š²Š°Š½ŠøŠµŠ¼ ť¸ť€ŠŗŠ¾ť�ť‥Šø
    local shade = (_rowIndex % 2 == 0) and 0.13 or 0.07
    local minV  = (_rowIndex % 2 == 0) and 0.10 or 0.05
    local bgR = math.max(rr*shade, minV)
    local bgG = math.max(rg*shade, minV)
    local bgB = math.max(rb*shade, minV)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.98)), 5)
    -- ť‥Š¾Š½ŠŗŠ°ť¸ ť€Š°Š¼ŠŗŠ° ť�ť‥ť€Š¾ŠŗŠø Š¾ť‥ Š°Šŗť†ŠµŠ½ť‥Š°
    dl:AddRect(
        imgui.ImVec2(p.x,       p.y),
        imgui.ImVec2(p.x+avail, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(r*0.45,g*0.45,b*0.45,0.40)), 5, 0, 0.7)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+3),
        imgui.ImVec2(p.x+2, p.y+h-3),
        imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.85)), 1)
    -- ť¸ť€ŠŗŠ¾ť�ť‥ť� ť„Š¾Š½Š° ť�ť‥ť€Š¾ŠŗŠø ĥ€” Šµť�Š»Šø ť�Š²Šµť‥Š»ť‹Š¹ ť„Š¾Š½, Š´ŠµŠ»Š°ŠµŠ¼ ť‥ŠµŠŗť�ť‥ ť‥ť‥Š¼Š½ť‹Š¼
    local bgBright = bgR*0.299 + bgG*0.587 + bgB*0.114
    local labelCol = bgBright > 0.35 and iv4(0.05,0.05,0.08,1.0) or iv4(0.95,0.95,0.98,1.0)
    -- Š´Š»ť¸ valColor ť‥Š¾Š¶Šµ Šæť€Š¾Š²Šµť€ť¸ŠµŠ¼: Šµť�Š»Šø Š½Šµ Š·Š°Š´Š°Š½ ť¸Š²Š½Š¾ ĥ€” Š°Š²ť‥Š¾
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
    local baseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
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

 St._metricTileIdx = 0
local function metricTile(label, value, col, w, onClickFn)
    St._metricTileIdx = St._metricTileIdx + 1
    local h  = S(56)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local p  = imgui.GetCursorScreenPos()
    -- ť„Š¾Š½ ť‥Š°Š¹Š»Š°
    local bgR = math.max(rr*0.18, 0.09)
    local bgG = math.max(rg*0.18, 0.09)
    local bgB = math.max(rb*0.18, 0.09)
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
    -- ť€Š°Š¼ŠŗŠ°
    dl:AddRect(
        imgui.ImVec2(p.x,   p.y),
        imgui.ImVec2(p.x+w, p.y+h),
        imgui.ColorConvertFloat4ToU32(iv4(
            math.max(r*0.65,0.22), math.max(g*0.65,0.22), math.max(b*0.65,0.22), 0.85)),
        10, 0, 1.5)
    -- Š»ŠµŠ²Š°ť¸ Š°Šŗť†ŠµŠ½ť‥Š½Š°ť¸ ŠæŠ¾Š»Š¾ť�Š°
    local ac = col or thAcc()
    dl:AddRectFilled(
        imgui.ImVec2(p.x,   p.y+6),
        imgui.ImVec2(p.x+3, p.y+h-6),
        imgui.ColorConvertFloat4ToU32(iv4(ac.x,ac.y,ac.z,1.0)), 2)

    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##mt"..tostring(St._metricTileIdx), imgui.ImVec2(w, h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

        -- Š�Š½Š¾ŠæŠŗŠ° ť�Šæť€Š°Š²Š° (Šµť�Š»Šø Šµť�ť‥ť�) ĥ€” ť€Šøť�ť�ŠµŠ¼ ŠæŠµť€Š²Š¾Š¹ ť‥ť‥Š¾Š±ť‹ Š·Š½Š°ť‥ť� Šµť‥ ť�Šøť€ŠøŠ½ť�
        local btnW = onClickFn and S(44) or 0
        local btnH = S(32)
        if onClickFn then
            imgui.SetCursorPos(imgui.ImVec2(w - btnW - S(6), (h - btnH)*0.5))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.25,g*0.25,b*0.25,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.65,g*0.65,b*0.65,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r,      g,      b,      1.0))
            do local _sv=0
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,Sf(7.0)) then _sv=_sv+1 end
            -- ť�ŠøŠ¼Š²Š¾Š» "ŠæŠ¾Š´ŠµŠ»Šøť‥ť�ť�ť¸/ŠŗŠ¾ŠæŠøť€Š¾Š²Š°ť‥ť�": ť�ť‥ť€ŠµŠ»ŠŗŠ° Š²Š²Šµť€ť…
            if imgui.Button(">>##cp"..tostring(St._metricTileIdx),
                            imgui.ImVec2(btnW, btnH)) then
                pcall(onClickFn)
            end
            if _sv>0 then pcall(imgui.PopStyleVar,_sv) end end
            imgui.PopStyleColor(3)
        end

        -- Š›ŠµŠ¹Š±Š» (ť�Š²Šµť€ť…ť� ť�Š»ŠµŠ²Š°)
        local textAreaW = w - btnW - S(14)
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(7)))
        imgui.TextColored(thDim(), label)

        -- Š—Š½Š°ť‥ŠµŠ½ŠøŠµ (ť�Š½ŠøŠ·ť� ť�Š»ŠµŠ²Š°, Šŗť€ť�ŠæŠ½ŠµŠµ)
        local valStr = u8(value~="" and value or "-")
        local mtId = "mt_"..label
        imgui.SetCursorPos(imgui.ImVec2(S(10), S(28)))
        imgui.TextColored(getElemColor(mtId, applyGlobalNumColor(col or thTxt())), valStr)
        recolorOnClick(mtId)

    imgui.EndChild()
    imgui.PopStyleColor()
end

 St._chipIdx = 0
 St.chipSide = false
local function chip(label, value)
    if not hasVal(value) then return end
    St._chipIdx = St._chipIdx + 1
    local avail = imgui.GetContentRegionAvail().x
    local w  = (avail - S(6)) * 0.5
    local h  = S(54)
    local r,g,b = getAcc()
    local rr,rg,rb = getRowBgColor()
    local dl = imgui.GetWindowDrawList()
    local doRender = function(side)
        local p = imgui.GetCursorScreenPos()
        -- ť„Š¾Š½ chip: ŠŗŠ°ť�ť‥Š¾Š¼Š½ť‹Š¹ ť†Š²Šµť‥ ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ
        local bgR = math.max(rr*0.14, 0.08)
        local bgG = math.max(rg*0.14, 0.08)
        local bgB = math.max(rb*0.14, 0.08)
        dl:AddRectFilled(
            imgui.ImVec2(p.x,   p.y),
            imgui.ImVec2(p.x+w, p.y+h),
            imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 8)
        -- ť€Š°Š¼ŠŗŠ° Š¾ť‥ Š°Šŗť†ŠµŠ½ť‥Š°
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
        local cid = "##chip"..tostring(St._chipIdx)..(side and "R" or "L")
        imgui.BeginChild(cid, imgui.ImVec2(w,h), false)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(6)))
            imgui.TextColored(thDim(), label)
            imgui.SetCursorPos(imgui.ImVec2(S(8),S(26)))
            imgui.TextColored(thAcc(), u8(vOrDash(value)))
        imgui.EndChild()
        imgui.PopStyleColor()
    end
    if St.chipSide then
        imgui.SameLine(0,S(6))
        doRender(true)
        imgui.Spacing()
        St.chipSide = false
    else
        St.chipSide = true
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

    -- Š›Š•Š’Š�ŠÆ Š�Š˛Š›Š˛Š¯Š�Š� ĥ€” Š‥Š�Š›Š�Š¯Š� + Š�Š§Š•Š¢Š� (Š¾Š±ť‹ť‥Š½ť‹Š¹ ť�Šŗť€Š¾Š»Š»: ŠŗŠ¾Š»Šµť�Š¾ Š¼ť‹ť�Šø / ŠæŠ¾Š»Š¾ť�Š° Šæť€Š¾Šŗť€ť�ť‥ŠŗŠø)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_left", imgui.ImVec2(colW, h), false)
    if St._resetCharScroll then imgui.SetScrollY(0) end
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
                -- ĥ”€ĥ”€ Š›Š�Š§Š¯Š«Š• Š�Š§Š•Š¢Š� (Š²ť�ť‥ť€Š¾ŠµŠ½ť‹ Š² Š»ŠµŠ²ť�ťˇ ŠŗŠ¾Š»Š¾Š½Šŗť�) ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
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

    -- Š�Š Š�Š’Š�ŠÆ Š�Š˛Š›Š˛Š¯Š�Š� ĥ€” Š�Š•Š Š�Š˛Š¯Š�Š– (Š¾Š±ť‹ť‥Š½ť‹Š¹ ť�Šŗť€Š¾Š»Š»: ŠŗŠ¾Š»Šµť�Š¾ Š¼ť‹ť�Šø / ŠæŠ¾Š»Š¾ť�Š° Šæť€Š¾Šŗť€ť�ť‥ŠŗŠø)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##col_right", imgui.ImVec2(colW, h), false)
    if St._resetCharScroll then imgui.SetScrollY(0) end
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

    St._resetCharScroll = false
end
-- ============================================================
local function drawBattle(s, h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sb", imgui.ImVec2(0,h), false,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
        secTitle(u8"\xc1\xee\xe5\xe2\xfb\xe5 \xc1\xee\xed\xf3\xf1\xfb")
        St.chipSide = false
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
        if St.chipSide then St.chipSide=false end

    -- ── нижний отѥтѥп, чтобы поѥледняя ѥтрока не прилипала к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
end

-- ============================================================
--  Š‥Š£Š¤Š•Š Š« Š�Š›Š�Š™Š”Š•Š Š˛Š’ Š Š�Š—Š�Š•Š Š� Š˛Š�Š¯Š�
-- ============================================================
 St.winWbuf = imgui.new.float(0.60)
 St.winHbuf = imgui.new.float(0.76)
local WIN_W_MIN = 0.38
local WIN_H_MIN = 0.42
 St.fontSizeBuf = imgui.new.float(1.25)
local FONT_SIZE_MIN = 0.7
local FONT_SIZE_MAX = 2.0
-- Š±ť�ť„Šµť€ť‹ Š´Š»ť¸ Š½Š°ť�ť‥ť€Š¾ŠµŠŗ Š°Š²ť‥Š¾-Š¾Š±Š½Š¾Š²Š»ŠµŠ½Šøť¸ (Š´Š¾Š»Š¶Š½ť‹ Š±ť‹ť‥ť� Š³Š»Š¾Š±Š°Š»ť�Š½ť‹Š¼Šø, Š½Šµ Š²Š½ť�ť‥ť€Šø ť€ŠµŠ½Š´Šµť€Š°!)
local chkBuf = imgui.new.bool(false)
local chkBuf2 = imgui.new.bool(true)
local aBuf   = imgui.new.float(30.0)
-- Buffery kursov obmena valyut (celye chisla, chtoby ne bylo lishnih nulikov posle zapyatoy)
 St.rateAZBuf  = imgui.new.int(0)
 St.rateBTCBuf = imgui.new.int(0)
 St.rateEURBuf = imgui.new.int(0)
 St.rateVCBuf  = imgui.new.int(0)
 St.rateASCBuf = imgui.new.int(0)
local ascAmtBuf  = imgui.new.int(0)
-- bufer imeni servera dlya avtoobnovleniya kursov s arz-wiki.com
local vcServerNameBuf = imgui.new.char[32]("Tucson")
local _vcServerActive = false
local _arzFetching    = false
local _arzLastResult  = ""
-- otslezhivaem kakoe pole seychas redaktiruetsya, chtoby ne perezapisyvat bufer
-- kazhdyy kadr poka igrok pechataet (imenno eto vyzyvalo "migание"/skachushchie nuliki)
local _rateActive = {}
local _financeFilterExpanded = false
local _financeFilterBufs = {}

-- ── ѥоѥтояние окна "Наѥтройки" вкладки "Финанѥы": по ѥмолчанию оно
-- прикреплено к главномѥ окнѥ ѥправа и двигаетѥя вмеѥте ѥ ним; кнопка
-- "Открепитѥ" позволяет ноѥитѥ его отделѥно ──
 St._financeSettingsOpen     = false
 St._financeSettingsDetached = false
local _financeSettingsPos      = nil   -- {x=,y=} запоминаетѥя, толѥко пока панелѥ откреплена
 St._mainWinPos  = nil
 St._mainWinSize = nil
-- ── анимация ѥдвига главного окна влево при открытой (приѥтыкованной) панели
-- наѥтроек "Финанѥы"; когда панелѥ открываетѥя — окно ѥкрипта плавно ѥезжает
-- влево, чтобы оѥвободитѥ меѥто панели, а при закрытии панели возвращаетѥя
-- обратно на ѥвоё меѥто ──
 St._finShiftAnim       = 0.0   -- 0..1, текѥщая фаза анимации
 St._finShiftAppliedPx  = 0.0   -- ѥколѥко пикѥелей ѥдвига ѥже применено в проѥлый кадр
 St._finShiftLastTime   = nil

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
--  ОБНОВЛЕНХЕ ХУРХОВ ВХЛЮТ ЧЕРЕЗ ВНУТРХХГРОВОЙ ТЕЛЕФОН (без CEF)
-- ============================================================
-- В этой ѥборке MoonLoader модѥлѥ CEF недоѥтѥпен, поэтомѥ кѥрѥы
-- болѥѥе не берѥтѥя ѥ внеѥних ѥайтов через ѥкрытый браѥзер. Вмеѥто
-- этого ѥкрипт ѥам открывает телефон перѥонажа командой cfg.phoneOpenCmd
-- и читает значения кѥрѥов прямо из диалога ѥервера ѥ ID 0 (телефон
-- переиѥполѥзѥет этот диалог под вѥе ѥвои экраны).

local _cefFetching   = false
 St._cefLastResult = ""  -- текѥтовый ѥтатѥѥ поѥледней попытки (для UI)

-- ѥоѥтояние навигации по телефонѥ при автообновлении кѥрѥа:
-- false | "opening" (ждём главный экран, выберем поѥледнюю вкладкѥ) |
-- "last_tab" (ищем на ней пѥнкт "Хриптовалюта") | "crypto_menu" (мы в
-- нѥжном разделе, разбираем текѥт на кѥрѥы)
local _phoneFetchState = false

-- ѥчитает непѥѥтые ѥтроки ѥпиѥка диалога (пѥнкты SAMP-ѥпиѥка разделены
-- \n) и возвращает индекѥ (ѥ 0) поѥледней из них — это и еѥтѥ "поѥледняя
-- вкладка" телефона.
local function lastPhoneListIndex(text)
    if not text or text == "" then return nil end
    local idx = -1
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if stripColor(line) ~= "" then idx = idx + 1 end
    end
    if idx < 0 then return nil end
    return idx
end

-- ищет в текѥте диалога индекѥ (ѥ 0) первой ѥтроки, ѥодержащей любое
-- ѥлово из needles (без ѥчёта региѥтра/цветовых кодов). needles должны
-- бытѥ в той же кодировке (CP1251), что и текѥт диалога — БЕЗ u8()!
local function findPhoneListIndex(text, needles)
    if not text or text == "" then return nil end
    local idx = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line):lower()
        if clean ~= "" then
            for _, n in ipairs(needles) do
                if clean:find(n, 1, true) then return idx end
            end
            idx = idx + 1
        end
    end
    return nil
end

-- вытаѥкивает чиѥло прямо перед/поѥле ключевого ѥлова currency в ѥтроке
-- вида "AZ-Coins   104.791 AZ - $3.667.685.000" или "Евро  44 EUR - $0" —
-- ищем именно кѥрѥ (ценѥ в SA$ за единицѥ), а не количеѥтво на рѥках,
-- поэтомѥ берём чиѥло ѥразѥ поѥле "$" в конце ѥтроки, еѥли оно еѥтѥ,
-- иначе — первое чиѥло в ѥтроке.
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

-- разбирает текѥт диалога "кѥрѥ валют" в телефоне и раѥкладывает найденные
-- значения по cfg.rateXXX/бѥферам полей ввода. Возвращает true, еѥли хотя
-- бы один кѥрѥ ѥдалоѥѥ раѥпознатѥ.
local function parsePhoneRatesText(text)
    if not text or text == "" then return false end
    local gotAny = false

    local rAZ  = extractPhoneRate(text, {"az-coin", "az \xea\xee\xe8\xed", "\xe0\xe7-\xea\xee\xe8\xed"})
    local rBTC = extractPhoneRate(text, {"btc", "bitcoin", "\xe1\xe8\xf2\xea\xee\xe9\xed"})
    local rEUR = extractPhoneRate(text, {"eur", "\xe5\xe2\xf0\xee"})
    local rVC  = extractPhoneRate(text, {"vc$", "vice city", "\xe2\xe0\xe9\xf1 \xf1\xe8\xf2\xe8"})
    local rASC = extractPhoneRate(text, {"asc", "\xe0\xf0\xe8\xe7\xee\xed\xe0 \xf1\xf2\xe5\xe9\xe1\xeb"})

    if rAZ  and rAZ  > 0 then cfg.rateAZ  = rAZ;  St.rateAZBuf[0]  = math.floor(rAZ  + 0.5); gotAny = true end
    if rBTC and rBTC > 0 then cfg.rateBTC = rBTC; St.rateBTCBuf[0] = math.floor(rBTC + 0.5); gotAny = true end
    if rEUR and rEUR > 0 then cfg.rateEUR = rEUR; St.rateEURBuf[0] = math.floor(rEUR + 0.5); gotAny = true end
    if rVC  and rVC  > 0 then cfg.rateVC  = rVC;  St.rateVCBuf[0]  = math.floor(rVC  + 0.5); gotAny = true end
    if rASC and rASC > 0 then cfg.rateASC = rASC; St.rateASCBuf[0] = math.floor(rASC + 0.5); gotAny = true end

    if gotAny then saveCfg() end
    return gotAny
end

-- Запѥѥкает автообновление: открывает телефон командой cfg.phoneOpenCmd,
-- далѥѥе ѥама пролиѥтывает вкладки телефона до поѥледней, находит там
-- пѥнкт "Хриптовалюта", открывает его и читает кѥрѥы — ѥм. sampev.onShowDialog.
local function fetchRatesViaCEF()
    if _cefFetching then return end
    if not isSampAvailable() then
        St._cefLastResult = "\xf1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    _cefFetching     = true
    _phoneFetchState = "opening"
    St._cefLastResult   = "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed..."
    pcall(sampAddChatMessage, "{FFD700}[Stats] " .. "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xe8\xf9\xe5\xec \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2...", -1)
    lua_thread.create(function()
        local cmd = (cfg.phoneOpenCmd and cfg.phoneOpenCmd ~= "") and cfg.phoneOpenCmd or "/phone"
        local okCmd = pcall(sampSendChat, cmd)
        if not okCmd then
            _phoneFetchState = false
            _cefFetching     = false
            St._cefLastResult   = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xef\xf0\xe0\xe2\xe8\xf2\xfc \xea\xee\xec\xe0\xed\xe4\xf3 " .. cmd
            return
        end
        local waited = 0
        while _phoneFetchState and waited < 15000 do
            wait(100); waited = waited + 100
        end
        if _phoneFetchState then
            local failStage = _phoneFetchState
            _phoneFetchState = false
            if failStage == "opening" then
                St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xef\xf0\xe5\xe4\xe5\xeb\xe8\xf2\xfc \xf1\xef\xe8\xf1\xee\xea \xe2\xea\xeb\xe0\xe4\xee\xea \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
            elseif failStage == "last_tab" then
                St._cefLastResult = "\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xef\xf3\xed\xea\xf2 \\\"\xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0\\\" \xed\xe0 \xef\xee\xf1\xeb\xe5\xe4\xed\xe5\xe9 \xe2\xea\xeb\xe0\xe4\xea\xe5"
            else
                St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xea\xf3\xf0\xf1\xfb \xe2 \xee\xf2\xea\xf0\xfb\xf2\xee\xec \xf0\xe0\xe7\xe4\xe5\xeb\xe5"
            end
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
            -- на вѥякий ѥлѥчай закрываем вѥе вѥплывѥие диалоги, чтобы не
            -- оѥтавитѥ телефон открытым поверх интерфейѥа игрока
            for _=1,3 do pcall(sampCloseCurrentDialog, -1); wait(150) end
        end
        _cefFetching = false
    end)
end

-- ============================================================
--  Šť Š£Š ŠŠ« Š’ŠŠ›Š®Š¢ ŠŸŠ Š•Š”Š¤Ā  ARZ-WIKI (statichesky snapshot)
-- ------------------------------------------------------------
-- Tablitsa kursov obmena valyut po serveram Arizona RP, sobrannaya
-- s stranitsy arz-wiki.com/arz-rp/articles/currency-exchange/.
-- Znachenie kazhdogo polya - tsena PRODAZHI 1 edinitsy valyuty v SA$
-- (t.e. skolko SA$ igrok poluchit za 1 VC$/BTC/AZ/EUR/ASC).
-- Eto snimok na moment 19.07.2026 - kursy na servere menyayutsya,
-- tak chto tablitsu stoit periodicheski obnovlyat' vruchnuyu so
-- stranitsy vyshe. Ispolzuetsya kak bystryy istochnik kursov, kogda
-- igrok ne hochet otkryvat' telefon (fetchRatesViaCEF).
-- ============================================================
local ARZ_WIKI_RATES = {
    ["Brainburg"]    = { vc=124, btc=64644, az=27000, eur=4622, asc=46000 },
    ["Bumble Bee"]   = { vc=112, btc=63939, az=27000, eur=4445, asc=46000 },
    ["Casa Grande"]  = { vc=112, btc=64660, az=27000, eur=4945, asc=46000 },
    ["Chandler"]     = { vc=129, btc=63120, az=27000, eur=2909, asc=46000 },
    ["Christmas"]    = { vc=112, btc=64652, az=27000, eur=4901, asc=46000 },
    ["Drake"]        = { vc=112, btc=63936, az=27000, eur=4888, asc=46000 },
    ["Faraway"]      = { vc=112, btc=64749, az=20000, eur=4890, asc=46000 },
    ["Gilbert"]      = { vc=112, btc=63910, az=27000, eur=9592, asc=46000 },
    ["Glendale"]     = { vc=112, btc=64436, az=27000, eur=5753, asc=46000 },
    ["Holiday"]      = { vc=112, btc=63120, az=27000, eur=5431, asc=46000 },
    ["Kingman"]      = { vc=112, btc=64791, az=27000, eur=6946, asc=46000 },
    ["Love"]         = { vc=112, btc=64660, az=27000, eur=5122, asc=46000 },
    ["Mesa"]         = { vc=160, btc=64744, az=27000, eur=3538, asc=46000 },
    ["Mirage"]       = { vc=112, btc=64193, az=27000, eur=4959, asc=46000 },
    ["Mobile 1"]     = {         btc=72986, az=35000, eur=5048, asc=46000 },
    ["Mobile 2"]     = {         btc=89441, az=35000, eur=5739, asc=45000 },
    ["Mobile 3"]     = {         btc=66533, az=35000, eur=6439, asc=46000 },
    ["Page"]         = { vc=112, btc=64515, az=27000, eur=4696, asc=46000 },
    ["Payson"]       = { vc=112, btc=64660, az=27000, eur=4820, asc=46000 },
    ["Phoenix"]      = { vc=131, btc=64660, az=27000, eur=1673, asc=46000 },
    ["Prescott"]     = { vc=112, btc=63939, az=27000, eur=5438, asc=46000 },
    ["Queen Creek"]  = { vc=112, btc=64665, az=27000, eur=5393, asc=46000 },
    ["Red Rock"]     = { vc=114, btc=64515, az=27000, eur=3903, asc=46000 },
    ["Saint Rose"]   = { vc=123, btc=63365, az=27000, eur=4844, asc=46000 },
    ["Scottdale"]    = { vc=148, btc=64665, az=27000, eur=2438, asc=46000 },
    ["Sedona"]       = { vc=112, btc=64660, az=27000, eur=4857, asc=46000 },
    ["Show Low"]     = { vc=112, btc=64086, az=27000, eur=6842, asc=46000 },
    ["Space"]        = { vc=112, btc=62933,           eur=4862, asc=46000 },
    ["Sun City"]     = { vc=112, btc=63120, az=27000, eur=5626, asc=46000 },
    ["Surprise"]     = { vc=112, btc=64471, az=27000, eur=4976, asc=46000 },
    ["Tucson"]       = { vc=183, btc=64736, az=27000, eur=2827, asc=46000 },
    ["Vice City"]    = {         btc=97368, az=35000, eur=5048, asc=43000 },
    ["Wednesday"]    = { vc=112, btc=63936, az=27000, eur=3134, asc=46000 },
    ["Winslow"]      = { vc=112, btc=64665, az=27000, eur=6063, asc=46000 },
    ["Yava"]         = { vc=112, btc=63935, az=27000, eur=4485, asc=46000 },
    ["Yuma"]         = { vc=132, btc=64644, az=27000, eur=7238, asc=46000 },
}

-- ============================================================
--  Ā–ivaya zagruzka kursov s arz-wiki.com (bez otkrytiya telefona)
-- ------------------------------------------------------------
-- Skachivaet stranitsu s tablitsey kursov i razbiraet HTML-tablitsy
-- pryamo v skripte, obnovlyaya ARZ_WIKI_RATES svezhimi chislami. Ne
-- zavisit ot tochnoy razmetki sayta - ischet izvestnye nazvaniya
-- serverov v tekste kazhdoy stroki tablitsy, a ne po pozitsii kolonok.
-- ============================================================
local ARZ_WIKI_URL = "https://arz-wiki.com/arz-rp/articles/currency-exchange/"

-- markery valyutnyh razdelov na stranitse (v poryadke ih poyavleniya);
-- eto prostoy ASCII-tekst v zagolovkah vida "Kurs Bitcoin (BTC)", tak
-- chto poisk ne zavisit ot kodirovki kirillicheskogo teksta stranitsy
local ARZ_SECTION_ORDER = {
    { key="vc",  marker="(VC)"   },
    { key="btc", marker="(BTC)"  },
    { key="az",  marker="(AZ)"   },
    { key="ltc", marker="(LTC)"  },
    { key="eth", marker="(ETH)"  },
    { key="eur", marker="(EURO)" },
    { key="asc", marker="(ASC)"  },
}

-- spisok izvestnyh nazvaniy serverov (iz ARZ_WIKI_RATES), otsortirovannyy
-- po dline po ubyvaniyu - chtoby "Queen Creek" naschelsya ranshe, chem
-- korotkoe imya, sluchayno vhodyashchee v nego podstrokoy
local ARZ_SERVER_NAMES = {}
for k in pairs(ARZ_WIKI_RATES) do ARZ_SERVER_NAMES[#ARZ_SERVER_NAMES+1] = k end
table.sort(ARZ_SERVER_NAMES, function(a, b) return #a > #b end)

-- ubiraet vse HTML-tegi iz kuska teksta, ostavlyaya tolko vidimyy tekst
local function stripHtmlTags(s)
    return (tostring(s or ""):gsub("<[^>]+>", " "))
end

-- vytaskivaet chislo iz teksta yacheyki vida "183$" / "64 736$" / "-"
local function extractCellNumber(s)
    s = tostring(s or ""):gsub("&nbsp;", " ")
    local numStr = s:match("([%d%s]+)%s*%$")
    if not numStr then return nil end
    numStr = numStr:gsub("%s+", "")
    local v = tonumber(numStr)
    if v and v > 0 then return v end
    return nil
end

-- razbiraet odнѥ tablitsu (kusok HTML mezhdu markerami dvuh valyut) i
-- vozvrashchaet { [serverName] = firstNumberInRow, ... } - pervaya
-- chislovaya yacheyka v stroke vsegda "Prodat'" (kurs prodazhi), a imenno
-- eto polya cfg.rateXXX i ozhidayut
local function parseArzTableChunk(html)
    local result = {}
    local tableHtml = html:match("<table[^>]*>(.-)</table>")
    if not tableHtml then return result end
    for rowHtml in tableHtml:gmatch("<tr[^>]*>(.-)</tr>") do
        local plainRow = stripHtmlTags(rowHtml)
        local foundName = nil
        for _, name in ipairs(ARZ_SERVER_NAMES) do
            if plainRow:find(name, 1, true) then foundName = name; break end
        end
        if foundName then
            for cellHtml in rowHtml:gmatch("<td[^>]*>(.-)</td>") do
                local n = extractCellNumber(stripHtmlTags(cellHtml))
                if n then result[foundName] = n; break end
            end
        end
    end
    return result
end

-- razbiraet vsyu stranitsu na sektsii po valyutam i sobiraet obshchuyu
-- tablitsu kursov po serveram; vozvrashchaet (tablitsa, kolichestvo
-- serverov, dlya kotoryh naideno hot' odno znachenie)
local function parseArzWikiHtml(html)
    if not html or #html < 500 then return nil, 0 end
    local positions = {}
    local searchFrom = 1
    for _, sec in ipairs(ARZ_SECTION_ORDER) do
        local s, e = html:find(sec.marker, searchFrom, true)
        if s then
            positions[#positions + 1] = { key = sec.key, pos = s }
            searchFrom = e + 1
        end
    end
    if #positions == 0 then return nil, 0 end

    local merged = {}
    for i, p in ipairs(positions) do
        local sectionEnd = positions[i + 1] and positions[i + 1].pos or (p.pos + 20000)
        local chunk = html:sub(p.pos, sectionEnd)
        local rows = parseArzTableChunk(chunk)
        for serverName, value in pairs(rows) do
            merged[serverName] = merged[serverName] or {}
            merged[serverName][p.key] = value
        end
    end

    local count = 0
    for _ in pairs(merged) do count = count + 1 end
    return merged, count
end

-- sinhronnoe HTTP GET cherez opcionalnuyu biblioteku 'requests'
-- (WinInet-obyortka, podderzhivayet https "iz korobki" na Windows).
-- Polozhi requests.lua v moonloader/lib/, chtoby zhivaya zagruzka rabotala.
local function httpGetArzWiki()
    if not _httpLib or type(_httpLib.get) ~= "function" then
        return nil, "no_requests_lib"
    end
    local ok, resp = pcall(_httpLib.get, ARZ_WIKI_URL)
    if not ok or not resp then return nil, "request_failed" end
    local status = resp.status_code or (type(resp.status) == "table" and resp.status.code) or 200
    if status and status ~= 200 then return nil, "http_" .. tostring(status) end
    local body = resp.text or resp.content or resp.body
    if type(body) ~= "string" or #body < 500 then return nil, "empty_body" end
    return body, nil
end

-- ============================================================
--  ХВТООБНОВЛЕНХЕ ХХРХХТХ Х GITHUB (вкладка "О ѥкрипте")
-- ============================================================
-- ЗХХОЛНХ эти 4 значения под ѥвой репозиторий на GitHub, чтобы кнопка
-- "Хроверитѥ обновления" заработала. raw.githubusercontent.com отдаёт
-- файл в чиѥтом виде (без HTML-обёртки) - то, что нѥжно для ѥкачивания.
-- Также требѥетѥя библиотека requests.lua в moonloader/lib (та же, что
-- иѥполѥзѥетѥя для "Обновитѥ кѥрѥы ѥ ѥайта" в вкладке "Финанѥы") ──
local UPDATE_GH_USER    = "maincrafter48-prog"   -- <- ник/организация на GitHub
local UPDATE_GH_REPO    = "pc-stats-moonloader"  -- <- имя репозитория
local UPDATE_GH_BRANCH  = "main"                 -- <- ветка (main / master)
-- ВХЖНО: имя файла НЕ должно ѥодержатѥ номер верѥии! Ранѥѥе тѥт было
-- "PCStats_v1.1.5.lua" - из-за этого при каждом новом релизе ѥкрипт
-- продолжал качатѥ ХТХРЫЙ файл по ѥтаромѥ хардкод-имени (даже еѥли
-- version.txt показывал новѥю верѥию), и поѥле "обновления" в игре
-- вѥё равно оѥтавалаѥѥ ѥтарая верѥия. Держи в репозитории ОДХН файл
-- ѥ ХОХТОЯННЫХ именем (например PCStats.lua) и проѥто перезапиѥывай
-- его ѥодержимое при каждом релизе.
local UPDATE_GH_FILE    = "PCStats.lua"          -- <- пѥтѥ к .lua файлѥ ѥкрипта внѥтри репозитория (имя не меняетѥя от релиза к релизѥ)
local UPDATE_GH_VERFILE = "version.txt"          -- <- лёгкий файл ѥ одной ѥтрокой-верѥией (обнови его при каждом релизе)

local SCRIPT_VERSION = "1.1.6" -- должно совпадать с script_version() в начале файла

local function ghRawUrl(path)
    return ("https://raw.githubusercontent.com/%s/%s/%s/%s")
        :format(UPDATE_GH_USER, UPDATE_GH_REPO, UPDATE_GH_BRANCH, path)
end

-- to zhe samoe, no s vozmozhnostyu ukazat' konkretnuyu vetku (dlya
-- fallback-a glavnaya vetka -> master, esli osnovnaya nedostupna)
local function ghRawUrlBranch(branch, path)
    return ("https://raw.githubusercontent.com/%s/%s/%s/%s")
        :format(UPDATE_GH_USER, UPDATE_GH_REPO, branch, path)
end

-- ѥравнение верѥий вида "1.2.10" vs "1.2.9" по чиѥловым ѥегментам
local function versionGreater(a, b)
    local function segs(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local ta, tb = segs(a), segs(b)
    for i = 1, math.max(#ta, #tb) do
        local x, y = ta[i] or 0, tb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

local function httpGetGithub(url)
    if not _httpLib or type(_httpLib.get) ~= "function" then
        return nil, "no_requests_lib"
    end
    local ok, resp = pcall(_httpLib.get, url)
    if not ok or not resp then return nil, "request_failed" end
    local status = resp.status_code or (type(resp.status) == "table" and resp.status.code) or 200
    if status and status ~= 200 then return nil, "http_" .. tostring(status) end
    local body = resp.text or resp.content or resp.body
    if type(body) ~= "string" or #body < 1 then return nil, "empty_body" end
    return body, nil
end

-- zapuskaet GET-zapros v otdelnom OS-potoke cherez effil, chtoby igra
-- ne zaviala poka zhdyom otvet ot GitHub (v otlichie ot httpGetGithub
-- vyshe, kotoryy blokiruet igrovoy potok na vsyo vremya zaprosa)
local function httpFetchThread(url)
    return effil.thread(function(target)
        local req = require('requests')
        local function once(link, depth)
            depth = depth or 0
            if depth > 5 then
                return false, { status_code = 0, text = '', error = 'redirect loop' }
            end
            local ok, response = pcall(req.request, 'GET', link, {
                headers = {
                    ['User-Agent'] = 'PCStats-Updater/1.0',
                    ['Accept'] = 'text/plain, application/octet-stream;q=0.9, */*;q=0.7',
                },
                timeout = 20,
            })
            if not ok or not response then
                return false, { status_code = 0, text = '', error = tostring(response or 'connect error') }
            end
            local code = tonumber(response.status_code) or 0
            if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                local loc = response.headers and (response.headers.Location or response.headers.location)
                if loc and loc ~= '' then
                    return once(loc, depth + 1)
                end
            end
            return true, {
                status_code = code,
                text = response.text or '',
                headers = response.headers or {},
                error = nil,
            }
        end
        return once(target, 0)
    end)(url)
end

-- ozhidaet otvet ot httpFetchThread, ne blokiruya igru (poll cherez
-- wait(100)); esli effil ne ustanovlen - tikho otkatyvaetsya na staryy
-- sinhronnyy httpGetGithub (nebolshaya zaderzhka igry na vremya zaprosa,
-- no khot' rabotaet bez effil)
local function httpFetchWait(url, maxSteps)
    if not effil then
        return httpGetGithub(url)
    end
    local ok, thr = pcall(httpFetchThread, url)
    if not ok or not thr then
        return httpGetGithub(url)
    end
    for _ = 1, (maxSteps or 200) do
        wait(100)
        local st, thErr = thr:status()
        if not st or st == 'canceled' or st == 'failed' or thErr then
            return nil, tostring(thErr or "request_failed")
        end
        if st == 'completed' then
            local ok2, resp = thr:get()
            if ok2 and resp and tonumber(resp.status_code) == 200 and type(resp.text) == "string" and resp.text ~= '' then
                return resp.text, nil
            end
            return nil, (resp and resp.error) or "http_error"
        end
    end
    return nil, "timeout"
end

-- ѥоѥтояние UI автообновления: "idle" | "checking" | "uptodate" | "available"
-- | "downloading" | "done" | "error"; _updMsg хранитѥя в CP1251 (как и
-- оѥталѥные ѥтроки для sampAddChatMessage), в imgui выводитѥя через u8()
local _updState      = "idle"
local _updChecking   = false
local _updDownloading= false
local _updRemoteVer  = nil
local _updMsg        = ""

local _updHttpErrors = {
    no_requests_lib = "\xed\xe5\xf2 \xe1\xe8\xe1\xeb\xe8\xee\xf2\xe5\xea\xe8 requests \xe4\xeb\xff HTTP (\xef\xee\xeb\xee\xe6\xe8 requests.lua \xe2 moonloader/lib)",
    request_failed  = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xef\xee\xe4\xea\xeb\xfe\xf7\xe8\xf2\xfc\xf1\xff \xea GitHub",
    empty_body      = "\xef\xf3\xf1\xf2\xee\xe9 \xee\xf2\xe2\xe5\xf2 \xee\xf2 GitHub",
}

-- ── проверка верѥии на GitHub: ѥначала пробѥем короткий version.txt
-- (деѥевле ѥкачатѥ), а еѥли его нет в репозитории - вытаѥкиваем верѥию
-- прямо из ѥтроки script_version("x.y.z") внѥтри ѥамого .lua файла;
-- пробѥем ѥначала UPDATE_GH_BRANCH, при неѥдаче - "master" ──
function checkForUpdates()
    if _updChecking then return end
    _updChecking = true
    _updState    = "checking"
    _updMsg      = "\xef\xf0\xee\xe2\xe5\xf0\xff\xe5\xec \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff \xed\xe0 GitHub..."
    lua_thread.create(function()
        local branches = { UPDATE_GH_BRANCH }
        if UPDATE_GH_BRANCH ~= "master" then branches[#branches + 1] = "master" end

        local remoteVer, lastErr = nil, nil
        for _, br in ipairs(branches) do
            local verBody, err = httpFetchWait(ghRawUrlBranch(br, UPDATE_GH_VERFILE))
            if verBody then
                remoteVer = verBody:match("(%d+%.%d+%.%d+)") or verBody:match("(%d+%.%d+)")
            end
            lastErr = err or lastErr
            if not remoteVer then
                local luaBody
                luaBody, err = httpFetchWait(ghRawUrlBranch(br, UPDATE_GH_FILE))
                if luaBody then
                    remoteVer = luaBody:match('script_version%s*%(%s*"([%d%.]+)"')
                end
                lastErr = err or lastErr
            end
            if remoteVer then break end
        end

        _updChecking = false
        if not remoteVer then
            _updState = "error"
            _updMsg   = _updHttpErrors[lastErr] or ("\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xef\xee\xeb\xf3\xf7\xe8\xf2\xfc \xe2\xe5\xf0\xf1\xe8\xfe: " .. tostring(lastErr))
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. _updMsg, -1)
            return
        end

        _updRemoteVer = remoteVer
        if versionGreater(remoteVer, SCRIPT_VERSION) then
            _updState = "available"
            _updMsg   = "\xe4\xee\xf1\xf2\xf3\xef\xed\xe0 \xed\xee\xe2\xe0\xff \xe2\xe5\xf0\xf1\xe8\xff: " .. remoteVer
            pcall(sampAddChatMessage, "{FFD700}[Stats] " .. _updMsg, -1)
        else
            _updState = "uptodate"
            _updMsg   = "\xf3 \xe2\xe0\xf1 \xef\xee\xf1\xeb\xe5\xe4\xed\xff\xff \xe2\xe5\xf0\xf1\xe8\xff (" .. SCRIPT_VERSION .. ")"
            pcall(sampAddChatMessage, "{00FF88}[Stats] " .. _updMsg, -1)
        end
    end)
end

-- проверяем, что тело ответа похоже на наѥтоящий .lua ѥкрипт, а не на
-- ѥтраницѥ оѥибки GitHub (404 / HTML) - иначе можно затеретѥ рабочий
-- файл мѥѥором
local function isValidScriptBody(body)
    if type(body) ~= "string" or #body < 500 then return false end
    if body:find("<!DOCTYPE html", 1, true) or body:find("<html", 1, true) then return false end
    if body:find("script_name%s*%(") then return true end
    return false
end

-- атомарная запиѥѥ: ѥначала во временный файл, потом переименование на
-- меѥто рабочего - еѥли ѥкачивание/запиѥѥ прервётѥя на ѥередине,
-- текѥщий рабочий ѥкрипт не поѥтрадает
local function writeFileAtomic(path, content)
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(content)
    f:close()
    os.remove(path)
    if os.rename(tmp, path) then return true end
    -- zapasnoy variant, esli os.rename ne srabotal (raznie diski/FS)
    local rf, wf = io.open(tmp, "rb"), io.open(path, "wb")
    if not rf or not wf then
        if rf then rf:close() end
        if wf then wf:close() end
        os.remove(tmp)
        return false
    end
    wf:write(rf:read("*a"))
    rf:close(); wf:close()
    os.remove(tmp)
    return true
end

-- ── ѥкачивает новѥю верѥию .lua-файла ѥ GitHub и перезапиѥывает им
-- текѥщий файл ѥкрипта на диѥке. Хам ѥкрипт не может "на летѥ" заменитѥ
-- ѥвой ѥже загрѥженный код - поѥле ѥѥпеѥной запиѥи нѥжно перезапѥѥтитѥ
-- ѥкрипт в MoonLoader (клавиѥа F4 или команда /reload) ──
function downloadUpdate()
    if _updDownloading then return end
    if not _updRemoteVer then return end
    _updDownloading = true
    _updState = "downloading"
    _updMsg   = "\xf1\xea\xe0\xf7\xe8\xe2\xe0\xe5\xec \xed\xee\xe2\xf3\xfe \xe2\xe5\xf0\xf1\xe8\xfe..."
    lua_thread.create(function()
        local branches = { UPDATE_GH_BRANCH }
        if UPDATE_GH_BRANCH ~= "master" then branches[#branches + 1] = "master" end

        local body, err = nil, nil
        for _, br in ipairs(branches) do
            body, err = httpFetchWait(ghRawUrlBranch(br, UPDATE_GH_FILE))
            if isValidScriptBody(body) then break end
            body = nil
        end

        _updDownloading = false
        if not isValidScriptBody(body) then
            _updState = "error"
            _updMsg   = _updHttpErrors[err] or "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf1\xea\xe0\xf7\xe0\xf2\xfc \xed\xee\xe2\xf3\xfe \xe2\xe5\xf0\xf1\xe8\xfe (\xef\xf3\xf1\xf2\xee\xe9 \xee\xf2\xe2\xe5\xf2 \xe8\xeb\xe8 \xed\xe5 \xf4\xe0\xe9\xeb .lua)"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. _updMsg, -1)
            return
        end

        local path = nil
        pcall(function()
            local ts = thisScript()
            if ts and ts.path then path = ts.path end
        end)
        if not path or path == "" then
            path = "moonloader/PCStats.lua" -- запаѥной вариант, еѥли thisScript() недоѥтѥпен
        end

        local ok = writeFileAtomic(path, body)

        if ok then
            _updState = "done"
            _updMsg   = "\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xee \xe4\xee " .. tostring(_updRemoteVer) ..
                ". \xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xe5 \xf1\xea\xf0\xe8\xef\xf2 (F4 \xe8\xeb\xe8 /reload)"
            pcall(sampAddChatMessage, "{00FF88}[Stats] " .. _updMsg, -1)
        else
            _updState = "error"
            _updMsg   = "\xee\xf8\xe8\xe1\xea\xe0 \xe7\xe0\xef\xe8\xf1\xe8 \xf4\xe0\xe9\xeb\xe0 \xed\xe0 \xe4\xe8\xf1\xea"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. _updMsg, -1)
        end
    end)
end

-- ── glavnaya funktsiya knopki "Obnovit' kursy valyut": skachivaet
-- stranitsu arz-wiki.com (bez otkrytiya telefona v igre), razbiraet
-- tablitsy, obnovlyaet ARZ_WIKI_RATES i primenyaet kursy k tekushchemu
-- (avtoopredelyonnomu ili vruchnuyu vvedennomu) serveru ──
function fetchLiveRatesFromWeb()
    if _arzFetching then return end
    _arzFetching   = true
    _arzLastResult = "\xef\xee\xe4\xea\xeb\xfe\xf7\xe0\xe5\xec\xf1\xff \xea arz-wiki.com..."
    lua_thread.create(function()
        local okCall, html, err = pcall(httpGetArzWiki)
        if not okCall then html, err = nil, "internal_error" end

        if not html then
            local messages = {
                no_requests_lib = "\xed\xe5\xf2 \xe1\xe8\xe1\xeb\xe8\xee\xf2\xe5\xea\xe8 requests \xe4\xeb\xff HTTP (\xef\xee\xeb\xee\xe6\xe8 requests.lua \xe2 moonloader/lib)",
                request_failed  = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xef\xee\xe4\xea\xeb\xfe\xf7\xe8\xf2\xfc\xf1\xff \xea arz-wiki.com",
                empty_body      = "\xef\xf3\xf1\xf2\xee\xe9 \xee\xf2\xe2\xe5\xf2 \xee\xf2 \xf1\xe0\xe9\xf2\xe0",
            }
            _arzLastResult = messages[err] or ("\xee\xf8\xe8\xe1\xea\xe0 \xf1\xe5\xf2\xe8: " .. tostring(err))
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. _arzLastResult, -1)
            _arzFetching = false
            return
        end

        local parsed, count = parseArzWikiHtml(html)
        if not parsed or count < 10 then
            _arzLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xf1\xf2\xf0\xe0\xed\xe8\xf6\xf3 \xf1\xe0\xe9\xf2\xe0 (\xe8\xe7\xec\xe5\xed\xe8\xeb\xe0\xf1\xfc \xf0\xe0\xe7\xec\xe5\xf2\xea\xe0?)"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. _arzLastResult, -1)
            _arzFetching = false
            return
        end

        for name, r in pairs(parsed) do
            ARZ_WIKI_RATES[name] = ARZ_WIKI_RATES[name] or {}
            for k, v in pairs(r) do ARZ_WIKI_RATES[name][k] = v end
        end

        _arzLastResult = "\xea\xf3\xf0\xf1\xfb \xef\xee\xeb\xf3\xf7\xe5\xed\xfb \xf1 \xf1\xe0\xe9\xf2\xe0 (" .. tostring(count) .. " \xf1\xe5\xf0\xe2\xe5\xf0\xee\xe2)"
        pcall(sampAddChatMessage, "{00FF88}[Stats] " .. _arzLastResult, -1)
        _arzFetching = false
        fetchArzWikiRates() -- primenyaet svezhiye dannye k tekushchemu serveru + soobshchenie
    end)
end

-- ── ishet zapis' v ARZ_WIKI_RATES po imeni servera: snachala tochnoe
-- sovpadenie, potom bez ucheta registra, potom po vhozhdeniyu podstroki
-- (na sluchay esli detectArzServerName() vernul chto-to vrode
-- "Arizona Role Play | Tucson" celikom) ──
local function findWikiRatesForServer(name)
    if not name or name == "" then return nil, nil end
    if ARZ_WIKI_RATES[name] then return ARZ_WIKI_RATES[name], name end
    local low = name:lower()
    for k, v in pairs(ARZ_WIKI_RATES) do
        if k:lower() == low then return v, k end
    end
    for k, v in pairs(ARZ_WIKI_RATES) do
        if low:find(k:lower(), 1, true) then return v, k end
    end
    return nil, nil
end

-- ── primenyaet naydennye v ARZ_WIKI_RATES kursy k cfg.rateXXX i
-- sootvetstvuyuschim buferam poley vvoda, sohranyaet konfig. silent=true
-- - bez soobscheniy v chat (ispolzuetsya pri tihoy avtozagruzke pri
-- vhode na server) ──
local function applyWikiRatesForServer(serverName, silent)
    local r, matched = findWikiRatesForServer(serverName)
    if not r then
        if not silent then
            pcall(sampAddChatMessage, "{FF6666}[Stats] " ..
                "\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed\xfb \xea\xf3\xf0\xf1\xfb \xe4\xeb\xff \xf1\xe5\xf0\xe2\xe5\xf0\xe0: " ..
                tostring(serverName or "?"), -1)
        end
        return false
    end
    if r.vc  then cfg.rateVC  = r.vc;  St.rateVCBuf[0]  = math.floor(r.vc  + 0.5) end
    if r.btc then cfg.rateBTC = r.btc; St.rateBTCBuf[0] = math.floor(r.btc + 0.5) end
    if r.az  then cfg.rateAZ  = r.az;  St.rateAZBuf[0]  = math.floor(r.az  + 0.5) end
    if r.eur then cfg.rateEUR = r.eur; St.rateEURBuf[0] = math.floor(r.eur + 0.5) end
    if r.asc then cfg.rateASC = r.asc; St.rateASCBuf[0] = math.floor(r.asc + 0.5) end
    saveCfg()
    if not silent then
        pcall(sampAddChatMessage, "{00FF88}[Stats] " ..
            "\xea\xf3\xf0\xf1\xfb \xe7\xe0\xe3\xf0\xf3\xe6\xe5\xed\xfb \xe4\xeb\xff \xf1\xe5\xf0\xe2\xe5\xf0\xe0 " ..
            tostring(matched) .. " (arz-wiki.com)", -1)
    end
    return true
end

-- ── zagruzhaet kursy iz tablitsy ARZ_WIKI_RATES dlya servera, na
-- kotorom seychas nahoditsya igrok. Esli vklyucheno avtoopredelenie
-- (cfg.vcAutoDetectServer) - server berйтsya cherez detectArzServerName()
-- (nativnaya SAMP-funkciya sampGetCurrentServerName), inache - iz
-- vruchnuyu vvedennogo cfg.vcServerName ──

-- ── определяет текѥщий ѥервер Arizona RP, к которомѥ подключён игрок,
-- через нативнѥю SAMP-фѥнкцию sampGetCurrentServerName(); иѥполѥзѥетѥя
-- в панели наѥтроек "Финанѥы" при включённом автоопределении ѥервера
-- (cfg.vcAutoDetectServer). Обёрнѥто в pcall, чтобы отѥѥтѥтвие фѥнкции
-- (например, до подключения к ѥерверѥ) не приводило к крахѥ ѥкрипта ──
local function detectArzServerName()
    if type(sampGetCurrentServerName) ~= "function" then
        return nil
    end
    local ok, name = pcall(sampGetCurrentServerName)
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    -- пытаемѥя вытащитѥ короткое имя города Arizona RP из полного
    -- названия ѥервера (например, "Arizona Role Play | Phoenix" -> "Phoenix");
    -- еѥли раѥпознатѥ не полѥчилоѥѥ — возвращаем название ѥервера как еѥтѥ
    local short = name:match("([%a%-]+)%s*$")
    return short or name
end

function fetchArzWikiRates(silent)
    local name = cfg.vcAutoDetectServer and detectArzServerName() or cfg.vcServerName
    return applyWikiRatesForServer(name, silent)
end

-- ── крѥглый тѥмблер вкл/выкл: зелёный = включено, краѥный = выключено ──
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

-- ── вѥплывающее окно "Наѥтройки" вкладки "Финанѥы": вынеѥено в отделѥнѥю
-- фѥнкцию, чтобы не раздѥватѥ ѥпиѥок апвэлѥю drawTotal (лимит Lua — 60) ──
local function drawFinanceSettingsBlock(r, g, b)
    local avW  = imgui.GetContentRegionAvail().x

    -- ── единая кнопка "Наѥтройки" — открывает/закрывает панелѥ наѥтроек
    -- вкладки "Финанѥы". Ханелѥ болѥѥе не вѥплывающий popup, а отделѥное
    -- окно, прикреплённое ѥправа от главного окна (ѥм. drawFinanceSettingsPanel).
    -- Цвет кнопки ѥделан отделѥным (нейтралѥно-ѥеро-голѥбым), а не акцентным,
    -- чтобы она визѥалѥно отличалаѥѥ от оѥталѥных кнопок вкладки ──
    local _fsOn = {0.42,0.48,0.58} -- цвет кнопки "Наѥтройки" (когда закрыта)
    local _fsAc = {0.30,0.62,0.95} -- цвет кнопки, когда панелѥ открыта (подѥветка)
    local sbc = St._financeSettingsOpen and _fsAc or _fsOn
    imgui.PushStyleColor(imgui.Col.Button,        iv4(sbc[1]*0.55,sbc[2]*0.55,sbc[3]*0.55,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(sbc[1]*0.80,sbc[2]*0.80,sbc[3]*0.80,1.0))
    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(sbc[1],sbc[2],sbc[3],1.0))
    do local _pb = prettyBtnPush(10.0)
    if imgui.Button(u8"  \xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8##financeSettingsBtn", imgui.ImVec2(avW, S(36))) then
        St._financeSettingsOpen = not St._financeSettingsOpen
    end
    prettyBtnPop(_pb) end
    imgui.PopStyleColor(3)
end

-- ── ѥодержимое панели "Наѥтройки" вкладки "Финанѥы" — вынеѥено отделѥно
-- от ѥамого окна (drawFinanceSettingsPanel), чтобы окно можно было риѥоватѥ
-- вне вкладки "Финанѥы" (оно теперѥ отделѥное, приѥтыкованное окно) ──
local function drawFinanceSettingsPanelContent(r, g, b)
    imgui.TextColored(thDim(), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xe2\xea\xeb\xe0\xe4\xea\xe8 \xab\xd4\xe8\xed\xe0\xed\xf1\xfb\xbb:")
    imgui.Spacing()
    imgui.Separator()
    imgui.Spacing()

    -- ── единая кнопка: обновляет и EUR/BTC, и VC$/AZ/EURO/ASC под ѥервер ──
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xca\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2")
    imgui.Spacing()

    -- переключателѥ: определятѥ ѥервер автоматичеѥки (по текѥщемѥ SAMP-ѥерверѥ)
    -- или вводитѥ название врѥчнѥю
    if drawToggleSwitch("##vcAutoDetectSw", cfg.vcAutoDetectServer) then
        cfg.vcAutoDetectServer = not cfg.vcAutoDetectServer
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(0.85,0.87,0.95,1.0), u8"\xce\xef\xf0\xe5\xe4\xe5\xeb\xff\xf2\xfc \xf1\xe5\xf0\xe2\xe5\xf0 \xe0\xe2\xf2\xee\xec\xe0\xf2\xe8\xf7\xe5\xf1\xea\xe8")
    imgui.Spacing()

    if cfg.vcAutoDetectServer then
        -- автоматичеѥкий режим: проѥто показываем, что определил ѥкрипт прямо ѥейчаѥ
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
        local busy = _arzFetching
        local awBg = busy and {0.85,0.68,0.15} or {0.16,0.52,0.92}
        local awLbl = busy
            and u8"  \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
            or  u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc \xea\xf3\xf0\xf1\xfb \xf1 \xf1\xe0\xe9\xf2\xe0"
        imgui.PushStyleColor(imgui.Col.Button,        iv4(awBg[1]*0.55,awBg[2]*0.55,awBg[3]*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(awBg[1]*0.75,awBg[2]*0.75,awBg[3]*0.75,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(awBg[1],awBg[2],awBg[3],1.0))
        do local _pb2 = prettyBtnPush(9.0)
        if imgui.Button(awLbl.."##financeRefAll", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            fetchLiveRatesFromWeb()
        end
        prettyBtnPop(_pb2) end
        imgui.PopStyleColor(3)
        if _arzLastResult ~= "" then
            imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. u8(_arzLastResult))
        end
    end
    imgui.Spacing()

    -- ── рѥчной ввод кѥрѥов валют: кнопка открывает вѥплывающее окно
    -- ѥ полями AZ-Coins/BTC/Евро/VC$/ASC (перенеѥено ѥюда ѥ вкладки
    -- "Финанѥы", ранѥѥе был раѥкрывающийѥя блок прямо там) ──
    do
        local pr1,pg1,pb1 = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr1*0.20,pg1*0.20,pb1*0.20,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr1*0.34,pg1*0.34,pb1*0.34,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr1*0.48,pg1*0.48,pb1*0.48,1.0))
        do local _pbm = prettyBtnPush(9.0)
        if imgui.Button(u8"\x20\x20\xc2\xe2\xe5\xf1\xf2\xe8\x20\xea\xf3\xf0\xf1\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x20\x20##openManualRates", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            imgui.OpenPopup("##manualRatesPopup")
        end
        prettyBtnPop(_pbm) end
        imgui.PopStyleColor(3)

        pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
        if imgui.BeginPopup("##manualRatesPopup") then
            imgui.TextColored(thDim(), u8"\xca\xf3\xf0\xf1\x20\xe2\xe0\xeb\xfe\xf2\x20\xe2\xf0\xf3\xf7\xed\xf3\xfe\x3a")
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            imgui.PushItemWidth(S(220))
            rateInputRow("az",  "AZ-Coins", St.rateAZBuf,  "rateAZ")
            rateInputRow("btc", "BTC",      St.rateBTCBuf, "rateBTC")
            rateInputRow("eur", u8"\xc5\xe2\xf0\xee", St.rateEURBuf, "rateEUR")
            rateInputRow("vc",  "VC$",       St.rateVCBuf,  "rateVC")
            rateInputRow("asc", u8"\xca\xf3\xf0\xf1 ASC", St.rateASCBuf, "rateASC")
            imgui.PopItemWidth()
            imgui.Spacing()
            do
                local pr2,pg2,pb2 = getAcc()
                imgui.PushStyleColor(imgui.Col.Button,        iv4(pr2*0.22,pg2*0.22,pb2*0.22,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr2*0.40,pg2*0.40,pb2*0.40,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr2*0.58,pg2*0.58,pb2*0.58,1.0))
                do local _pbd = prettyBtnPush(8.0)
                if imgui.Button(u8"\xc3\xee\xf2\xee\xe2\xee##closeManualRates", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                    imgui.CloseCurrentPopup()
                end
                prettyBtnPop(_pbd) end
                imgui.PopStyleColor(3)
            end
            imgui.EndPopup()
        end
    end
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- 2) переключитѥ раѥкладкѥ (ѥпиѥок / два ѥтолбика)
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
            St._financeSettingsOpen = false
        end
        prettyBtnPop(_pbc) end
        imgui.PopStyleColor(3)
    end
end

-- ── отделѥное окно панели наѥтроек вкладки "Финанѥы". Хо ѥмолчанию
-- приѥтыковано ѥправа от главного окна и двигаетѥя вмеѥте ѥ ним; кнопка
-- "Открепитѥ" позволяет ноѥитѥ его отделѥно в любом меѥте экрана ──
local function drawFinanceSettingsPanel()
    if not St._financeSettingsOpen then return end
    if not St._mainWinPos or not St._mainWinSize then return end

    local panelW = S(320)

    if not St._financeSettingsDetached then
        imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(4),  St._mainWinPos.y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Always)
    else
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Once)
        if _financeSettingsPos then
            imgui.SetNextWindowPos(imgui.ImVec2(_financeSettingsPos.x, _financeSettingsPos.y), imgui.Cond.Once)
        else
            imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(4),  St._mainWinPos.y), imgui.Cond.Once)
        end
    end

    applyStyle()
    -- (NoMove/NoResize umyshlenno ne ispolzuyutsya - ne vstrechayutsya bolshe nigde v
    -- etom fayle i mogli otsutstvovat v etoy sborke mimgui; Cond.Always vyshe i tak
    -- prinuditelno vozvraschaet okno na mesto kazhdyy kadr, poka ono ne otkrepleno)
    local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
    imgui.Begin("###financeSettingsPanel", nil, flags)
    imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

    if St._financeSettingsDetached then
        local okP, p = pcall(imgui.GetWindowPos)
        if okP and p then _financeSettingsPos = {x = p.x, y = p.y} end
    end

    -- ── ѥапка панели: заголовок + кнопка "Открепитѥ/Закрепитѥ" ──
    do
        local aw = imgui.GetContentRegionAvail().x
        imgui.TextColored(iv4(1,1,1,1), u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8 \xf4\xe8\xed\xe0\xed\xf1\xee\xe2")
        imgui.SameLine(math.max(0, aw - S(104)))
        local pr,pg,pb = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.22,pg*0.22,pb*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.40,pg*0.40,pb*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.58,pg*0.58,pb*0.58,1.0))
        local detachLbl = St._financeSettingsDetached
            and u8"\xc7\xe0\xea\xf0\xe5\xef\xe8\xf2\xfc"
            or  u8"\xce\xf2\xea\xf0\xe5\xef\xe8\xf2\xfc"
        if imgui.Button(detachLbl.."##financeDetachBtn", imgui.ImVec2(S(104), S(24))) then
            St._financeSettingsDetached = not St._financeSettingsDetached
            if St._financeSettingsDetached then
                local okP, p = pcall(imgui.GetWindowPos)
                if okP and p then _financeSettingsPos = {x = p.x, y = p.y} end
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


-- ── кнопка-копия итога "ВХЕГО ВХРТОВ" в чат: тоже вынеѥена отделѥно ──
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
    if St._resetCharScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()

        -- ── кнопки ѥправления вкладкой "Вѥего": подпиѥаны текѥтом, читаемый
        -- ѥрифт, толщина рамки 4px, ѥирина ѥчитаетѥя так, чтобы вѥе кнопки
        -- помещалиѥѥ в один ряд ──────────────────────────────────────────
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

        -- итог ѥчитаем толѥко по включённым в филѥтре категориям
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
                local baseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)
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

                -- кнопка-копия: вывеѥти "ВХЕГО ВХРТОВ" в чат (как белые кнопки на вкладке "Херѥонаж")
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
                -- фон полоѥы (более крѥпная, ѥ лёгкой рамкой ѥнизѥ) — так проще разглядетѥ ѥегменты
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
                        -- тонкий разделителѥ междѥ ѥегментами, чтобы было видно границы
                        if bx > p.x then
                            dl:AddLine(imgui.ImVec2(bx, by), imgui.ImVec2(bx, by+bh),
                                imgui.ColorConvertFloat4ToU32(iv4(0,0,0,0.35)), 1)
                        end
                        -- наведение мыѥѥю прямо на цвет в ѥамом графике — показываем процент
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

                -- легенда: толѥко цветной квадратик + название (без цифр); процент — во вѥплывающей подѥказке при наведении
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
            -- ── ДВХ ХТОЛБХХХ: ѥлева наличные/банк/депозит/ѥчета, ѥправа валюты ──
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

    -- ── нижний отѥтѥп, чтобы поѥледний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetCharScroll = false
end


-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 3: Š¯Š�Š�Š¢Š Š˛Š™Š�Š�
-- ============================================================
local function drawSettings(h, sw, sh)
    -- ĥ”€ĥ”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ Š¯Š�Š�Š¢Š Š˛Š•Š� (Š¾Š±ť‹ť‥Š½ť‹Š¹ ť�Šŗť€Š¾Š»Š»: ŠŗŠ¾Š»Šµť�Š¾ Š¼ť‹ť�Šø / ŠæŠ¾Š»Š¾ť�Š° Šæť€Š¾Šŗť€ť�ť‥ŠŗŠø) ĥ”€ĥ”€
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sset", imgui.ImVec2(0, h), false)
    if St._resetSettScroll then imgui.SetScrollY(0) end
            local r,g,b = getAcc()

        -- ĥ”€ĥ”€ Š Š�Š—Š�Š•Š  Š˛Š�Š¯Š� ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xee\xea\xed\xe0")
        local curWPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local curHPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        St.winWbuf[0] = curWPct
        St.winHbuf[0] = curHPct

        -- Š�Š°ť€ť‥Š¾ť‥ŠŗŠ° ť� Š´Š²ť�Š¼ť¸ ť�Š»Š°Š¹Š´Šµť€Š°Š¼Šø
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

                -- ŠåŠøť€ŠøŠ½Š°
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
                imgui.SliderFloat("##sw2", St.winWbuf, WIN_W_MIN, 0.98)
                if St.winWbuf[0] < WIN_W_MIN then St.winWbuf[0] = WIN_W_MIN end
                cfg.winWPct = St.winWbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(5)
                imgui.PopItemWidth()

                -- Š’ť‹ť�Š¾ť‥Š°
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
                imgui.SliderFloat("##sh2", St.winHbuf, WIN_H_MIN, 0.98)
                if St.winHbuf[0] < WIN_H_MIN then St.winHbuf[0] = WIN_H_MIN end
                cfg.winHPct = St.winHbuf[0]
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

        -- ĥ”€ĥ”€ Š Š�Š—Š�Š•Š  ŠåŠ Š�Š¤Š¢Š� ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xf8\xf0\xe8\xf4\xf2\xe0")
        do
            local curFS = cfg.fontSize > 0 and cfg.fontSize or 1.25
            St.fontSizeBuf[0] = curFS
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
                -- ŠŗŠ½Š¾ŠæŠŗŠø -/+ Š´Š»ť¸ ť‥Š¾ť‥Š½Š¾Š¹ Š½Š°ť�ť‥ť€Š¾Š¹ŠŗŠø
                stepBtn("fs_minus", "-", function()
                    cfg.fontSize = math.max(FONT_SIZE_MIN, math.floor((cfg.fontSize - 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)
                imgui.SameLine(0,4)
                stepBtn("fs_plus", "+", function()
                    cfg.fontSize = math.min(FONT_SIZE_MAX, math.floor((cfg.fontSize + 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
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
                if imgui.SliderFloat("##fsz2", St.fontSizeBuf, FONT_SIZE_MIN, FONT_SIZE_MAX) then
                    cfg.fontSize = math.floor(St.fontSizeBuf[0]*100+0.5)/100
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
                            St.custRbuf[0]=aR; St.custGbuf[0]=aG; St.custBbuf[0]=aB
                            St.rowBgRbuf[0]=bR; St.rowBgGbuf[0]=bG; St.rowBgBbuf[0]=bB
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

        -- превѥю цвета + кнопка, которая открывает вѥплывающее окно ѥ полноценным
        -- пикером цвета (вмеѥто огромного вѥтроенного пикера — короче, вѥё влезает в меню)
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
                    St.custRbuf[0]=_a[1]; St.custGbuf[0]=_a[2]; St.custBbuf[0]=_a[3]
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
                    _custPickerVec = imgui.new("float[3]", {St.custRbuf[0], St.custGbuf[0], St.custBbuf[0]})
                end
                _custPickerVec[0], _custPickerVec[1], _custPickerVec[2] = St.custRbuf[0], St.custGbuf[0], St.custBbuf[0]
                local okPicker = pcall(function()
                    imgui.PushItemWidth(S(220))
                    local flags = 0
                    pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
                    if imgui.ColorPicker3("##accentpicker", _custPickerVec, flags) then
                        St.custRbuf[0], St.custGbuf[0], St.custBbuf[0] = _custPickerVec[0], _custPickerVec[1], _custPickerVec[2]
                        cfg.custR=St.custRbuf[0]; cfg.custG=St.custGbuf[0]; cfg.custB=St.custBbuf[0]
                        saveCfg()
                    end
                    imgui.PopItemWidth()
                end)
                if not okPicker then
                    imgui.PushItemWidth(150)
                    if imgui.SliderFloat("R##cr2", St.custRbuf, 0.0, 1.0) then
                        cfg.custR=St.custRbuf[0]; cfg.custG=St.custGbuf[0]; cfg.custB=St.custBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("G##cg2", St.custGbuf, 0.0, 1.0) then
                        cfg.custR=St.custRbuf[0]; cfg.custG=St.custGbuf[0]; cfg.custB=St.custBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("B##cb2", St.custBbuf, 0.0, 1.0) then
                        cfg.custR=St.custRbuf[0]; cfg.custG=St.custGbuf[0]; cfg.custB=St.custBbuf[0]; saveCfg()
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
                St.rowBgRbuf[0]=_a2[1]; St.rowBgGbuf[0]=_a2[2]; St.rowBgBbuf[0]=_a2[3]
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
                    _rowBgPickerVec = imgui.new("float[3]", {St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0]})
                end
                _rowBgPickerVec[0], _rowBgPickerVec[1], _rowBgPickerVec[2] = St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0]
                local okPicker2 = pcall(function()
                    imgui.PushItemWidth(S(220))
                    local flags = 0
                    pcall(function() flags = imgui.ColorEditFlags.PickerHueBar + imgui.ColorEditFlags.DisplayHex end)
                    if imgui.ColorPicker3("##rowbgpickerwidget", _rowBgPickerVec, flags) then
                        St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0] = _rowBgPickerVec[0], _rowBgPickerVec[1], _rowBgPickerVec[2]
                        cfg.rowBgR=St.rowBgRbuf[0]; cfg.rowBgG=St.rowBgGbuf[0]; cfg.rowBgB=St.rowBgBbuf[0]
                        saveCfg()
                    end
                    imgui.PopItemWidth()
                end)
                if not okPicker2 then
                    imgui.PushItemWidth(150)
                    if imgui.SliderFloat("R##rbR", St.rowBgRbuf, 0.0, 1.0) then
                        cfg.rowBgR=St.rowBgRbuf[0]; cfg.rowBgG=St.rowBgGbuf[0]; cfg.rowBgB=St.rowBgBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("G##rbG", St.rowBgGbuf, 0.0, 1.0) then
                        cfg.rowBgR=St.rowBgRbuf[0]; cfg.rowBgG=St.rowBgGbuf[0]; cfg.rowBgB=St.rowBgBbuf[0]; saveCfg()
                    end
                    if imgui.SliderFloat("B##rbB", St.rowBgBbuf, 0.0, 1.0) then
                        cfg.rowBgR=St.rowBgRbuf[0]; cfg.rowBgG=St.rowBgGbuf[0]; cfg.rowBgB=St.rowBgBbuf[0]; saveCfg()
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

        -- ── ХВТО-ОБНОВЛЕНХЕ (перемещено ѥюда — в ѥамый низ) ─────────
        secTitle(u8"\xc0\xe2\xf2\xee-\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5")
        -- НЕ перезапиѥываем chkBuf каждый кадр
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

    -- ── нижний отѥтѥп, чтобы поѥледний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()

    St._resetSettScroll = false
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 4: Š˛ Š�Š�Š Š�Š�Š¢Š•  (Š²ť�Šµ Š±Š»Š¾ŠŗŠø ť� Šŗť€Š°ť�ŠøŠ²Š¾Š¹ ť€Š°Š¼ŠŗŠ¾Š¹)
-- ============================================================
local function drawAbout(h)
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    -- ubrali NoScrollbar/NoScrollWithMouse: teper mozhno prokrutit koleskom
    -- myshi ili polosoy sprava, esli tekst ne pomeshchaetsya v okno
    imgui.BeginChild("##sabout", imgui.ImVec2(0,h), false)
    if St._resetSettScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()
        local rra,rga,rba = getRowBgColor()
        local dl_a  = imgui.GetWindowDrawList()

        -- Š‥Š°Š½Š½Šµť€
        imgui.Spacing()
        local bannerH = SFtext(86)
        local ps_a    = imgui.GetCursorScreenPos()
        local aw_a    = imgui.GetContentRegionAvail().x
        -- Š¤Š¾Š½ Š±Š°Š½Š½Šµť€Š° ť€ŠµŠ°Š³Šøť€ť�Šµť‥ Š½Š° rowBg
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
        -- Š±Š¾Š»ŠµŠµ ť‥Š¾Š»ť�ť‥Š°ť¸ Šø ť¸ť€ŠŗŠ°ť¸ Š¾Š±Š²Š¾Š´ŠŗŠ° Š±Š°Š½Š½Šµť€Š°
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 14, 0, 3.0)
        -- Š²Š½Šµť�Š½ŠøŠ¹ ť�Š²Šµť‥ (glow effect)
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x-2,      ps_a.y-2),
            imgui.ImVec2(ps_a.x+aw_a+2, ps_a.y+bannerH+2),
            imgui.ColorConvertFloat4ToU32(iv4(r*0.70,g*0.70,b*0.70,0.45)), 16, 0, 1.5)
        -- Š²Šµť€ť…Š½ť¸ť¸ Š°Šŗť†ŠµŠ½ť‥Š½Š°ť¸ ŠæŠ¾Š»Š¾ť�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+3),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 2)
        -- Š½ŠøŠ¶Š½ť¸ť¸ Š°Šŗť†ŠµŠ½ť‥Š½Š°ť¸ ŠæŠ¾Š»Š¾ť�ŠŗŠ°
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x+20,      ps_a.y+bannerH-3),
            imgui.ImVec2(ps_a.x+aw_a-20, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,0.7)), 2)
        -- ť¸ť€ŠŗŠ¾ť�ť‥ť� ť„Š¾Š½Š° Š±Š°Š½Š½Šµť€Š° Š´Š»ť¸ Š°Š´Š°Šæť‥Š°ť†ŠøŠø ť‥ŠµŠŗť�ť‥Š°
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

        -- Š�Š°ť€ť‥Š¾ť‥ŠŗŠ° ť€Š°Š·ť€Š°Š±Š¾ť‥ť‥ŠøŠŗŠ°
        secTitle(u8"\xd0\xe0\xe7\xf0\xe0\xe1\xee\xf2\xf7\xe8\xea")
        infoCard("##devcard", 100, function(aw, ch)
            -- Š¯ŠøŠŗ
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(10)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcd\xe8\xea \xe2 \xe8\xe3\xf0\xe5:")
            imgui.SameLine(0,8)
            imgui.TextColored(thAccBright(), "Marco_Santiago")
            -- Š’Šµť€ť�Šøť¸ + Š�ť€Š¾ŠµŠŗť‥
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(40)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc2\xe5\xf0\xf1\xe8\xff:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v1.1.0")
            imgui.SameLine(0,14)
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcf\xf0\xee\xe5\xea\xf2:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.90,0.90,0.90,1.0), "Arizona RP PC")
            -- Š¢ŠøŠæ ť�Šŗť€ŠøŠæť‥Š°
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(70)))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0), "MoonLoader Lua Script")
        end)

        -- Š�Š°ť€ť‥Š¾ť‥ŠŗŠ° ť�Š²ť¸Š·Šø ĥ€” Telegram ť� ŠŗŠ¾Š¼ŠæŠ°Šŗť‥Š½Š¾Š¹ ŠŗŠ½Š¾ŠæŠŗŠ¾Š¹
        secTitle(u8"\xd1\xe2\xff\xe7\xfc")
        infoCard("##tgcard", 100, function(aw, ch)
            -- "Telegram:" Š»ŠµŠ¹Š±Š» + Š½ŠøŠŗ + ŠŗŠ½Š¾ŠæŠŗŠ° ŠŗŠ¾ŠæŠøť€Š¾Š²Š°ť‥ť� Š½Š° Š¾Š´Š½Š¾Š¹ ť�ť‥ť€Š¾ŠŗŠµ
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(14)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), "Telegram:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.18,0.75,0.98,1.0), "@Marco8877")
            imgui.SameLine(0,10)
            -- Š�Š¾Š¼ŠæŠ°Šŗť‥Š½Š°ť¸ ŠŗŠ½Š¾ŠæŠŗŠ° ŠŗŠ¾ŠæŠøť€Š¾Š²Š°Š½Šøť¸
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

        -- Š�Š°ť€ť‥Š¾ť‥ŠŗŠ° Š¾ ť�Šŗť€ŠøŠæť‥Šµ
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
        -- Š²ť‹ť�Š¾ť‥Š° ŠŗŠ°ť€ť‥Š¾ť‥ŠŗŠø Š±Š°Š·Š¾Š²Š°ť¸ ŠæŠ¾Š´ 2 Š²ť�ť‥ť�ŠæŠ½ť‹ť… + Š·Š°Š³Š¾Š»Š¾Š²Š¾Šŗ + Š²ť�Šµ Š±ť�Š»Š»Šµť‥ť‹ + Š½ŠøŠ¶Š½ŠøŠ¹ Š¾ť‥ť�ť‥ť�Šæ,
        -- ť‥ť‥Š¾Š±ť‹ Šæť€Šø Š±Š¾Š»ť�ť¨Š¾Š¼ ť€Š°Š·Š¼Šµť€Šµ ť¨ť€Šøť„ť‥Š° Š½Šøť‥ŠµŠ³Š¾ Š½Šµ Š¾Š±ť€ŠµŠ·Š°Š»Š¾ť�ť�
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

        -- ── Харточка "Обновления": проверка верѥии на GitHub + ѥкачивание ──
        secTitle(u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff")
        do
            local hasUpdBtn = (_updState == "available")
            local updCardH  = hasUpdBtn and 118 or 78
            infoCard("##updcard", updCardH, function(aw, ch)
                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(14)))
                imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xd2\xe5\xea\xf3\xf9\xe0\xff \xe2\xe5\xf0\xf1\xe8\xff:")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), SCRIPT_VERSION)
                if _updRemoteVer then
                    imgui.SameLine(0,16)
                    imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xed\xe0 GitHub:")
                    imgui.SameLine(0,8)
                    local newer = versionGreater(_updRemoteVer, SCRIPT_VERSION)
                    imgui.TextColored(newer and iv4(1.0,0.84,0.20,1.0) or iv4(0.45,0.90,0.55,1.0), _updRemoteVer)
                end

                imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(40)))
                do
                    local busy  = _updChecking
                    local btnBg = busy and {0.85,0.68,0.15} or {0.30,0.55,0.90}
                    local lbl   = busy and u8"  \xef\xf0\xee\xe2\xe5\xf0\xea\xe0..."
                                        or  u8"  \xcf\xf0\xee\xe2\xe5\xf0\xe8\xf2\xfc \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff"
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(btnBg[1]*0.55,btnBg[2]*0.55,btnBg[3]*0.55,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(btnBg[1]*0.75,btnBg[2]*0.75,btnBg[3]*0.75,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(btnBg[1],btnBg[2],btnBg[3],1.0))
                    do local _pbu = prettyBtnPush(8.0)
                    if imgui.Button(lbl.."##checkUpdBtn", imgui.ImVec2(aw - SFtext(32), S(30))) then
                        checkForUpdates()
                    end
                    prettyBtnPop(_pbu) end
                    imgui.PopStyleColor(3)
                end

                if _updMsg ~= "" then
                    imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(76)))
                    local msgCol = (_updState == "error") and iv4(0.95,0.45,0.40,1.0)
                        or (_updState == "available") and iv4(1.0,0.84,0.20,1.0)
                        or iv4(0.60,0.85,0.65,1.0)
                    imgui.TextColored(msgCol, u8(_updMsg))
                end

                if hasUpdBtn then
                    imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(100)))
                    local busyD  = _updDownloading
                    local btnBg2 = busyD and {0.85,0.68,0.15} or {0.25,0.85,0.45}
                    local lbl2   = busyD and u8"  \xf1\xea\xe0\xf7\xe8\xe2\xe0\xed\xe8\xe5..."
                                          or  u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc"
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(btnBg2[1]*0.55,btnBg2[2]*0.55,btnBg2[3]*0.55,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(btnBg2[1]*0.75,btnBg2[2]*0.75,btnBg2[3]*0.75,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(btnBg2[1],btnBg2[2],btnBg2[3],1.0))
                    do local _pbu2 = prettyBtnPush(8.0)
                    if imgui.Button(lbl2.."##doUpdateBtn", imgui.ImVec2(aw - SFtext(32), S(30))) then
                        downloadUpdate()
                    end
                    prettyBtnPop(_pbu2) end
                    imgui.PopStyleColor(3)
                end
            end)
        end

    -- ── нижний отѥтѥп, чтобы поѥледний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetSettScroll = false
end

-- ============================================================
--  Š‥Š›Š�Š’Š¯Š˛Š• Š˛Š�Š¯Š˛
-- ============================================================
imgui.OnFrame(
    function() return St.winOpen end,
    function(self)
        -- FIX: ť�Š±ť€Š°ť�ť‹Š²Š°ŠµŠ¼ ť�ť‥ť‥ť‥ť‥ŠøŠŗŠø ť�Š½ŠøŠŗŠ°Š»ť�Š½ť‹ť… ID Š² Š½Š°ť‥Š°Š»Šµ ŠŗŠ°Š¶Š´Š¾Š³Š¾ ŠŗŠ°Š´ť€Š°
        St._metricTileIdx = 0
        St._chipIdx = 0
        St.chipSide = false
        local sw = imgui.GetIO().DisplaySize.x
        local sh = imgui.GetIO().DisplaySize.y

        -- Š°Š²ť‥Š¾Š¼Š°ť�ť¨ť‥Š°Š± Š²ť�ŠµŠ³Š¾ UI ŠæŠ¾Š´ ť‥ŠµŠŗť�ť‰ŠµŠµ ť€Š°Š·ť€Šµť¨ŠµŠ½ŠøŠµ (Š±Š°Š·Š° 1080p)
        if sh > 0 then
            St.UI_SCALE = math.max(St.UI_SCALE_MIN, math.min(St.UI_SCALE_MAX, sh / 1080.0))
        end

        -- Šµť�Š»Šø ť€Š°Š·ť€Šµť¨ŠµŠ½ŠøŠµ/ť€Š°Š·Š¼Šµť€ ŠøŠ³ť€Š¾Š²Š¾Š³Š¾ Š¾ŠŗŠ½Š° ŠøŠ·Š¼ŠµŠ½ŠøŠ»Š¾ť�ť� (Š²ť‹ť¨ŠµŠ» ŠøŠ· Š¾ŠŗŠ½Š° / ť�Š¼ŠµŠ½ŠøŠ» ť€Š°Š·ť€Šµť¨ŠµŠ½ŠøŠµ) ĥ€”
        -- Š·Š°ť�ť‥Š°Š²Š»ť¸ŠµŠ¼ ŠæŠµť€Šµť�ť‥Šøť‥Š°ť‥ť� ť€Š°Š·Š¼Šµť€ ŠøŠ¼ŠæŠ»ť�ť‥-Š¾ŠŗŠ½Š°, ŠøŠ½Š°ť‥Šµ Cond.Once Š±Š¾Š»ť�ť¸Šµ Š½Šµ Š´Š°ť�ť‥ ŠµŠ¼ť� ŠøŠ·Š¼ŠµŠ½Šøť‥ť�ť�ť¸
        if math.abs(sw - St._lastSw) > 2 or math.abs(sh - St._lastSh) > 2 then
            if St._lastSw > 0 then _sw_win_init = nil end
            St._lastSw, St._lastSh = sw, sh
        end

        local wPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local hPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        local ww   = math.floor(sw * wPct)
        local wh   = math.floor(sh * hPct)
        -- Š¶ť‥ť�ť‥ŠŗŠøŠµ Š³ť€Š°Š½Šøť†ť‹, ť‥ť‥Š¾Š±ť‹ Š¾ŠŗŠ½Š¾ Š½Šµ ť�ť‥Š°Š»Š¾ Šŗť€Š¾ť¨Šµť‥Š½ť‹Š¼ Š½Š° Š¼Š°Š»ŠµŠ½ť�ŠŗŠøť… ť€Š°Š·ť€Šµť¨ŠµŠ½Šøť¸ť… (Š½Š°Šæť€. 1280x720)
        -- ŠøŠ»Šø Š½Šµ Š²ť‹Š»ŠµŠ·Š»Š¾ Š·Š° Šæť€ŠµŠ´ŠµŠ»ť‹ ť�Šŗť€Š°Š½Š° Š½Š° ť�Š²Šµť€ť…ť¨Šøť€Š¾ŠŗŠøť… Š¼Š¾Š½Šøť‥Š¾ť€Š°ť…
        ww = math.max(math.floor(sw * 0.30), math.min(ww, math.floor(sw * 0.98)))
        wh = math.max(math.floor(sh * 0.35), math.min(wh, math.floor(sh * 0.95)))

        if not _sw_win_init then
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Always)
            imgui.SetNextWindowPos(imgui.ImVec2(sw*0.5, sh*0.5), imgui.Cond.Always, imgui.ImVec2(0.5,0.5))
            _sw_win_init = true
        else
            imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Once)
        end

        -- ── анимированный ѥдвиг главного окна влево, пока открыта (и
        -- приѥтыкована) панелѥ наѥтроек "Финанѥы"; двигаем окно толѥко
        -- на кадрах, где фаза анимации реалѥно меняетѥя, чтобы в оѥталѥное
        -- время окно оѥтавалоѥѥ ѥвободно перетаѥкиваемым мыѥѥю ──
        do
            local tnow = os.clock()
            if St._finShiftLastTime == nil then St._finShiftLastTime = tnow end
            local dt = tnow - St._finShiftLastTime
            St._finShiftLastTime = tnow
            if dt < 0 or dt > 0.5 then dt = 0 end -- защита от ѥкачков (первый кадр / лаги)

            local target = (St._financeSettingsOpen and not St._financeSettingsDetached) and 1.0 or 0.0
            local speed  = 6.0 -- ѥкороѥтѥ анимации, полный ѥдвиг за ~1/speed ѥек
            if St._finShiftAnim < target then
                St._finShiftAnim = math.min(target, St._finShiftAnim + dt*speed)
            elseif St._finShiftAnim > target then
                St._finShiftAnim = math.max(target, St._finShiftAnim - dt*speed)
            end

            local finShiftPx = S(60)  * St._finShiftAnim -- ѥирина панели (320) + отѥтѥп (10)
            local deltaPx    = finShiftPx - St._finShiftAppliedPx
            St._finShiftAppliedPx = finShiftPx

            if math.abs(deltaPx) > 0.01 and St._mainWinPos then
                imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x - deltaPx, St._mainWinPos.y), imgui.Cond.Always)
            end
        end

        applyStyle()
        -- Š¼Š°ť�ť�ť‥Š°Š± ť�ť€Šøť„ť‥Š°: Šæť€ŠøŠ¼ŠµŠ½ť¸ŠµŠ¼ ť‥Šµť€ŠµŠ· SetWindowFontScale ŠæŠ¾ť�Š»Šµ Begin
        -- Š¯Š° Š�Š� Š¾ŠŗŠ½Š¾ Š¼Š¾Š¶Š½Š¾ Š´Š²ŠøŠ³Š°ť‥ť� Šø Š¼ŠµŠ½ť¸ť‥ť� ť€Š°Š·Š¼Šµť€ Š¼ť‹ť�ŠŗŠ¾Š¹ (Š½Š° Š¼Š¾Š±ŠøŠ»Šµ ť¨ť‥Š¾
        -- Š±ť‹Š»Š¾ Š¾ť‥ŠŗŠ»ťˇť‥ŠµŠ½Š¾, ť‥ť‥Š¾Š±ť‹ ť�Š»ť�ť‥Š°Š¹Š½ť‹Šµ ť‥Š°Šæť‹ Š½Šµ Š´Š²ŠøŠ³Š°Š»Šø Š¾ŠŗŠ½Š¾ Š½Š° ť‥Š°ť‥ť�Šŗť€ŠøŠ½Šµ)
        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
        imgui.Begin("###sw", nil, flags)
        imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

        -- ĥ”€ĥ”€ Š�Š�Š�Š¢Š˛Š�Š¯Š«Š™ Š—Š�Š‥Š˛Š›Š˛Š’Š˛Š� ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
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

        -- ĥ”€ĥ”€ Š’Š�Š›Š�Š”Š�Š� (Š�Š�Š�Š«Š�Š� Š�Š•Š Š’Š«Š�Š�) ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
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
                if tabButton(td[1], St.activeTab==i, tw, td[2],td[3],td[4]) then
                    if St.activeTab ~= i then St._resetCharScroll = true; St._resetSettScroll = true; St.accPopupOpen = false end
                    St.activeTab=i
                end
            end
        end

        -- Š´ŠµŠŗŠ¾ť€Š°ť‥ŠøŠ²Š½Š°ť¸ Š»ŠøŠ½Šøť¸ ŠæŠ¾Š´ Š²ŠŗŠ»Š°Š´ŠŗŠ°Š¼Šø
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

        -- ĥ”€ĥ”€ ŠåŠ�Š�Š�Š� Š�Š•Š Š�Š˛Š¯Š�Š–Š� (ť‥Š¾Š»ť�ŠŗŠ¾ Š½Š° Š²ŠŗŠ»Š°Š´ŠŗŠµ 1) ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        if St.activeTab == 1 and St.statsData and St.statsData.name ~= "" then
            local r2,g2,b2 = getAcc()
            local rr2,rg2,rb2 = getRowBgColor()
            local dl2 = imgui.GetWindowDrawList()
            local ph  = imgui.GetCursorScreenPos()
            local aw  = imgui.GetContentRegionAvail().x
            local hdrH = S(60)
            -- ť„Š¾Š½ ť�Š°ŠæŠŗŠø: ť€ŠµŠ°Š³Šøť€ť�Šµť‥ Š½Š° rowBg
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
            -- Š»ŠµŠ²Š°ť¸ Š°Šŗť†ŠµŠ½ť‥Š½Š°ť¸ ŠæŠ¾Š»Š¾ť�Š°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x,   ph.y+6),
                imgui.ImVec2(ph.x+4, ph.y+hdrH-6),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,1.0)), 2)
            -- Š²Šµť€ť…Š½ť¸ť¸ ť‥Š¾Š½ŠŗŠ°ť¸ ŠæŠ¾Š»Š¾ť�ŠŗŠ°
            dl2:AddRectFilled(
                imgui.ImVec2(ph.x+12,    ph.y),
                imgui.ImVec2(ph.x+aw-12, ph.y+2),
                imgui.ColorConvertFloat4ToU32(iv4(r2,g2,b2,0.85)), 2)
            -- ť¸ť€ŠŗŠ¾ť�ť‥ť� ť„Š¾Š½Š° ť�Š°ŠæŠŗŠø Š´Š»ť¸ Š°Š´Š°Šæť‥Š°ť†ŠøŠø ť†Š²Šµť‥Š° ť‥ŠµŠŗť�ť‥Š°
            local hdrBright = hdrBgR*0.299 + hdrBgG*0.587 + hdrBgB*0.114
            local hdrLabelCol = hdrBright > 0.35 and iv4(0.10,0.10,0.15,1.0) or thDim()
            local hdrTextCol  = hdrBright > 0.35 and iv4(0.05,0.05,0.10,1.0) or iv4(0.48,0.48,0.55,1.0)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild("##hdr", imgui.ImVec2(aw, hdrH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                -- Š�ť‥ť€Š¾ŠŗŠ° 1: Š�Š•Š Š�Š˛Š¯Š�Š– + ŠøŠ¼ť¸ + Š½Š¾Š¼Šµť€ Š°ŠŗŠŗŠ°ť�Š½ť‥Š°
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(6)))
                imgui.TextColored(hdrLabelCol, u8"\xcf\xc5\xd0\xd1\xce\xcd\xc0\xc6")
                imgui.SameLine(0,7)
                imgui.TextColored(thAccBright(), u8(St.statsData.name))
                if St.statsData.accountNumber~="" then
                    imgui.SameLine(0,7)
                    imgui.TextColored(hdrTextCol, "["..St.statsData.accountNumber.."]")
                end
                -- Š�ť‥ť€Š¾ŠŗŠ° 2: Š£ť€. + EXP + HP
                imgui.SetCursorPos(imgui.ImVec2(S(14), S(28)))
                if St.statsData.level~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), u8"\xd3\xf0.")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thGold(), u8(St.statsData.level))
                    imgui.SameLine(0,14)
                end
                if St.statsData.respect~="" then
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "EXP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(thAcc(), u8(St.statsData.respect))
                    imgui.SameLine(0,14)
                end
                if St.statsData.health~="" then
                    local hp    = tonumber((St.statsData.health or ""):match("%d+")) or 100
                    local maxhp = tonumber((St.statsData.health or ""):match("/(%d+)")) or 100
                    local hcol  = hp>=80 and thGreen() or hp>=40 and thGold() or thRed()
                    imgui.TextColored(iv4(0.55,0.58,0.68,1.0), "HP:")
                    imgui.SameLine(0,4)
                    imgui.TextColored(hcol, u8(St.statsData.health))
                    -- Š¼ŠøŠ½Šø HP-Š±Š°ť€
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

        -- ť�ť‥Š°ť‥ť�ť� Š·Š°Š³ť€ť�Š·ŠŗŠø
        if St.waitingStats then
            imgui.TextColored(thGold(), u8"  \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            imgui.Spacing()
        elseif St.statusMsg ~= "" and St.statusMsg ~= u8"\xc3\xee\xf2\xee\xe2\xee" then
            imgui.TextColored(thGold(), "  "..St.statusMsg)
            imgui.Spacing()
        end

        -- ĥ”€ĥ”€ Š�Š•Š¢Š Š�Š�Š� (ť‥Š¾Š»ť�ŠŗŠ¾ Š²ŠŗŠ»Š°Š´ŠŗŠø 1-2) ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        if St.statsData and St.activeTab <= 2 then
            local s    = St.statsData
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

        -- ĥ”€ĥ”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        local contentH = imgui.GetContentRegionAvail().y - 46 - 20

        if St.activeTab == 4 then
            drawSettings(contentH, sw, sh)
        elseif St.activeTab == 5 then
            drawAbout(contentH)
        elseif St.activeTab == 3 and St.statsData then
            drawTotal(St.statsData, contentH)
        elseif not St.statsData then
            imgui.Spacing()
            if St.waitingStats then
                imgui.TextColored(thGold(), u8"  \xc7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            elseif St.statusMsg ~= "" then
                imgui.TextColored(thGold(), "  "..St.statusMsg)
            else
                imgui.TextColored(thDim(), u8"  \xcd\xe0\xe6\xec\xe8\xf2\xe5 \"\xce\xe1\xed\xee\xe2\xe8\xf2\xfc\" \xe4\xeb\xff \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe8 \xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xe8")
            end
        else
            local s = St.statsData
            if     St.activeTab == 1 then drawChar(s, contentH)
            elseif St.activeTab == 2 then drawBattle(s, contentH)
            end
        end

        imgui.Spacing()
        if St.activeTab == 4 then
            imgui.Dummy(imgui.ImVec2(0, S(10)))
        end

        -- ĥ”€ĥ”€ Š¯Š�Š–Š¯Š�Š• Š�Š¯Š˛Š�Š�Š� ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€ĥ”€
        local r4,g4,b4 = getAcc()
        do
            if St.activeTab == 5 then
                -- Š’ŠŗŠ»Š°Š´ŠŗŠ° "Š¾ ť�Šŗť€ŠøŠæť‥Šµ": Š¢Š¾Š»ť�ŠŗŠ¾ Š—Š°Šŗť€ť‹ť‥ť� (Š²Š¾ Š²ť�ťˇ ť¨Šøť€ŠøŠ½ť�, Š±ŠµŠ· ŠŗŠ½Š¾ŠæŠŗŠø Š�Š±Š½Š¾Š²Šøť‥ť�)
                local awClose = imgui.GetContentRegionAvail().x
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
                if imgui.Button(u8"  \xc7\xe0\xea\xf0\xfb\xf2\xfc  ", imgui.ImVec2(awClose, S(40))) then
                    St.winOpen=false; St.activeTab=1; _sw_win_init=nil
                end
                imgui.PopStyleColor(3)
            else
                local bw = (imgui.GetContentRegionAvail().x - 6) * 0.5
                if St.activeTab == 4 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š½Š°ť�ť‥ť€Š¾ŠµŠŗ: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±ť€Š¾ť� + Š—Š°Šŗť€ť‹ť‥ť�
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.12,0.12,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.78,0.18,0.18,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(1.0, 0.25,0.25,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1\xe8\xf2\xfc \xe2\xf1\xb8  ", imgui.ImVec2(bw, S(40))) then
                        cfg.winWPct    = 0.60; cfg.winHPct   = 0.76
                        cfg.custR      = -1;   cfg.custG      = -1;   cfg.custB = -1
                        cfg.rowBgR     = -1;   cfg.rowBgG     = -1;   cfg.rowBgB= -1
                        cfg.fontSize   = 1.25
                        St.winWbuf[0]=0.60; St.winHbuf[0]=0.76
                        St.fontSizeBuf[0] = 1.25
                        local a = getTheme().acc
                        St.custRbuf[0]=a[1]; St.custGbuf[0]=a[2]; St.custBbuf[0]=a[3]
                        St.rowBgRbuf[0]=a[1]; St.rowBgGbuf[0]=a[2]; St.rowBgBbuf[0]=a[3]
                        _sw_win_init=nil; saveCfg()
                    end
                    imgui.PopStyleColor(3)
                elseif St.activeTab == 3 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š¤ŠøŠ½Š°Š½ť�ť‹: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±ť€Š¾ť� Šŗť�ť€ť�Š° Š²Š°Š»ť�ť‥ (Š²Š¼Šµť�ť‥Š¾ Š�Š±Š½Š¾Š²Šøť‥ť�)
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(0.55,0.35,0.05,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.75,0.50,0.08,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.95,0.65,0.12,1.0))
                    if imgui.Button(u8"  \xd1\xe1\xf0\xee\xf1 \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2  ", imgui.ImVec2(bw, S(40))) then
                        cfg.rateAZ = 35000.0; cfg.rateBTC = 0.0; cfg.rateEUR = 0.0
                        cfg.rateVC = 0.0;     cfg.rateASC = 0.0
                        St.rateAZBuf[0]  = 35000; St.rateBTCBuf[0] = 0; St.rateEURBuf[0] = 0
                        St.rateVCBuf[0]  = 0;     St.rateASCBuf[0] = 0
                        St._cefLastResult = ""
                        saveCfg()
                        pcall(sampAddChatMessage, "{FFAA00}[Stats] \xea\xf3\xf0\xf1\xfb \xe2\xe0\xeb\xfe\xf2 \xf1\xe1\xf0\xee\xf8\xe5\xed\xfb \xea \xe7\xed\xe0\xf7\xe5\xed\xe8\xff\xec \xef\xee \xf3\xec\xee\xeb\xf7\xe0\xed\xe8\xfe", -1)
                    end
                    imgui.PopStyleColor(3)
                else
                    -- ŠŸŠµť€ť�Š¾Š½Š°Š¶/Š‥Š¾ť¹: ŠŗŠ½Š¾ŠæŠŗŠ° Š˛Š±Š½Š¾Š²Šøť‥ť�
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
                    St.winOpen=false; St.activeTab=1; _sw_win_init=nil
                end
                imgui.PopStyleColor(3)
            end
        end

        do
            local okP, p = pcall(imgui.GetWindowPos)
            local okS, s = pcall(imgui.GetWindowSize)
            if okP and okS then St._mainWinPos, St._mainWinSize = p, s end
        end
        imgui.End()

        drawFinanceSettingsPanel()
    end
)

-- ============================================================
--  Š—Š�Š�Š Š˛Š� Š�Š¢Š�Š¢Š�Š�Š¢Š�Š�Š�
-- ============================================================
function requestStats()
    if St.waitingStats then return end
    if not isSampAvailable() then
        St.statusMsg = u8"\xd1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    St.waitingStats    = true
    captureStarted  = false
    lastReqTime     = now()
    lastTdTime      = now()
    tdCollector     = {}
    tdCollectorSize = 0
    -- St.statsData Š¯Š• ť�Š±ť€Š°ť�ť‹Š²Š°ŠµŠ¼ ĥ€” ť�ť‥Š°ť€ť‹Šµ Š´Š°Š½Š½ť‹Šµ Š²ŠøŠ´Š½ť‹ ŠæŠ¾ŠŗŠ° Š½Šµ ŠæŠ¾Š»ť�ť‥ŠøŠ¼ Š½Š¾Š²ť‹Šµ
    St.statusMsg       = u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
    lua_thread.create(function()
        wait(300)
        local ok, err = pcall(sampSendChat, "/stats")
        if not ok then
            St.waitingStats = false
            St.statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xea\xee\xec\xe0\xed\xe4\xfb: " .. tostring(err)
        end
    end)
end

local function finalize()
    if not St.waitingStats or finalizing then return end
    finalizing = true
    -- Š·Š°ť‰Šøť‥Š° Š¾ť‥ Šæť�ť�ť‥Š¾Š³Š¾ ŠŗŠ¾Š»Š»ŠµŠŗť‥Š¾ť€Š°
    if next(tdCollector) == nil then
        St.waitingStats = false
        finalizing = false  -- Š˛Š‥ŠÆŠ—Š�Š¢Š•Š›Š¬Š¯Š˛ ť�Š±ť€Š°ť�ť‹Š²Š°ŠµŠ¼ ť„Š»Š°Š³!
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
        St.statsData=parseStats(raw)
        St.statusMsg=u8"\xc3\xee\xf2\xee\xe2\xee"
    else
        St.statusMsg=u8"\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5"
    end
    St.waitingStats=false; captureStarted=false; tdCollector={}; tdCollectorSize=0
    finalizing = false
end

-- ============================================================
--  Š˛Š‥Š Š�Š‥Š˛Š¢Š§Š�Š�Š� SAMP
-- ============================================================
function sampev.onShowDialog(id, style, title, btn1, btn2, text)
    -- ── автообновление кѥрѥа валют через телефон (ѥм. fetchRatesViaCEF):
    -- 1) "opening"    — на первом экране телефона выбираем поѥледний пѥнкт
    --                   ѥпиѥка. Хо ѥловам полѥзователя это 4-я вкладка
    --                   (индекѥ 3, еѥли ѥчитатѥ ѥ 0) — пробѥем её первой,
    --                   но еѥли пѥнктов менѥѥе 4 — берём поѥледний;
    -- 2) "last_tab"   — на этой вкладке ищем пѥнкт "Хриптовалюта" и жмём;
    -- 3) "crypto_menu"— открылоѥѥ меню ѥ кѥрѥами, разбираем текѥт, ѥохраняем
    --                   и закрываем диалог(и), возвращая игрока в игрѥ ──
    if _phoneFetchState then
        -- диагноѥтика: пока идёт автообновление, пиѥем в чат ID/ѥтилѥ/
        -- заголовок и кѥѥок текѥта ХХЖДОГО диалога, который видит ѥкрипт.
        -- Еѥли поѥле нажатия "Обновитѥ кѥрѥы" в чате вообще ничего не
        -- появляетѥя ѥ пометкой [Stats:phone] — значит ѥкрипт не полѥчает
        -- от игры ни одного диалога (телефон открываетѥя не через
        -- ѥтандартный SAMP-диалог), и реѥатѥ это нѥжно ѥже дрѥгим ѥпоѥобом.
        pcall(function()
            local dbgTitle = stripColor(tostring(title or ""))
            local dbgText  = stripColor(tostring(text or "")):gsub("\n", " | ")
            if #dbgText > 90 then dbgText = dbgText:sub(1, 90) .. "..." end
            pcall(sampAddChatMessage, ("{00CCFF}[Stats:phone] id=%s style=%s title=%s text=%s")
                :format(tostring(id), tostring(style), dbgTitle, dbgText), -1)
        end)

        local handled = false
        pcall(function()
            local tX = tostring(text or "")

            if _phoneFetchState == "opening" then
                local lastIdx = lastPhoneListIndex(tX)
                local targetIdx = (lastIdx and lastIdx >= 3) and 3 or lastIdx
                if targetIdx then
                    _phoneFetchState = "last_tab"
                    pcall(sampSendDialogResponse, id, 1, targetIdx, "")
                    handled = true
                end

            elseif _phoneFetchState == "last_tab" then
                local idx = findPhoneListIndex(tX, {"\xea\xf0\xe8\xef\xf2\xee", "\xe2\xe0\xeb\xfe\xf2"})
                if idx then
                    _phoneFetchState = "crypto_menu"
                    pcall(sampSendDialogResponse, id, 1, idx, "")
                    handled = true
                else
                    _phoneFetchState = false
                    _cefFetching = false
                    St._cefLastResult = "\xed\xe5 \xed\xe0\xe9\xe4\xe5\xed \xef\xf3\xed\xea\xf2 \\\"\xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0\\\" \xed\xe0 \xef\xee\xf1\xeb\xe5\xe4\xed\xe5\xe9 \xe2\xea\xeb\xe0\xe4\xea\xe5"
                    pcall(sampAddChatMessage, "{FF9900}[Stats] " .. tostring(St._cefLastResult), -1)
                    pcall(sampCloseCurrentDialog, -1)
                    handled = true
                end

            elseif _phoneFetchState == "crypto_menu" then
                local got = parsePhoneRatesText(tX)
                _phoneFetchState = false
                if got then
                    St._cefLastResult = "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] " .. "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                else
                    St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xea\xf3\xf0\xf1\xfb \xe2 \xee\xf2\xea\xf0\xfb\xf2\xee\xec \xf0\xe0\xe7\xe4\xe5\xeb\xe5"
                    pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
                end
                -- закрываем меню кѥрѥов и ѥамѥ вкладкѥ телефона, чтобы не
                -- оѥтавлятѥ телефон открытым поверх интерфейѥа игрока
                pcall(sampCloseCurrentDialog, -1)
                lua_thread.create(function()
                    wait(150)
                    pcall(sampCloseCurrentDialog, -1)
                end)
                handled = true
            end
        end)
        if handled then
            if not _phoneFetchState then _cefFetching = false end
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
                -- ť�Šŗť€ť‹Š²Š°ŠµŠ¼ Š´ŠøŠ°Š»Š¾Š³ Šµť�Š»Šø ť�Šŗť€ŠøŠæť‥ ť�Š°Š¼ ŠµŠ³Š¾ Š·Š°Šæť€Š¾ť�ŠøŠ»
                if St.waitingStats then isStatsDialog = true end
                St.statsData       = parseStats(cleaned)
                St.statusMsg       = u8"\xc3\xee\xf2\xee\xe2\xee"
                St.waitingStats    = false
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
    -- Š¾Š±ť€Š°Š±Š°ť‥ť‹Š²Š°ŠµŠ¼ Š¢Š˛Š›Š¬Š�Š˛ ŠŗŠ¾Š³Š´Š° Š°Šŗť‥ŠøŠ²Š½Š¾ Š¶Š´ť‥Š¼ Š¾ť‥Š²Šµť‥ /stats
    if not St.waitingStats then return end
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
            -- Š·Š°ť‰Šøť‥Š° Š¾ť‥ ŠæŠµť€ŠµŠæŠ¾Š»Š½ŠµŠ½Šøť¸: Šøť�ŠæŠ¾Š»ť�Š·ť�ŠµŠ¼ ť�ť‥ť‥ť‥ť‥ŠøŠŗ Š²Š¼Šµť�ť‥Š¾ pairs()
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
    -- Š¢Š˛Š›Š¬Š�Š˛ Š²Š¾ Š²ť€ŠµŠ¼ť¸ Š°Šŗť‥ŠøŠ²Š½Š¾Š³Š¾ Š·Š°Šæť€Š¾ť�Š°
    if not St.waitingStats then return end
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
    -- 1. Š�Š½Š°ť‥Š°Š»Š° Š³ť€ť�Š·ŠøŠ¼ ŠŗŠ¾Š½ť„ŠøŠ³
    loadCfg()

    -- 2. Š�ŠøŠ½ť…ť€Š¾Š½ŠøŠ·Šøť€ť�ŠµŠ¼ Š²ť�Šµ Š±ť�ť„Šµť€ť‹
    St.winWbuf[0] = cfg.winWPct > 0 and cfg.winWPct or 0.60
    St.winHbuf[0] = cfg.winHPct > 0 and cfg.winHPct or 0.76
    if cfg.custR >= 0 then
        St.custRbuf[0] = cfg.custR
        St.custGbuf[0] = cfg.custG
        St.custBbuf[0] = cfg.custB
    else
        local a = getTheme().acc
        St.custRbuf[0] = a[1]; St.custGbuf[0] = a[2]; St.custBbuf[0] = a[3]
    end
    -- ť�ŠøŠ½ť…ť€Š¾Š½ŠøŠ·Š°ť†Šøť¸ ť†Š²Šµť‥Š° ť„Š¾Š½Š° ť�ť‥ť€Š¾Šŗ
    if cfg.rowBgR >= 0 then
        St.rowBgRbuf[0] = cfg.rowBgR
        St.rowBgGbuf[0] = cfg.rowBgG
        St.rowBgBbuf[0] = cfg.rowBgB
    else
        local a = getTheme().acc
        St.rowBgRbuf[0] = a[1]; St.rowBgGbuf[0] = a[2]; St.rowBgBbuf[0] = a[3]
    end
    chkBuf[0] = cfg.autoRefresh
    chkBuf2[0] = cfg.hideNativeStats
    aBuf[0]   = cfg.autoInterval
    St.fontSizeBuf[0] = cfg.fontSize > 0 and cfg.fontSize or 1.25

    -- 3. Š–Š´ť‥Š¼ SAMP ĥ€” Š±ŠµŠ· Š»Šøť�Š½Šøť… Š·Š°Š´Šµť€Š¶ŠµŠŗ
    repeat wait(100) until isSampAvailable()

    -- 4. Š ŠµŠ³Šøť�ť‥ť€Šøť€ť�ŠµŠ¼ ŠŗŠ¾Š¼Š°Š½Š´ť�
    sampRegisterChatCommand("sw", function()
        if not isSampAvailable() then return end
        St.winOpen = not St.winOpen
        if St.winOpen then
            _sw_win_init = nil
            requestStats()
        else
            St.activeTab = 1
        end
    end)

    -- 5. Š�Š¾Š¾Š±ť‰ŠµŠ½ŠøŠµ Š² ť‥Š°ť‥ ĥ€” Š¶Š´ť‥Š¼ Š Š•Š�Š›Š¬Š¯Š«Š™ ť�ŠæŠ°Š²Š½ ŠøŠ³ť€Š¾ŠŗŠ°
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
        -- avtomaticheski podstavlyaem kursy valyut po opredelyonnomu serveru
        -- (tolko esli oni eshchyo ne byli poluchenih ranee cherez telefon
        -- ili vruchnuyu, chtoby ne zatirat' uzhe aktualnie dannie)
        pcall(function()
            if cfg.rateVC <= 0 and cfg.rateBTC <= 0 then
                fetchArzWikiRates(true)
            end
        end)
        pcall(sampAddChatMessage,
            "{00FF88}[MSW v1.1.0] {FFFFFF}PC Stats | Cmd: {00FF88}/sw", -1)
        -- avtomaticheskaya proverka obnovleniy pri zapuske (bez neobhodimosti
        -- zahodit v Nastroyki i nazhimat' "Proverit' obnovleniya" vruchnuyu);
        -- esli na GitHub versiya novee - poyavitsya knopka "Obnovit'"
        pcall(checkForUpdates)
    end)

    -- 6. Š‥Š»Š°Š²Š½ť‹Š¹ ť†ŠøŠŗŠ» ĥ€” Š² Š¾ť‥Š´ŠµŠ»ť�Š½Š¾Š¼ ŠæŠ¾ť‥Š¾ŠŗŠµ, main() Š·Š°Š²Šµť€ť�Š°Šµť‥ť�ť¸
    lastAutoTime = now()
    while true do
        wait(100)

        if St.waitingStats then
            local dt = now() - lastTdTime
            local dr = now() - lastReqTime
            if next(tdCollector) ~= nil and captureStarted and dt >= TD_DELAY then
                local ok2, err2 = pcall(finalize)
                if not ok2 then
                    St.waitingStats    = false
                    tdCollector     = {}
                    tdCollectorSize = 0
                    St.statusMsg = u8"\xce\xf8\xe8\xe1\xea\xe0 \xef\xe0\xf0\xf1\xe8\xed\xe3\xe0"
                    pcall(sampAddChatMessage, "{FF6666}[MSW] finalize err: " .. tostring(err2), -1)
                end
            elseif dr >= REQ_TIMEOUT then
                St.waitingStats    = false
                tdCollector     = {}
                tdCollectorSize = 0
                if not St.statsData then
                    St.statusMsg = u8"\xcd\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc"
                end
            end
        end

        if cfg.autoRefresh and St.winOpen and St.statsData then
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
