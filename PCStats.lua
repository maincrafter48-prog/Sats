script_name("PC Stats")
script_description("Statistika personazha | Arizona PC | by Marco_Santiago (PC port)")
script_author("Marco_Santiago")
script_version("1.1.2")

local SCRIPT_VER = "1.1.2"

-- ── авто-обновление: репозиторий на GitHub, откуда скрипт проверяет и
-- скачивает новую версию. version.txt в корне репозитория должен содержать
-- только номер версии (например "1.3.0"), PCStats.lua — актуальный файл.
-- Чтобы завести обновления на своём репозитории, поменяй owner/repo/branch. --
local UPDATE_OWNER    = "maincrafter48-prog"
local UPDATE_REPO     = "Sats"
local UPDATE_BRANCH   = "main"
local UPDATE_RAW_BASE = "https://raw.githubusercontent.com/" .. UPDATE_OWNER .. "/" .. UPDATE_REPO .. "/refs/heads/" .. UPDATE_BRANCH .. "/"
local UPDATE_SCRIPT_URL  = UPDATE_RAW_BASE .. "PCStats.lua"
local UPDATE_VERSION_URL = UPDATE_RAW_BASE .. "version.txt"

-- имя чат-команды, зарегистрированной сейчас (для перерегистрации при смене)
local _registeredMenuCmd = nil

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
local ffi    = safeRequire("ffi")

-- opcionalnaya biblioteka dlya HTTP-zaprosov (nuzhna dlya proverki/skachivaniya
-- obnovleniy skripta s GitHub i dlya otpravki statistiki na leaderboard-backend);
-- esli ne ustanovlena - skript prosto pokazhet ob etom soobshchenie tam, gde ona nuzhna
local _httpLib = safeRequire("requests")

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
--  WINAPI ЧЕРЕЗ FFI (без os.execute!)
-- ------------------------------------------------------------
-- os.execute() на Windows для GUI-процесса (каким является
-- SA-MP/GTA:SA) под капотом дёргает C-функцию system(), а она
-- всегда порождает видимое окно cmd.exe (даже для простых команд
-- вроде mkdir), потому что у процесса нет своей консоли — Windows
-- создаёт новую. Это окно перехватывает фокус и может свернуть
-- игру в полноэкранном режиме, из-за чего игра выглядит "вылетевшей".
-- Поэтому папку конфига создаём через WinAPI CreateDirectoryA, а
-- ссылки открываем через ShellExecuteA — оба варианта работают
-- без создания какого-либо окна консоли ──
local _winApiOk = false
if ffi then
    _winApiOk = pcall(function()
        ffi.cdef[[
            int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);
            void *ShellExecuteA(void *hwnd, const char *lpOperation, const char *lpFile,
                                 const char *lpParameters, const char *lpDirectory, int nShowCmd);
        ]]
    end)
end
local _shell32 = nil
if _winApiOk then
    local okLib, lib = pcall(ffi.load, "shell32")
    if okLib then _shell32 = lib end
end

-- создаёт папку через WinAPI (без консоли); возвращает true при успехе
-- вызова (папка создана или уже существовала — CreateDirectoryA в обоих
-- случаях не бросает исключение, просто выставляет код ошибки, который
-- нам тут не важен)
local function winCreateDir(path)
    if not _winApiOk then return false end
    local ok = pcall(function() ffi.C.CreateDirectoryA(path, nil) end)
    return ok
end

-- открывает ссылку через WinAPI (без консоли)
local function winOpenUrl(url)
    if not _shell32 then return false end
    local ok = pcall(function() _shell32.ShellExecuteA(nil, "open", url, nil, nil, 1) end)
    return ok
end

-- ============================================================
--  Š�Š˛Š¯Š¤Š�Š“
-- ============================================================
local CFG_DIR      = "moonloader/config/PCStats"
local CFG_FILE     = CFG_DIR .. "/settings.ini"
-- старое расположение конфига (плоский файл без папки, версии до 1.1.2) —
-- нужно для миграции: если новый файл ещё не существует, но существует
-- старый, подхватываем настройки из него и сразу пересохраняем в новую
-- папку, чтобы обновление скрипта не сбросило игроку его настройки
local CFG_FILE_OLD = "moonloader/config/PCStats.ini"

-- создаёт папку конфига, если её ещё нет; если она уже есть — ничего не
-- делает и не пересоздаёт. Раньше это делалось через os.execute('mkdir'),
-- что на Windows каждый раз на мгновение открывало окно cmd.exe (см.
-- комментарий у WinAPI-обёрток выше) — из-за того, что saveCfg() (а
-- значит и ensureCfgDir()) вызывается очень часто, буквально при любом
-- изменении настроек, это окно постоянно мелькало и могло сворачивать
-- игру в полноэкранном режиме. Теперь используем CreateDirectoryA без
-- всякой консоли; на всякий случай (если ffi недоступен) оставлен
-- запасной вариант через os.execute ──
local function ensureCfgDir()
    if not winCreateDir(CFG_DIR:gsub("/", "\\")) then
        pcall(os.execute, 'mkdir "' .. CFG_DIR:gsub("/", "\\") .. '" 2>nul')
    end
end

-- ============================================================
--  ШРИФТ ИКОНОК ВКЛАДОК (FontAwesome 6 Free Solid, обрезанный)
-- ------------------------------------------------------------
-- ниже — обрезанный (только 5 нужных глифов: user/hand-fist/
-- sack-dollar/gear/circle-info, взяты с fontawesome.com/v6/search)
-- вариант fa-solid-900.ttf в base64, ~2.3 КБ вместо ~420 КБ полного
-- шрифта. mimgui умеет грузить шрифт только из файла или из ffi-
-- буфера в памяти, а не прямо из Lua-строки, поэтому декодируем
-- base64 в бинарные байты и один раз сохраняем как .ttf-файл рядом
-- с настройками (moonloader/config/PCStats/) — при следующих запусках
-- скрипт видит, что файл уже есть, и просто переиспользует его ──
local ICON_FONT_FILE = CFG_DIR .. "/pcstats-icons.ttf"
local ICON_FONT_B64 = table.concat({
    "AAEAAAAKAIAAAwAgT1MvMlFQWnEAAAa0AAAAYGNtYXDnEdkAAAAHFAAAAFRnbHlmT7TBOAAAAKwAAAVkaGVhZCupGN8AAAZAAAAA",
    "NmhoZWEETQIxAAAGkAAAACRobXR4CwAALAAABngAAAAYbG9jYQQ/AtcAAAYwAAAADm1heHAAHAeEAAAGEAAAACBuYW1lHYc4cwAA",
    "B2gAAAGYcG9zdP/eABkAAAkAAAAAIAACAAD/wAHAAcAAGgAwAAA3MjcxMTY3NjU0JyYnJiMiBwYHBhUUFxYXFjMHBgcxMQYHFBcW",
    "MyExMjc2NSYnJicj4CMdHRIRERIdHSMjHR0SERESHR0jLkszMgIJCA0BhA0ICQIyM0tcwBERHh4iIh4eERERER4eIiIeHhERMAIy",
    "M0sNCAkJCA1LMzICAAIADP/AAfQBwABgAG0AAAEWBwcxFhUUBxcxFgcGBwcxBgcGJycxBgcHMQYHBiMiJyYnJzEmJwcxBicmJycx",
    "JicmNzcxJjU0NycxJjc2NzcxNjc2FxcxNjc3MTY3NjMyFxYXFzEWFzcxNhcWFxcxFhcHNjc2JyYnBgcGFxYXAfAECiwCAiwKBAcJ",
    "BQoMCg44FBgMBA8UFhYVDgQMGBQ4DgoNCQUJBwQKLAICLAoEBwkFCQ0KDjgUGAwEDxQWFhUOBAwYFDgOCg0KBAkH8C0YFhYYLS0Y",
    "FhYYLQEZDgooDA0NDCgKDhIRCBAPCwQSEAk6DgMEBAMOOgkQEgQLDxAIEREPCicNDQ0MKAoOEhEIEA8LBBIQCjkOAwQEAw45ChAS",
    "BAsPEAgREqkBJygoJwEBJygoJwEAAwAA/8ACAAHAABoAOABLAAAFNjcxMTY3NjU0JyYnJicGBwYHBhUUFxYXFhcnMyMzNTEjMSYn",
    "NjczMRYXFTEzMRYXBgcjMSYnNjc3MhcxMRYVFAcGIyInJjU0NzYzAQBGOjokIiIkOjpGRjo6JCIiJDo6RigYGBgYFgICFjAWAggW",
    "AgIWUBYCAhYoDgkJCQkODgkJCQkOQAEhIjw9Q0M9PCIhAQEhIjw9Q0M9PCIhAbBAAhYWAgIWWAIWFgICFhYC0AkJDg4JCQkJDg4J",
    "CQAFACD/wAGgAcAAEAAgADYATACQAAATMhcxMRYVFTEjMTUxNDc2Mwc0NzExNjMyFxYVFTEjMTUzNDcxMTYzMhcWFRUxFAcGIyIn",
    "JjU1FzQ3MTE2MzIXFhUVMRQHBiMiJyY1NQc1FTUWMzI3FhcWMzI3FTEUBwYHFTEUBwYjIzEiJyY1NTEmJycxJic1MTY3NjczMTIX",
    "FhUUBwYjIzEGBxYXMzE2NzY3wA4JCUAJCQ6ACQkODgkJQMAJCQ4OCQkJCQ4OCQlgCQkODgkJCQkODgkJYA4SFBAGERAVEg4RER4J",
    "CQ6gDgkJGhULJQEBEhIbWBELDAwLETgPAQEPOB8UFAEBwAkJDnBwDgkJQA4JCQkJDlBQDgkJCQkOYA4JCQkJDmBADgkJCQkOQA4J",
    "CQkJDkBYAQEBCQsTDAwJCSghIRZgDgkJCQkOTgwVCyY1GxsSEgEMCxERCwwBDw8BARQUHwAAAwAA/8ACAAHAABAAPACQAAABIzMj",
    "JzEmNzY3MzEWFxYHBwczIzMWFzAxFhcWFxYXBgcGByExJicmJzY3Njc2NzAxMDEwMTAxMDE2NzY3FyYnBgcVMQYHBgcWFxYXFzEW",
    "FxYHFAcGIyYnJicmBwYXFhcwMTAxMDEwMRYXFTEWFzY3NTE2NzY3JicmJzAxMDExMSYnJjcmNzYzMhcWNzYnJic1AUCAgIAvBQQE",
    "CsQKBAQFL4CAgIAGBx4qKSAgAgEbGyn+wCkbGwECICApKh4CAwQEVAISEgIMChgCAxYSEQITCQcBBggNEBMEBBIHBBEDAwwQAhIS",
    "AgwLFwIDFhITEwoGAQEHCQ0OERIGAxEKCwFgRwkIBwEBBwgJRyAEBBIiIzc4UikbGwEBGxspUjg3IyISAQICA1gSAgISDgIHDB8e",
    "CwoEAQUFBQQHAwUBCAEBBBASCAEBBQMPEgICEg4CBw0gHgwKBQUFBQIFBAUFAxESBwICDgABAAAABgeDABUAAAAAAAEAAAAAAAAA",
    "AAAAAAAAAAAAAAAAAABGAOABRwH3ArIAAAABAAADBwUA2/3Av18PPPUACwIAAAAAAOOCabEAAAAA44Jpsf/0/7UCiwHLAAAACAAC",
    "AAAAAAAAAYAAAAHAAAACAAAMAgAAAAHAACACAAAAAAEAAAHL/7UAAAKA//T/9QKLAAEAAAAAAAAAAAAAAAAAAAAGAAQCAwOEAAUA",
    "AAFMAWYAAABHAUwBZgAAAPUAGQCEAAACAAkDAAAAAAAAAAAAABAAAAAAAAAAAAAAAEFXU00AgPAH+B0By/+1AAABywBLAAAAAQAA",
    "AAABQQGvAAAAIAAAAAAAAgAAAAMAAAAUAAMAAQAAABQABABAAAAADAAIAAIABPAH8BPwWvbe+B3//wAA8AfwE/Ba9t74Hf//D/oP",
    "7w+pCSYH6AABAAAAAAAAAAAAAAAAAAAABwBaAAMAAQQJAAAANAAAAAMAAQQJAAEAMgA0AAMAAQQJAAIACgBmAAMAAQQJAAMAPgBw",
    "AAMAAQQJAAQAMgA0AAMAAQQJAAUAZACuAAMAAQQJAAYALAESAEMAbwBwAHkAcgBpAGcAaAB0ACAAKABjACkAIABGAG8AbgB0ACAA",
    "QQB3AGUAcwBvAG0AZQBGAG8AbgB0ACAAQQB3AGUAcwBvAG0AZQAgADYAIABGAHIAZQBlACAAUwBvAGwAaQBkAFMAbwBsAGkAZABG",
    "AG8AbgB0ACAAQQB3AGUAcwBvAG0AZQAgADYAIABGAHIAZQBlACAAUwBvAGwAaQBkAC0ANgAuADcALgAyAFYAZQByAHMAaQBvAG4A",
    "IAA3ADcANQAuADAAMQA5ADUAMwAxADIANQAgACgARgBvAG4AdAAgAEEAdwBlAHMAbwBtAGUAIAB2AGUAcgBzAGkAbwBuADoAIAA2",
    "AC4ANwAuADIAKQBGAG8AbgB0AEEAdwBlAHMAbwBtAGUANgBGAHIAZQBlAC0AUwBvAGwAaQBkAAMAAAAAAAD/2wAZAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAA=",
})

-- UTF-8 байты нужных иконок (кодовые точки Private Use Area
-- FontAwesome: f007/f6de/f81d/f013/f05a) — считаются напрямую в UTF-8,
-- БЕЗ u8(), потому что u8() конвертирует из CP1251, а это не кириллица
local ICON_USER = "\239\128\135" -- fa-user        -- vkladka "Personazh"
local ICON_FIST = "\239\155\158" -- fa-hand-fist   -- vkladka "Boy"
local ICON_SACK = "\239\160\157" -- fa-sack-dollar -- vkladka "Finansy"
local ICON_GEAR = "\239\128\147" -- fa-gear        -- vkladka "Nastroyki"
local ICON_INFO = "\239\129\154" -- fa-circle-info -- vkladka "O skripte"

-- простой чистый Lua base64-декодер (без внешних зависимостей —
-- на скрипт с mimgui нельзя рассчитывать, что будет доступна bit32/bit)
local function b64decode(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local rev = {}
    for i = 1, #b64chars do rev[b64chars:sub(i,i)] = i - 1 end
    data = data:gsub('[^%w%+%/%=]', '')
    local out = {}
    local i = 1
    local n = #data
    while i <= n do
        local c1 = rev[data:sub(i,i)]
        local c2 = rev[data:sub(i+1,i+1)]
        local c3 = data:sub(i+2,i+2)
        local c4 = data:sub(i+3,i+3)
        local v3 = rev[c3]
        local v4 = rev[c4]
        if not c1 or not c2 then break end
        local n1 = c1 * 4 + math.floor(c2 / 16)
        out[#out+1] = string.char(n1)
        if c3 ~= '' and c3 ~= '=' and v3 then
            local n2 = (c2 % 16) * 16 + math.floor(v3 / 4)
            out[#out+1] = string.char(n2)
            if c4 ~= '' and c4 ~= '=' and v4 then
                local n3 = (v3 % 4) * 64 + v4
                out[#out+1] = string.char(n3)
            end
        end
        i = i + 4
    end
    return table.concat(out)
end

-- распаковывает шрифт иконок на диск, если его там ещё нет (или файл
-- повреждён/пустой) — вызывается один раз из imgui.OnInitialize ниже
local function ensureIconFontFile()
    local f = io.open(ICON_FONT_FILE, "rb")
    if f then
        local sz = f:seek("end")
        f:close()
        if sz and sz > 0 then return true end
    end
    ensureCfgDir()
    local raw = b64decode(ICON_FONT_B64)
    if not raw or #raw == 0 then return false end
    local out, ferr = io.open(ICON_FONT_FILE, "wb")
    if not out then return false end
    out:write(raw)
    out:close()
    return true
end

-- подключаем шрифт иконок в режиме MergeMode поверх обычного шрифта —
-- после этого ICON_USER/ICON_FIST/ICON_SACK/ICON_GEAR/ICON_INFO можно
-- вставлять прямо в любой imgui-текст как обычные символы
imgui.OnInitialize(function()
    local okIco = pcall(ensureIconFontFile)
    if not okIco then return end
    pcall(function()
        local defaultFontCfg = imgui.GetIO().Fonts.ConfigData.Data[0]
        local baseSize = (defaultFontCfg and defaultFontCfg.SizePixels) or 13.0
        local config = imgui.ImFontConfig()
        config.MergeMode   = true
        config.PixelSnapH  = true
        local iconRanges = imgui.new.ImWchar[3](0xf000, 0xf8ff, 0)
        imgui.GetIO().Fonts:AddFontFromFileTTF(ICON_FONT_FILE, baseSize, config, iconRanges)
    end)
end)

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
    rateVC  = 0.0,
    -- отдельно курс "продажа" VC$ с экрана "Криптовалюта" (заполняется
    -- автоматически из parsePhoneRatesText вместе с обычным rateVC,
    -- редактируется вручную так же, как остальные курсы) ──
    rateVCSell = 0.0,
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
    -- ── лидерборд игроков на сайте: включён по умолчанию (тумблер в
    -- настройках убран по просьбе — теперь это просто всегда работает,
    -- ник/сервер/часть статистики (уровень/работа/баланс) уходят на backend ──
    shareStats = true,
    -- уникальный id инсталляции, генерируется один раз при первом запуске,
    -- нужен backend'у чтобы понимать "это тот же игрок обновил данные"
    -- и чтобы можно было удалить свои данные при отключении опции
    ownerKey = "",
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
    -- komanda otkrytiya glavnogo menyu skripta (bez slesha, po umolchaniyu "sw")
    menuOpenCmd = "sw",
    -- nomer poslednej otkrytoy vkladki (1..5), chtoby posle perezahoda/
    -- obnovleniya skripta menyu otkryvalos na toy zhe vkladke, na kotoroy
    -- igrok byl v proshlyy raz
    lastTab = 1,
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

local saveCfgLater = false -- true, если loadCfg сгенерировал новый ownerKey и его надо сохранить
local _restoredMenuCmd = false -- true, если menuOpenCmd подхватился из сохранённых настроек (не дефолт) — используется для уведомления в чат при спавне

local function applyCfgData(m)
    cfg.theme        = tonumber(m.theme) or 1
    cfg.autoRefresh  = m.autoRefresh == "true"
    cfg.autoInterval = tonumber(m.autoInterval) or 30
    cfg.winWPct      = tonumber(m.winWPct) or 0.0
    cfg.winHPct      = tonumber(m.winHPct) or 0.0
    cfg.custR        = tonumber(m.custR) or -1
    cfg.custG        = tonumber(m.custG) or -1
    cfg.custB        = tonumber(m.custB) or -1
    cfg.rowBgR        = tonumber(m.rowBgR) or -1
    cfg.rowBgG        = tonumber(m.rowBgG) or -1
    cfg.rowBgB        = tonumber(m.rowBgB) or -1
    cfg.fontSize      = tonumber(m.fontSize) or 1.25
    cfg.rateAZ        = tonumber(m.rateAZ) or 35000.0
    cfg.rateBTC       = tonumber(m.rateBTC) or 0.0
    cfg.rateEUR       = tonumber(m.rateEUR) or 0.0
    cfg.rateVC        = tonumber(m.rateVC) or 0.0
    cfg.rateVCSell    = tonumber(m.rateVCSell) or 0.0
    cfg.ascAmount     = tonumber(m.ascAmount) or 0.0
    cfg.rateASC       = tonumber(m.rateASC) or 0.0
    cfg.vcServerName  = (m.vcServerName and m.vcServerName ~= "") and m.vcServerName or "Tucson"
    cfg.vcAutoDetectServer = (m.vcAutoDetectServer ~= "false")
    -- тумблер убран из интерфейса — родное окно /stats теперь скрывается всегда
    cfg.hideNativeStats = true
    cfg.financeTwoCol   = m.financeTwoCol == "true"
    if m.incCash == nil then cfg.incCash = true else cfg.incCash = m.incCash == "true" end
    if m.incBank == nil then cfg.incBank = true else cfg.incBank = m.incBank == "true" end
    if m.incDep  == nil then cfg.incDep  = true else cfg.incDep  = m.incDep  == "true" end
    if m.incAcc  == nil then cfg.incAcc  = true else cfg.incAcc  = m.incAcc  == "true" end
    if m.incAZ   == nil then cfg.incAZ   = true else cfg.incAZ   = m.incAZ   == "true" end
    if m.incBTC  == nil then cfg.incBTC  = true else cfg.incBTC  = m.incBTC  == "true" end
    if m.incEUR  == nil then cfg.incEUR  = true else cfg.incEUR  = m.incEUR  == "true" end
    if m.incVC   == nil then cfg.incVC   = true else cfg.incVC   = m.incVC   == "true" end
    if m.incASC  == nil then cfg.incASC  = true else cfg.incASC  = m.incASC  == "true" end
    cfg.globalNumColorOn = m.globalNumColorOn == "true"
    cfg.globalNumR = tonumber(m.globalNumR) or -1
    cfg.globalNumG = tonumber(m.globalNumG) or -1
    cfg.globalNumB = tonumber(m.globalNumB) or -1
    cfg.customColorsStr = m.customColorsStr or ""
    deserializeCustomColors(cfg.customColorsStr)
    cfg.phoneOpenCmd  = (m.phoneOpenCmd and m.phoneOpenCmd ~= "") and m.phoneOpenCmd or "/phone"
    cfg.menuOpenCmd   = (m.menuOpenCmd and m.menuOpenCmd ~= "") and m.menuOpenCmd or "sw"
    if cfg.menuOpenCmd ~= "sw" then _restoredMenuCmd = true end
    if m.shareStats == nil then cfg.shareStats = true else cfg.shareStats = m.shareStats == "true" end
    cfg.ownerKey   = m.ownerKey or ""
    local lt = tonumber(m.lastTab)
    cfg.lastTab = (lt and lt >= 1 and lt <= 5) and math.floor(lt) or 1
end

local function loadCfg()
    -- 1) пробуем новое расположение (папка moonloader/config/PCStats/)
    local ok, data = pcall(function() return inicfg.load(nil, CFG_FILE) end)
    if ok and data and data.main then
        applyCfgData(data.main)
    else
        -- 2) новой папки/файла ещё нет — пробуем старое плоское
        -- расположение (версии скрипта до 1.1.2). Если там что-то есть —
        -- подхватываем эти настройки и сразу пересохраняем в новую папку,
        -- чтобы при следующем запуске уже читать из неё
        local okOld, dataOld = pcall(function() return inicfg.load(nil, CFG_FILE_OLD) end)
        if okOld and dataOld and dataOld.main then
            applyCfgData(dataOld.main)
            saveCfgLater = true
        end
    end
    if not cfg.ownerKey or cfg.ownerKey == "" then
        -- генерируем один раз и сразу сохраняем, чтобы id был стабилен между запусками
        math.randomseed((os.time() or 0) + (os.clock() or 0) * 1000)
        local parts = {}
        for i = 1, 32 do parts[i] = string.format("%x", math.random(0, 15)) end
        cfg.ownerKey = table.concat(parts)
        saveCfgLater = true
    end
end

local function saveCfg()
    cfg.customColorsStr = serializeCustomColors()
    ensureCfgDir() -- на случай, если папки ещё нет (первый запуск / миграция со старой версии) — если уже есть, ничего не делает
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
            rateVCSell    = tostring(cfg.rateVCSell),
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
            lastTab       = tostring(cfg.lastTab or 1),
            phoneOpenCmd  = tostring(cfg.phoneOpenCmd or "/phone"),
            menuOpenCmd   = tostring(cfg.menuOpenCmd or "sw"),
            shareStats = tostring(cfg.shareStats),
            ownerKey   = tostring(cfg.ownerKey or ""),
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
 St.accPopupOpen   = false
 St._resetCharScroll = false
 St._resetSettScroll = false

-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Ń€Ń�Ń‡Š½Š¾Š³Š¾ Š²Š²Š¾Š´Š° RGB Š² Š½Š°Ń�Ń‚Ń€Š¾Š¹ŠŗŠ°Ń…
 St.custRbuf = imgui.new.float(1.0)
 St.custGbuf = imgui.new.float(0.5)
 St.custBbuf = imgui.new.float(0.2)

-- Š±Ń�Ń„ŠµŃ€Ń‹ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ (R,G,B)
local _custPickerVec  = nil
local _rowBgPickerVec = nil
 St.rowBgRbuf = imgui.new.float(0.43)
 St.rowBgGbuf = imgui.new.float(0.71)
 St.rowBgBbuf = imgui.new.float(1.0)

-- буфер для поля ввода команды открытия меню (вкладка "Настройки")
St.menuCmdBuf = imgui.new("char[16]", "sw")

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
    s = s:gsub("%[%x%x%x%x%x%x%]", "") -- цветовые коды в квадратных скобках (формат диалогов телефона)
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
    local rnd = 10
    -- FIX: раньше заливка была с острыми углами (0), а рамка поверх — со
    -- скруглёнными (8) => углы "рвались". Теперь заливка тоже скруглена
    -- с нужной стороны (верх/низ), флаги — через pcall на случай, если
    -- в этой сборке mimgui нет ImDrawFlags (тогда просто без углового флага)
    local flagsTop, flagsBot
    pcall(function() flagsTop = imgui.ImDrawFlags.RoundCornersTop end)
    pcall(function() flagsBot = imgui.ImDrawFlags.RoundCornersBottom end)
    if flagsTop then
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+halfH),
            imgui.ColorConvertFloat4ToU32(iv4(aR*0.55,aG*0.55,aB*0.55,bgAlpha)), rnd, flagsTop)
    else
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+halfH),
            imgui.ColorConvertFloat4ToU32(iv4(aR*0.55,aG*0.55,aB*0.55,bgAlpha)), 0)
    end
    if flagsBot then
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y+halfH),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+bH_c),
            imgui.ColorConvertFloat4ToU32(iv4(bR*0.55,bG*0.55,bB*0.55,bgAlpha)), rnd, flagsBot)
    else
        dl_cb:AddRectFilled(
            imgui.ImVec2(p_cb.x,           p_cb.y+halfH),
            imgui.ImVec2(p_cb.x+btnW,      p_cb.y+bH_c),
            imgui.ColorConvertFloat4ToU32(iv4(bR*0.55,bG*0.55,bB*0.55,bgAlpha)), 0)
    end
    local borderCol = isAct and iv4(aR,aG,aB,1.0) or iv4(aR*0.65,aG*0.65,aB*0.65,0.70)
    dl_cb:AddRect(
        imgui.ImVec2(p_cb.x,       p_cb.y),
        imgui.ImVec2(p_cb.x+btnW,  p_cb.y+bH_c),
        imgui.ColorConvertFloat4ToU32(borderCol), rnd, 0, isAct and 2.0 or 1.0)
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
    imgui.BeginChild("##mt"..tostring(St._metricTileIdx), imgui.ImVec2(w, h), false,
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
            if imgui.Button(">>##cp"..tostring(St._metricTileIdx),
                            imgui.ImVec2(btnW, btnH)) then
                pcall(onClickFn)
            end
            if _sv>0 then pcall(imgui.PopStyleVar,_sv) end end
            imgui.PopStyleColor(3)
        end

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

    -- Š›Š•Š’Š�ŠÆ Š�Š˛Š›Š˛Š¯Š�Š� ā€” Š‘Š�Š›Š�Š¯Š� + Š�Š§Š•Š¢Š� (Š¾Š±Ń‹Ń‡Š½Ń‹Š¹ Ń�ŠŗŃ€Š¾Š»Š»: ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø)
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

    -- ── нижний отступ, чтобы последняя строка не прилипала к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
end

-- ============================================================
--  Š‘Š£Š¤Š•Š Š« Š�Š›Š�Š™Š”Š•Š Š˛Š’ Š Š�Š—Š�Š•Š Š� Š˛Š�Š¯Š�
-- ============================================================
 St.winWbuf = imgui.new.float(0.60)
 St.winHbuf = imgui.new.float(0.76)
local WIN_W_MIN = 0.38
local WIN_H_MIN = 0.42
 St.fontSizeBuf = imgui.new.float(1.25)
local FONT_SIZE_MIN = 0.7
local FONT_SIZE_MAX = 2.0
-- Š±Ń�Ń„ŠµŃ€Ń‹ Š´Š»Ń¸ Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ Š°Š²Ń‚Š¾-Š¾Š±Š½Š¾Š²Š»ŠµŠ½ŠøŃ¸ (Š´Š¾Š»Š¶Š½Ń‹ Š±Ń‹Ń‚Ń� Š³Š»Š¾Š±Š°Š»Ń�Š½Ń‹Š¼Šø, Š½Šµ Š²Š½Ń�Ń‚Ń€Šø Ń€ŠµŠ½Š´ŠµŃ€Š°!)
local chkBuf = imgui.new.bool(false)
local chkBuf2 = imgui.new.bool(true)
local aBuf   = imgui.new.float(30.0)
-- Buffery kursov obmena valyut (celye chisla, chtoby ne bylo lishnih nulikov posle zapyatoy)
 St.rateAZBuf  = imgui.new.int(0)
 St.rateBTCBuf = imgui.new.int(0)
 St.rateEURBuf = imgui.new.int(0)
 St.rateVCBuf  = imgui.new.int(0)
 St.rateVCSellBuf = imgui.new.int(0)
 St.rateASCBuf = imgui.new.int(0)

-- otslezhivaem kakoe pole seychas redaktiruetsya, chtoby ne perezapisyvat bufer
-- kazhdyy kadr poka igrok pechataet (imenno eto vyzyvalo "migание"/skachushchie nuliki)
local _rateActive = {}

-- ── состояние окна "Настройки" вкладки "Финансы": по умолчанию оно
-- прикреплено к главному окну справа и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно ──
 St._financeSettingsOpen     = false
 St._financeSettingsDetached = false
local _financeSettingsPos      = nil   -- {x=,y=} запоминается, только пока панель откреплена
 St._mainWinPos  = nil
 St._mainWinSize = nil

-- ── анимация сдвига главного окна влево при открытой (пристыкованной) панели
-- настроек "Финансы"; когда панель открывается — окно скрипта плавно уезжает
-- влево, чтобы освободить место панели, а при закрытии панели возвращается
-- обратно на своё место ──
 St._finShiftAnim       = 0.0   -- 0..1, текущая фаза анимации
 St._finShiftAppliedPx  = 0.0   -- сколько пикселей сдвига уже применено в прошлый кадр
 St._finShiftLastTime   = nil
 St._finShiftAnchorX    = nil   -- "домашняя" X-позиция окна без сдвига (запоминается только пока сдвиг == 0)

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
-- Раньше скрипт пытался угадать номер вкладки телефона и кликать по
-- списку диалогов (sampSendDialogResponse) — ненадёжно, т.к. состав
-- вкладок/пунктов может отличаться. Теперь вместо угадывания скрипт
-- открывает приложение "Криптовалюта" НАПРЯМУЮ по его ID через
-- RakNet-пакет — тот же способ, что использует отдельный скрипт
-- CryptoRatesReader (payload "launchedApp|39"). Это сразу открывает
-- нужный экран без блуждания по меню.

local CRYPTO_APP_ID = 39 -- ID приложения "Криптовалюта" в телефоне Arizona RP

local _cefFetching   = false
 St._cefLastResult = ""  -- текстовый статус последней попытки (для UI)

-- ── "Покупка $X VS $Y" / "Продажа $X VS $Y" с экрана "Криптовалюта" —
-- те же два числа, что читает CryptoRatesReader; хранятся только для
-- отображения в меню, на итоговый расчёт "Всего" не влияют ──
St._phoneBuy       = nil
St._phoneBuyFor    = nil
St._phoneSell      = nil
St._phoneSellFor   = nil
St._phoneRatesTime = nil

-- true/"waiting", пока скрипт ждёт открытия диалога с курсами валют
local _phoneFetchState = false

-- отправляет сырые байты через RakNet-битстрим (аналог sendBytes из
-- CryptoRatesReader)
local function sendPhoneBytes(bytes)
    local bitStream = raknetNewBitStream()
    for _, byte in ipairs(bytes) do raknetBitStreamWriteInt8(bitStream, byte) end
    raknetSendBitStream(bitStream)
    raknetDeleteBitStream(bitStream)
end

-- открывает телефон и сразу переключает его на приложение "Криптовалюта"
-- по фиксированному ID (CRYPTO_APP_ID) — без блуждания по вкладкам меню
local function openCryptoAppDirect()
    local payload = "launchedApp|" .. tostring(CRYPTO_APP_ID)
    local appPacket = {220, 18, #payload, 0}
    for i = 1, #payload do table.insert(appPacket, payload:byte(i)) end
    for _ = 1, 4 do table.insert(appPacket, 0) end
    sendPhoneBytes({220, 0, 80, 64}) -- открыть телефон
    wait(150)
    sendPhoneBytes(appPacket) -- открыть приложение "Криптовалюта"
end

-- вытаскивает число прямо перед/после ключевого слова currency в строке
-- вида "AZ-Coins   104.791 AZ - $3.667.685.000" или "Евро  44 EUR - $0" —
-- ищем именно курс (цену в SA$ за единицу), а не количество на руках,
-- поэтому берём число сразу после "$" в конце строки, если оно есть,
-- иначе — первое число в строке.
-- игра форматирует числа ТОЧКАМИ как разделителями тысяч, а не десятичными
-- точками: "44.211" это 44211, "3.667.685.000" это 3667685000, дробной
-- части там никогда не бывает. Поэтому просто выкидываем всё, что не
-- цифра (пробелы, точки, запятые), и получаем целое число — раньше точки
-- не вырезались и tonumber("44.211") превращался в 44.211, отсюда неверный курс.
local function parseGameNumber(str)
    if not str then return nil end
    local digits = tostring(str):gsub("[^%d]", "")
    if digits == "" then return nil end
    return tonumber(digits)
end

-- Lua-шный string.lower() умеет опускать регистр только у ASCII a-z —
-- заглавные кириллические буквы в CP1251 (диапазон 0xC0-0xDF, плюс
-- Ё=0xA8) он не трогает вообще. Из-за этого сравнение needle
-- (написан строчными буквами) с текстом диалога, который игра всегда
-- присылает ЗАГЛАВНЫМИ (см. скриншот: "ТЕКУЩИЙ КУРС ДЛЯ ПОКУПКИ"),
-- никогда не совпадало — именно поэтому курс VC$ не читался, даже
-- когда искомая строка была найдена правильно. Эта функция опускает
-- регистр и у кириллических байт CP1251 тоже.
local function cp1251Lower(s)
    s = s:gsub("[\xc0-\xdf]", function(c) return string.char(c:byte() + 0x20) end)
    s = s:gsub("\xa8", "\xb8") -- Ё -> ё (не входит в диапазон выше)
    return s
end

local function extractPhoneRate(text, needles)
    if not text or text == "" then return nil end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line)
        local low = cp1251Lower(clean)
        for _, n in ipairs(needles) do
            if low:find(n, 1, true) then
                local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
                local numStr = afterDollar or clean:match("([%d%s%.,]+)")
                if numStr then
                    local v = parseGameNumber(numStr)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    return nil
end

-- вариант extractPhoneRate, который требует, чтобы needle стоял именно в
-- НАЧАЛЕ строки (после обрезки пробелов/цветовых кодов), а не просто
-- где-то встречался — нужно для VC$: значение курса стоит на отдельной
-- строке вида "Курс продажи: 1234" в меню "Криптовалюта", а не рядом со
-- словом "VC$"/"vice city", поэтому обычный extractPhoneRate по этим
-- словам её не находил, и курс VC$ всегда оставался 0
local function extractPhoneRateLineStart(text, needles)
    if not text or text == "" then return nil end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local clean = stripColor(line):gsub("^%s+", "")
        local low = cp1251Lower(clean)
        for _, n in ipairs(needles) do
            if low:find("^" .. n) then
                local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
                local numStr = afterDollar or clean:match("([%d%s%.,]+)")
                if numStr then
                    local v = parseGameNumber(numStr)
                    if v and v > 0 then return v end
                end
            end
        end
    end
    return nil
end

-- крайний запасной вариант для VC$: если поиск по подписи строки не
-- сработал (сервер прислал другую формулировку/сломанную кодировку),
-- берём число прямо по НОМЕРУ строки — на экране "Криптовалюта" курс
-- покупки VC$ стабильно оказывается на 6-й строке диалога
local function extractPhoneRateLineNumber(text, lineNum)
    if not text or text == "" then return nil end
    local i = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        i = i + 1
        if i == lineNum then
            local clean = stripColor(line):gsub("^%s+", ""):gsub("%s+$", "")
            local afterDollar = clean:match("%$%s*([%d%s%.,]+)%s*$")
            local numStr = afterDollar or clean:match("([%d%s%.,]+)")
            if numStr then
                local v = parseGameNumber(numStr)
                if v and v > 0 then return v end
            end
            return nil
        end
    end
    return nil
end

-- точный шаблон числа: пропускаем всё, что не цифра, до первой цифры,
-- затем забираем цифры/точки/запятые — так же, как NUM в CryptoRatesReader
local NUM_PATTERN = '[^%d]-(%d[%d,.]*)'

-- ищет rate по точному шаблону вида "Bitcoin (BTC): 12345" и возвращает
-- число (или nil, если не нашлось/не число)
local function phoneNumFromPattern(text, pattern)
    local v = text:match(pattern)
    if not v then return nil end
    local n = parseGameNumber(v)
    if n and n > 0 then return n end
    return nil
end

-- разбирает текст диалога "курс валют" в телефоне и раскладывает найденные
-- значения по cfg.rateXXX/буферам полей ввода. Возвращает true, если хотя
-- бы один курс удалось распознать.
--
-- Экран "Криптовалюта" показывает курсы Bitcoin (BTC), ЕВРО (euro) и
-- Arizona Coin (ASC) в формате "Название (СОКР): число" — это ровно тот
-- же формат, что успешно разбирает CryptoRatesReader, поэтому сначала
-- пробуем точные шаблоны под него, а на случай другого оформления —
-- запасной вариант через общий построчный поиск по ключевым словам.
local function parsePhoneRatesText(text)
    if not text or text == "" then return false end
    local body = stripColor(text)
    local gotAny = false

    local rBTC = phoneNumFromPattern(body, 'Bitcoin%s*%(%s*BTC%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"btc", "bitcoin", "\xe1\xe8\xf2\xea\xee\xe9\xed"})
    local rEUR = phoneNumFromPattern(body, '\xc5\xc2\xd0\xce%s*%(%s*euro%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"eur", "\xe5\xe2\xf0\xee"})
    local rASC = phoneNumFromPattern(body, 'Arizona%s+Coin%s*%(%s*ASC%s*%)%s*:' .. NUM_PATTERN)
        or extractPhoneRate(body, {"asc", "\xe0\xf0\xe8\xe7\xee\xed\xe0 \xf1\xf2\xe5\xe9\xe1\xeb"})
    -- AZ-Coin и VC$ на этом экране обычно не показываются (см.
    -- CryptoRatesReader — там их тоже нет), но на всякий случай пробуем
    -- запасной поиск и для них, вдруг формат сервера отличается
    local rAZ  = extractPhoneRate(body, {"az-coin", "az \xea\xee\xe8\xed", "\xe0\xe7-\xea\xee\xe8\xed"})
    -- курс VC$ в меню "Криптовалюта" стоит не рядом со словом "VC$", а на
    -- отдельной строке с меткой "Текущий курс для покупки" — поэтому
    -- сначала ищем именно эту строку по началу строки (ищем по стему
    -- "покуп", чтобы ловить и "покупки", и "покупке"), и только если её
    -- нет — пробуем старый способ как запасной вариант
    local rVC  = extractPhoneRateLineStart(body, {"\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xee\xea\xf3\xef"})
        or extractPhoneRate(body, {"vc$", "vice city", "\xe2\xe0\xe9\xf1 \xf1\xe8\xf2\xe8"})
        or extractPhoneRateLineNumber(body, 6)

    if rAZ  and rAZ  > 0 then cfg.rateAZ  = rAZ;  St.rateAZBuf[0]  = math.floor(rAZ  + 0.5); gotAny = true end
    if rBTC and rBTC > 0 then cfg.rateBTC = rBTC; St.rateBTCBuf[0] = math.floor(rBTC + 0.5); gotAny = true end
    if rEUR and rEUR > 0 then cfg.rateEUR = rEUR; St.rateEURBuf[0] = math.floor(rEUR + 0.5); gotAny = true end
    if rVC  and rVC  > 0 then cfg.rateVC  = rVC;  St.rateVCBuf[0]  = math.floor(rVC  + 0.5); gotAny = true end
    if rASC and rASC > 0 then cfg.rateASC = rASC; St.rateASCBuf[0] = math.floor(rASC + 0.5); gotAny = true end

    -- ── строка "Текущий курс для покупки/продажи" с телефонного экрана
    -- "Криптовалюта": на ней всегда идут ДВА числа подряд (курс и цена
    -- "за сколько") — ровно тот же формат, что разбирает CryptoRatesReader
    -- (buy/buyFor и sell/sellFor), поэтому берём оба точно так же и потом
    -- показываем в меню строкой "Покупка: $X VS $Y" / "Продажа: $X VS $Y".
    --
    -- ВАЖНО: в диалоге строка идёт с заглавной буквы ("Текущий курс..."),
    -- а наш шаблон-стем написан в нижнем регистре — поэтому сравниваем не
    -- с сырым body, а с его версией в нижнем регистре (cp1251Lower, как и
    -- в extractPhoneRateLineStart чуть выше). Позиции символов совпадают,
    -- так что захваченные NUM_PATTERN'ом цифры от регистра не зависят ──
    local bodyLow = cp1251Lower(body)
    local buy, buyFor = bodyLow:match(
        "\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xee\xea\xf3\xef.-:" .. NUM_PATTERN .. NUM_PATTERN)
    local sell, sellFor = bodyLow:match(
        "\xf2\xe5\xea\xf3\xf9\xe8\xe9 \xea\xf3\xf0\xf1 \xe4\xeb\xff \xef\xf0\xee\xe4\xe0\xe6.-:" .. NUM_PATTERN .. NUM_PATTERN)
    if buy or sell then
        St._phoneBuy      = buy      or St._phoneBuy
        St._phoneBuyFor   = buyFor   or St._phoneBuyFor
        St._phoneSell     = sell     or St._phoneSell
        St._phoneSellFor  = sellFor  or St._phoneSellFor
        St._phoneRatesTime = os.date("%H:%M:%S")
        gotAny = true
        -- курс продажи тоже сохраняем как обычный курс (rateVCSell), а не
        -- только как текст для показа — раньше он терялся и не попадал в
        -- поле ручного ввода курсов ──
        local sellN = tonumber(sell)
        if sellN and sellN > 0 then cfg.rateVCSell = sellN; St.rateVCSellBuf[0] = math.floor(sellN + 0.5) end
        -- курс ПОКУПКИ (buy) пишем в основную существующую строку rateVC —
        -- именно её использует расчёт общего баланса (vcSA = vc * cfg.rateVC
        -- в drawFinance), поэтому важно, чтобы сюда попадало распознанное
        -- значение, а не оставался 0. Пишем его здесь (а не только через
        -- более раннюю/хрупкую эвристику rVC выше), потому что buy разбирается
        -- из того же надёжного шаблона "два числа подряд", что и sell,
        -- который уже гарантированно работает ──
        local buyN = tonumber(buy)
        if buyN and buyN > 0 then cfg.rateVC = buyN; St.rateVCBuf[0] = math.floor(buyN + 0.5) end
    end

    if gotAny then saveCfg() end
    return gotAny
end

-- проверяет, похож ли открывшийся диалог именно на экран "Курс валют"
-- приложения "Криптовалюта" (по заголовку либо по телу — так же, как
-- делает parseRates() в CryptoRatesReader), чтобы случайно не схватить
-- какой-то другой экран телефона
local function isCryptoRatesDialog(title, text)
    local marker = "\xca\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2" -- "Курс валют"
    local h = stripColor(tostring(title or ""))
    local b = stripColor(tostring(text or ""))
    return h:find(marker, 1, true) ~= nil or b:find(marker, 1, true) ~= nil
end

-- Запускает автообновление: открывает телефон и сразу переключает его на
-- приложение "Криптовалюта" по ID (см. openCryptoAppDirect), затем ждёт
-- диалог с курсами и читает его — см. sampev.onShowDialog.
local function fetchRatesViaCEF()
    if _cefFetching then return end
    if not isSampAvailable() then
        St._cefLastResult = "\xf1\xe0\xec\xef \xed\xe5 \xe4\xee\xf1\xf2\xf3\xef\xe5\xed"
        return
    end
    _cefFetching     = true
    _phoneFetchState = "waiting"
    St._cefLastResult   = "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed..."
    pcall(sampAddChatMessage, "{FFD700}[Stats] " .. "\xee\xf2\xea\xf0\xfb\xe2\xe0\xe5\xec \xf2\xe5\xeb\xe5\xf4\xee\xed \xe8 \xe8\xf9\xe5\xec \xea\xf3\xf0\xf1 \xe2\xe0\xeb\xfe\xf2...", -1)
    lua_thread.create(function()
        local okOpen = pcall(openCryptoAppDirect)
        if not okOpen then
            _phoneFetchState = false
            _cefFetching     = false
            St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xea\xf0\xfb\xf2\xfc \xef\xf0\xe8\xeb\xee\xe6\xe5\xed\xe8\xe5 \xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
            return
        end
        local waited = 0
        while _phoneFetchState and waited < 8000 do
            wait(100); waited = waited + 100
        end
        if _phoneFetchState then
            -- за 8 секунд диалог с курсами так и не пришёл
            _phoneFetchState = false
            St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xee\xf2\xea\xf0\xfb\xf2\xfc \xec\xe5\xed\xfe \xca\xf0\xe8\xef\xf2\xee\xe2\xe0\xeb\xfe\xf2\xe0 \xe2 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe5"
            pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
        end
        -- на всякий случай закрываем всплывшие диалоги телефона, чтобы не
        -- оставить его открытым поверх интерфейса игрока
        for _=1,2 do pcall(sampCloseCurrentDialog, -1); wait(150) end
        _cefFetching = false
    end)
end

-- ============================================================
--  Šš Š£Š ŠŠ« Š’ŠŠ›Š®Š¢ ŠŸŠ Š•Š”Š¤Ā  ARZ-WIKI (statichesky snapshot)
-- ------------------------------------------------------------
-- Tablitsa kursov obmena valyut po serveram Arizona RP, sobrannaya
-- s stranitsy arz-wiki.com/arz-rp/articles/currency-exchange/.
-- Znachenie kazhdogo polya - tsena PRODAZHI 1 edinitsy valyuty v SA$
-- (t.e. skolko SA$ igrok poluchit za 1 VC$/BTC/AZ/EUR/ASC).
-- Eto snimok na moment 24.07.2026 - kursy na servere menyayutsya,
-- tak chto tablitsu stoit periodicheski obnovlyat' vruchnuyu so
-- stranitsy vyshe. Ispolzuetsya kak bystryy istochnik kursov, kogda
-- igrok ne hochet otkryvat' telefon (fetchRatesViaCEF).
-- ============================================================
local ARZ_WIKI_RATES = {
    ["Brainburg"]    = { vc=124, btc=64644, az=35000, eur=4622, asc=46000 },
    ["Bumble Bee"]   = { vc=112, btc=63939, az=35000, eur=4445, asc=46000 },
    ["Casa Grande"]  = { vc=112, btc=64660, az=35000, eur=4945, asc=46000 },
    ["Chandler"]     = { vc=129, btc=63120, az=35000, eur=2909, asc=46000 },
    ["Christmas"]    = { vc=112, btc=64652, az=35000, eur=4901, asc=46000 },
    ["Drake"]        = { vc=112, btc=63936, az=35000, eur=4888, asc=46000 },
    ["Faraway"]      = { vc=112, btc=64749, az=35000, eur=4890, asc=46000 },
    ["Gilbert"]      = { vc=112, btc=63910, az=35000, eur=9592, asc=46000 },
    ["Glendale"]     = { vc=112, btc=64436, az=35000, eur=5753, asc=46000 },
    ["Holiday"]      = { vc=112, btc=63120, az=35000, eur=5431, asc=46000 },
    ["Kingman"]      = { vc=112, btc=64791, az=35000, eur=6946, asc=46000 },
    ["Love"]         = { vc=112, btc=64660, az=35000, eur=5122, asc=46000 },
    ["Mesa"]         = { vc=160, btc=64744, az=35000, eur=3538, asc=46000 },
    ["Mirage"]       = { vc=112, btc=64193, az=35000, eur=4959, asc=46000 },
    ["Mobile 1"]     = {         btc=72986, az=35000, eur=5048, asc=46000 },
    ["Mobile 2"]     = {         btc=89441, az=35000, eur=5739, asc=45000 },
    ["Mobile 3"]     = {         btc=66533, az=35000, eur=6439, asc=46000 },
    ["Page"]         = { vc=112, btc=64515, az=35000, eur=4696, asc=46000 },
    ["Payson"]       = { vc=112, btc=64660, az=35000, eur=4820, asc=46000 },
    ["Phoenix"]      = { vc=131, btc=64660, az=35000, eur=1673, asc=46000 },
    ["Prescott"]     = { vc=112, btc=63939, az=35000, eur=5438, asc=46000 },
    ["Queen Creek"]  = { vc=112, btc=64665, az=35000, eur=5393, asc=46000 },
    ["Red Rock"]     = { vc=114, btc=64515, az=35000, eur=3903, asc=46000 },
    ["Saint Rose"]   = { vc=123, btc=63365, az=35000, eur=4844, asc=46000 },
    ["Scottdale"]    = { vc=148, btc=64665, az=35000, eur=2438, asc=46000 },
    ["Sedona"]       = { vc=112, btc=64660, az=35000, eur=4857, asc=46000 },
    ["Show Low"]     = { vc=112, btc=64086, az=35000, eur=6842, asc=46000 },
    ["Space"]        = { vc=112, btc=62933,           eur=4862, asc=46000 },
    ["Sun City"]     = { vc=112, btc=63120, az=35000, eur=5626, asc=46000 },
    ["Surprise"]     = { vc=112, btc=64471, az=35000, eur=4976, asc=46000 },
    ["Tucson"]       = { vc=183, btc=64736, az=35000, eur=2827, asc=46000 },
    ["Vice City"]    = {         btc=97368, az=35000, eur=5048, asc=43000 },
    ["Wednesday"]    = { vc=112, btc=63936, az=35000, eur=3134, asc=46000 },
    ["Winslow"]      = { vc=112, btc=64665, az=35000, eur=6063, asc=46000 },
    ["Yava"]         = { vc=112, btc=63935, az=35000, eur=4485, asc=46000 },
    ["Yuma"]         = { vc=132, btc=64644, az=35000, eur=7238, asc=46000 },
}

-- ============================================================
--  ДОБРОВОЛЬНЫЙ ЛИДЕРБОРД (opt-in) — отправка своей статистики
--  на backend, только если cfg.shareStats == true.
-- ============================================================
local API_BASE = "https://pcstats-backend-production.up.railway.app"
local REPORT_SECRET = "a8f3k29dmz7qp1x0vwrtl56bcyhesn4j"

-- минимальный JSON-энкодер под конкретный набор полей отчёта (без внешних зависимостей)
local function jsonStr(s)
    s = tostring(s or "")
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '')
    return '"' .. s .. '"'
end

local function buildReportJson(t)
    local parts = {}
    for _, k in ipairs({
        "ownerKey","nick","server","level","job","org","position","status",
        "cashSas","cashVcs","bank","euro","btc","azCoins","wanted"
    }) do
        table.insert(parts, jsonStr(k) .. ":" .. jsonStr(t[k]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- синхронный HTTP POST/DELETE через ту же опциональную библиотеку 'requests',
-- что используется для подгрузки курсов валют. Разные сборки requests.lua
-- по-разному называют метод отправки тела — пробуем несколько вариантов.
local function httpSendJson(method, url, jsonBody, headers)
    if not _httpLib then return false, "no_requests_lib" end
    local fn = method == "DELETE" and _httpLib.delete or _httpLib.post
    if type(fn) ~= "function" then return false, "no_" .. tostring(method):lower() .. "_method" end
    local ok, resp = pcall(fn, url, { data = jsonBody, headers = headers, timeout = 8 })
    if not ok or not resp then
        -- пробуем альтернативную сигнатуру (url, body, headers)
        ok, resp = pcall(fn, url, jsonBody, headers)
    end
    if not ok or not resp then return false, "request_failed" end
    local status = resp.status_code or (type(resp.status) == "table" and resp.status.code) or resp.status
    if status and tonumber(status) and tonumber(status) >= 300 then
        return false, "http_" .. tostring(status)
    end
    return true, nil
end

local _reportInFlight = false

-- отправляет текущую статистику игрока на backend (если shareStats включён)
function sendStatsReport()
    if not cfg.shareStats then return end
    if API_BASE == "" then return end -- backend ещё не подключён
    if not St.statsData then return end
    if _reportInFlight then return end
    local nick = St.statsData.name
    if not nick or nick == "" then return end

    -- сервер: если включено автоопределение — берём реальный текущий
    -- сервер игрока, а не то, что когда-то было вписано вручную
    local server = (cfg.vcAutoDetectServer and detectArzServerName()) or cfg.vcServerName or "Tucson"
    local payload = buildReportJson({
        ownerKey = cfg.ownerKey, nick = nick, server = server,
        level = St.statsData.level, job = St.statsData.job, org = St.statsData.org,
        position = St.statsData.position, status = St.statsData.status,
        cashSas = St.statsData.cashSas, cashVcs = St.statsData.cashVcs,
        bank = St.statsData.bank, euro = St.statsData.euro, btc = St.statsData.btc,
        azCoins = St.statsData.azCoins, wanted = St.statsData.wanted,
    })
    _reportInFlight = true
    lua_thread.create(function()
        local ok, err = httpSendJson("POST", API_BASE .. "/api/report", payload,
            { ["Content-Type"] = "application/json", ["X-Report-Key"] = REPORT_SECRET })
        _reportInFlight = false
        -- тихо: отправка лидерборда — фоновая и необязательная,
        -- ошибку в чат больше не пишем (err доступен для отладки при желании)
    end)
end

-- удаляет ранее отправленные данные игрока с backend (при выключении опции)
function deleteStatsReport()
    if API_BASE == "" then return end
    if not cfg.ownerKey or cfg.ownerKey == "" then return end
    local payload = '{' .. jsonStr("ownerKey") .. ':' .. jsonStr(cfg.ownerKey) .. '}'
    lua_thread.create(function()
        pcall(httpSendJson, "DELETE", API_BASE .. "/api/report", payload,
            { ["Content-Type"] = "application/json", ["X-Report-Key"] = REPORT_SECRET })
    end)
end

-- ============================================================
--  АВТО-ОБНОВЛЕНИЕ (проверка версии на GitHub + скачивание + рестарт)
-- ============================================================

local _updChecking    = false
local _updDownloading = false
local _updAvailable   = false
local _updRemoteVer   = nil
local _updStatus      = nil  -- статус для UI, сырые CP1251-байты

-- обычный синхронный HTTP GET: сперва пробуем нативную функцию MoonLoader
-- downloadUrlToFile (она встроена в сам MoonLoader и есть ВСЕГДА, в отличие
-- от сторонней библиотеки 'requests', которая у многих просто не установлена
-- — из-за этого раньше вся система обновлений молча ничего не делала).
-- Библиотеку 'requests' оставляем как запасной вариант.
local _mlEnum   = safeRequire('moonloader')
local _dlStatus = _mlEnum and _mlEnum.download_status or nil

-- скачивает URL во временный файл через downloadUrlToFile и дожидается
-- результата (можно звать только изнутри lua_thread.create, т.к. использует wait)
local function nativeDownloadToFile(url, path, timeoutMs)
    if not downloadUrlToFile or not _dlStatus then return false, "no_native_download" end
    timeoutMs = timeoutMs or 15000
    local finished, ok = false, false
    local myId = nil
    local startOk = pcall(function()
        myId = downloadUrlToFile(url, path, function(id, status)
            if myId ~= nil and id ~= myId then return end
            if status == _dlStatus.STATUS_ENDDOWNLOADDATA then
                finished = true; ok = true
            elseif status == _dlStatus.STATUS_ERROR then
                finished = true; ok = false
            end
        end)
    end)
    if not startOk or myId == nil then return false, "download_start_failed" end
    local waited = 0
    while not finished and waited < timeoutMs do wait(100); waited = waited + 100 end
    if not finished then return false, "timeout" end
    return ok, (ok and nil or "download_error")
end

local function httpGetUrl(url)
    if downloadUrlToFile and _dlStatus then
        ensureCfgDir()
        local tmpPath = CFG_DIR:gsub("/", "\\") .. "\\_update_tmp_" .. tostring(math.random(100000,999999)) .. ".tmp"
        local ok = nativeDownloadToFile(url, tmpPath, 15000)
        if ok then
            local f = io.open(tmpPath, "rb")
            if f then
                local body = f:read("*a")
                f:close()
                pcall(os.remove, tmpPath)
                if type(body) == "string" and #body > 0 then
                    return body, nil
                end
            end
        end
        pcall(os.remove, tmpPath)
        -- нативный способ не сработал (нет сети/файл не создался и т.п.) —
        -- падаем ниже на библиотеку 'requests', если она вдруг установлена
    end
    if not _httpLib or type(_httpLib.get) ~= "function" then
        return nil, "no_download_method"
    end
    local ok, resp = pcall(_httpLib.get, url)
    if not ok or not resp then return nil, "request_failed" end
    local status = resp.status_code or (type(resp.status) == "table" and resp.status.code) or 200
    if status and status ~= 200 then return nil, "http_" .. tostring(status) end
    local body = resp.text or resp.content or resp.body
    if type(body) ~= "string" or #body == 0 then return nil, "empty_body" end
    return body, nil
end

-- сравнение версий вида "1.2.7" по числовым компонентам
local function isNewerVersion(remote, current)
    local function parts(s)
        local t = {}
        for n in tostring(s):gmatch("%d+") do t[#t+1] = tonumber(n) end
        return t
    end
    local rp, cp = parts(remote), parts(current)
    local n = math.max(#rp, #cp)
    for i = 1, n do
        local rv, cv = rp[i] or 0, cp[i] or 0
        if rv ~= cv then return rv > cv end
    end
    return false
end

-- пытается перезапустить скрипт после обновления файла на диске
local function selfReloadScript()
    local ok = pcall(function() thisScript():reload() end)
    if ok then return true end
    ok = pcall(function()
        local s = thisScript()
        if s.unload then s:unload() end
        if s.load then s:load() end
    end)
    if ok then return true end
    ok = pcall(function()
        if unloadScript and loadScript then
            local p = thisScript().path
            unloadScript(thisScript())
            loadScript(p)
        end
    end)
    return ok
end

-- проверка версии на GitHub (version.txt в корне репозитория)
function checkForUpdate(silent)
    if _updChecking or _updDownloading then return end
    _updChecking  = true
    _updAvailable = false
    _updStatus    = "\xcf\xf0\xee\xe2\xe5\xf0\xea\xe0\x2e\x2e\x2e" -- "Проверка..."
    lua_thread.create(function()
        local okCall, body, err = pcall(httpGetUrl, UPDATE_VERSION_URL)
        if not okCall then body, err = nil, "internal_error" end
        _updChecking = false
        if not body then
            local messages = {
                no_download_method = "\xed\xe5\xf2\x20\xf1\xef\xee\xf1\xee\xe1\xe0\x20\xf1\xea\xe0\xf7\xe0\xf2\xfc\x20\xf4\xe0\xe9\xeb",
                download_start_failed = "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xed\xe0\xf7\xe0\xf2\xfc\x20\xf1\xea\xe0\xf7\xe8\xe2\xe0\xed\xe8\xe5",
                timeout         = "\xef\xf0\xe5\xe2\xfb\xf8\xe5\xed\x20\xf2\xe0\xe9\xec\xe0\xf3\xf2",
                download_error  = "\xee\xf8\xe8\xe1\xea\xe0\x20\xf1\xea\xe0\xf7\xe8\xe2\xe0\xed\xe8\xff",
                request_failed  = "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xef\xee\xe4\xea\xeb\xfe\xf7\xe8\xf2\xfc\xf1\xff\x20\xea\x20GitHub",
                empty_body      = "\xef\xf3\xf1\xf2\xee\xe9\x20\xee\xf2\xe2\xe5\xf2",
            }
            _updStatus = "\xce\xf8\xe8\xe1\xea\xe0\x20\xef\xf0\xee\xe2\xe5\xf0\xea\xe8: " .. (messages[err] or tostring(err))
            if not silent then
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] " .. _updStatus, -1)
            end
            return
        end
        local remoteVer = body:match("%d+%.%d+%.?%d*")
        if not remoteVer then
            _updStatus = "\xce\xf8\xe8\xe1\xea\xe0\x20\xef\xf0\xee\xe2\xe5\xf0\xea\xe8: \xed\xe5\xe2\xe5\xf0\xed\xfb\xe9\x20\xee\xf2\xe2\xe5\xf2"
            return
        end
        _updRemoteVer = remoteVer
        if isNewerVersion(remoteVer, SCRIPT_VER) then
            _updAvailable = true
            _updStatus = "\xc4\xee\xf1\xf2\xf3\xef\xed\xe0\x20\xed\xee\xe2\xe0\xff\x20\xe2\xe5\xf0\xf1\xe8\xff: v" .. remoteVer
            pcall(sampAddChatMessage, "{00FF88}[PC Stats] " .. _updStatus, -1)
        else
            _updAvailable = false
            _updStatus = "\xd3\xf1\xf2\xe0\xed\xee\xe2\xeb\xe5\xed\xe0\x20\xef\xee\xf1\xeb\xe5\xe4\xed\xff\xff\x20\xe2\xe5\xf0\xf1\xe8\xff"
        end
    end)
end

-- скачивает актуальный PCStats.lua и перезаписывает им собственный файл,
-- затем перезапускает скрипт
function downloadAndApplyUpdate()
    if _updDownloading or _updChecking then return end
    _updDownloading = true
    _updStatus = "\xc7\xe0\xe3\xf0\xf3\xe7\xea\xe0\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff\x2e\x2e\x2e"
    lua_thread.create(function()
        local okCall, body, err = pcall(httpGetUrl, UPDATE_SCRIPT_URL)
        if not okCall then body, err = nil, "internal_error" end
        if not body or #body < 500 then
            _updStatus = "\xce\xf8\xe8\xe1\xea\xe0\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff: " .. tostring(err or "empty")
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " .. _updStatus, -1)
            _updDownloading = false
            return
        end
        local ownPath = nil
        pcall(function() ownPath = thisScript().path end)
        if not ownPath then
            _updStatus = "\xce\xf8\xe8\xe1\xea\xe0: \xed\xe5\x20\xed\xe0\xe9\xe4\xe5\xed\x20\xef\xf3\xf2\xfc\x20\xea\x20\xf1\xea\xf0\xe8\xef\xf2\xf3"
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " .. _updStatus, -1)
            _updDownloading = false
            return
        end
        local f, ferr = io.open(ownPath, "wb")
        if not f then
            _updStatus = "\xce\xf8\xe8\xe1\xea\xe0\x20\xe7\xe0\xef\xe8\xf1\xe8: " .. tostring(ferr)
            pcall(sampAddChatMessage, "{FF6666}[PC Stats] " .. _updStatus, -1)
            _updDownloading = false
            return
        end
        f:write(body)
        f:close()
        _updStatus = "\xd1\xea\xf0\xe8\xef\xf2\x20\xee\xe1\xed\xee\xe2\xeb\xb8\xed\x2c\x20\xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xea\x2e\x2e\x2e"
        pcall(sampAddChatMessage, "{00FF88}[PC Stats] " .. _updStatus, -1)
        -- ── явное сохранение настроек ПЕРЕД перезапуском скрипта —
        -- защита на случай, если onScriptTerminate() почему-то не
        -- успеет/не сможет сработать до подмены файла; без этого игрок
        -- при автообновлении рисковал потерять цвет/размер окна/тумблеры,
        -- выставленные в текущей сессии (см. просьбу в чате) ──
        pcall(saveCfg)
        _updDownloading = false
        wait(300)
        selfReloadScript()
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

-- ── определяет текущий сервер Arizona RP, к которому подключён игрок,
-- через нативную SAMP-функцию sampGetCurrentServerName(); используется
-- в панели настроек "Финансы" при включённом автоопределении сервера
-- (cfg.vcAutoDetectServer). Обёрнуто в pcall, чтобы отсутствие функции
-- (например, до подключения к серверу) не приводило к краху скрипта ──
function detectArzServerName()
    if type(sampGetCurrentServerName) ~= "function" then
        return nil
    end
    local ok, name = pcall(sampGetCurrentServerName)
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    -- раньше здесь вырезался "хвост" строки регуляркой ("([%a%-]+)%s*$"),
    -- из-за чего в название сервера попадал мусор вроде "X3" или обрывки
    -- слова "Role Play" — сайт потом не мог сматчить это с настоящим
    -- названием города, и игрок не находился в списке своего сервера.
    -- Вместо этого ищем среди ИЗВЕСТНЫХ названий серверов (см.
    -- ARZ_WIKI_RATES) точное вхождение — так на выходе всегда чистое
    -- "Page"/"Tucson"/etc, независимо от того, что ещё есть в строке.
    local lower = name:lower()
    local best, bestLen = nil, 0
    for serverName in pairs(ARZ_WIKI_RATES) do
        local needle = serverName:lower()
        if lower:find(needle, 1, true) and #needle > bestLen then
            best, bestLen = serverName, #needle
        end
    end
    return best
end

function fetchArzWikiRates(silent)
    local name = cfg.vcAutoDetectServer and detectArzServerName() or cfg.vcServerName
    return applyWikiRatesForServer(name, silent)
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

-- ── единый "современный" стиль для всплывающих окон выбора цвета/курса —
-- скруглённые углы + мягкая акцентная рамка вместо стандартных острых
-- углов imgui. Вызывать ПЕРЕД imgui.BeginPopup(...), парную функцию —
-- после imgui.EndPopup() ──
local function pushModernPopupStyle()
    local r,g,b = getAcc()
    local n = 0
    if pcall(imgui.PushStyleVar, imgui.StyleVar.PopupRounding, 14.0) then n = n + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.PopupBorderSize, 1.4) then n = n + 1 end
    if pcall(imgui.PushStyleVar, imgui.StyleVar.WindowPadding, imgui.ImVec2(16, 14)) then n = n + 1 end
    imgui.PushStyleColor(imgui.Col.PopupBg, iv4(0.08,0.085,0.11,0.99))
    imgui.PushStyleColor(imgui.Col.Border,  iv4(r*0.75,g*0.75,b*0.75,0.85))
    return n
end
local function popModernPopupStyle(n)
    imgui.PopStyleColor(2)
    if n and n > 0 then pcall(imgui.PopStyleVar, n) end
end

-- ── всплывающее окно "Настройки" вкладки "Финансы": вынесено в отдельную
-- функцию, чтобы не раздувать список апвэлью drawTotal (лимит Lua — 60) ──
local function drawFinanceSettingsBlock(r, g, b)
    local avW  = imgui.GetContentRegionAvail().x

    -- ── единая кнопка "Настройки" — открывает/закрывает панель настроек
    -- вкладки "Финансы". Панель больше не всплывающий popup, а отдельное
    -- окно, прикреплённое справа от главного окна (см. drawFinanceSettingsPanel).
    -- Цвет кнопки сделан отдельным (нейтрально-серо-голубым), а не акцентным,
    -- чтобы она визуально отличалась от остальных кнопок вкладки ──
    -- цвет кнопки "Настройки" завязан на акцентный цвет темы (r,g,b),
    -- а не на фиксированный серый — чтобы кнопка не выглядела "мёртвой"
    local _fsOn = {r*0.85 + 0.10, g*0.55 + 0.10, b*1.00}
    local _fsAc = {math.min(1,r*1.15), math.min(1,g*1.15), math.min(1,b*1.15)} -- цвет кнопки, когда панель открыта (подсветка)
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

    -- ── ручной выбор сервера убран по требованию: сервер теперь всегда
    -- определяется автоматически (по текущему SAMP-серверу), без тумблера ──
    cfg.vcAutoDetectServer = true
    do
        local detectedNow = detectArzServerName()
        if detectedNow then
            imgui.TextColored(iv4(0.5,0.52,0.58,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0: ")
            imgui.SameLine(0,4)
            imgui.TextColored(iv4(0.40,0.90,0.55,1.0), detectedNow)
        else
            imgui.TextColored(iv4(0.95,0.55,0.30,1.0), u8"\xd1\xe5\xf0\xe2\xe5\xf0 \xed\xe5 \xee\xef\xf0\xe5\xe4\xe5\xeb\xb8\xed 3 \xe7\xe0\xe9\xe4\xe8\xf2\xe5 \xed\xe0 \xf1\xe5\xf0\xe2\xe5\xf0")
        end
    end
    imgui.Spacing()

    -- ── кнопка "Обновить с телефона": сама открывает игровой телефон и
    -- сразу переключает его на приложение "Криптовалюта" по ID через
    -- RakNet (без блуждания по вкладкам меню — см. openCryptoAppDirect()),
    -- затем читает актуальные курсы прямо из диалога — см. fetchRatesViaCEF()
    -- и sampev.onShowDialog. Найденные значения (и покупка, и продажа)
    -- сразу подставляются в поля ручного ввода курсов (rateInputRow) ниже ──
    do
        local busy2 = _cefFetching
        local phBg = busy2 and {0.85,0.68,0.15} or {0.20,0.65,0.85}
        local phLbl = busy2
            and u8"  \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5..."
            or  u8"  \xce\xe1\xed\xee\xe2\xe8\xf2\xfc \xf1 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
        imgui.PushStyleColor(imgui.Col.Button,        iv4(phBg[1]*0.55,phBg[2]*0.55,phBg[3]*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(phBg[1]*0.75,phBg[2]*0.75,phBg[3]*0.75,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(phBg[1],phBg[2],phBg[3],1.0))
        do local _pb3 = prettyBtnPush(9.0)
        if imgui.Button(phLbl.."##financeRefPhone", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(32))) then
            fetchRatesViaCEF()
        end
        prettyBtnPop(_pb3) end
        imgui.PopStyleColor(3)
    end
    imgui.Spacing()

    -- ── ручной ввод курсов валют: кнопка открывает всплывающее окно
    -- с полями AZ-Coins/BTC/Евро/VC$/ASC (перенесено сюда с вкладки
    -- "Финансы", раньше был раскрывающийся блок прямо там). Под кнопкой —
    -- статус последнего обновления с телефона и строки "Покупка"/
    -- "Продажа" (те же два числа, что читает CryptoRatesReader со строк
    -- "Текущий курс для покупки/продажи" на экране "Криптовалюта" — см.
    -- parsePhoneRatesText), показываются всегда, без отдельной кнопки-
    -- переключателя ──
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

        if St._cefLastResult ~= "" or St._phoneBuy or St._phoneSell then
            imgui.Spacing()
            if St._cefLastResult ~= "" then
                imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. u8(St._cefLastResult))
            end
            if St._phoneBuy then
                imgui.TextColored(iv4(0.55,0.95,0.55,1.0),
                    "  " .. u8"\xcf\xee\xea\xf3\xef\xea\xe0" .. ": $" .. tostring(St._phoneBuy)
                    .. " VS $" .. tostring(St._phoneBuyFor or "-"))
            end
            if St._phoneSell then
                imgui.TextColored(iv4(0.95,0.75,0.35,1.0),
                    "  " .. u8"\xcf\xf0\xee\xe4\xe0\xe6\xe0" .. ": $" .. tostring(St._phoneSell)
                    .. " VS $" .. tostring(St._phoneSellFor or "-"))
            end
            if St._phoneRatesTime then
                imgui.TextColored(iv4(0.5,0.52,0.58,1.0), "  " .. u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xee" .. ": " .. St._phoneRatesTime)
            end
        end

        pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(280), 0), imgui.Cond and imgui.Cond.Appearing or 0)
        local _mps1 = pushModernPopupStyle()
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
        popModernPopupStyle(_mps1)
    end
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

    -- ── АВТО-ОБНОВЛЕНИЕ: поставлен сразу под тумблером "Раскладка", чтобы
    -- оба одиночных тумблера панели шли вместе, одним блоком ──
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc0\xe2\xf2\xee-\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5")
    imgui.Spacing()
    if drawToggleSwitch("##autoRefreshSw", cfg.autoRefresh) then
        cfg.autoRefresh = not cfg.autoRefresh
        chkBuf[0] = cfg.autoRefresh
        saveCfg()
    end
    imgui.SameLine(0, S(8))
    imgui.TextColored(iv4(1,1,1,1), u8"\xc2\xea\xeb\xfe\xf7\xe8\xf2\xfc")
    imgui.Spacing()
    if cfg.autoRefresh then
        imgui.Dummy(imgui.ImVec2(0, S(6)))
        imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xc8\xed\xf2\xe5\xf0\xe2\xe0\xeb:")
        imgui.SameLine(0,8)
        imgui.TextColored(iv4(1,1,1,1), cfg.autoInterval..u8" \xf1\xe5\xea")
        do
            imgui.PushStyleColor(imgui.Col.FrameBg,          iv4(r*0.14,g*0.14,b*0.14,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgHovered,   iv4(r*0.24,g*0.24,b*0.24,1.0))
            imgui.PushStyleColor(imgui.Col.FrameBgActive,    iv4(r*0.35,g*0.35,b*0.35,1.0))
            imgui.PushStyleColor(imgui.Col.SliderGrab,       iv4(r,g,b,1.0))
            imgui.PushStyleColor(imgui.Col.SliderGrabActive, iv4(math.min(1,r*1.2),math.min(1,g*1.2),math.min(1,b*1.2)))
            do local _svc3=0
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,12.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,12.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,32.0) then _svc3=_svc3+1 end
            if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc3=_svc3+1 end
            if imgui.SliderFloat("##ai2", aBuf, 10.0, 300.0) then
                cfg.autoInterval = math.floor(aBuf[0]+0.5); saveCfg()
            end
            if _svc3>0 then pcall(imgui.PopStyleVar,_svc3) end; end
            imgui.PopStyleColor(5)
        end
    end

    imgui.Spacing()
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- переключатель "Закрытие по Esc" убран вместе с самим закрытием
    -- меню по Esc (по просьбе) — теперь Esc скриптом не перехватывается
    imgui.Dummy(imgui.ImVec2(0, S(4)))

    -- ── команда открытия меню: перенесено сюда с главной вкладки
    -- "Финансы" (раньше карточка "Меню" висела прямо там и занимала
    -- место среди сумм — теперь она аккуратно живёт в настройках).
    -- Рамку-карточку убрал по просьбе — поле теперь простое, без
    -- обводки, как остальные элементы панели, и сдвинуто чуть ниже ──
    imgui.Dummy(imgui.ImVec2(0, S(10)))
    imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xca\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe")
    imgui.Spacing()
    do
        local aw_m = imgui.GetContentRegionAvail().x
        local applyW = S(88)

        imgui.TextColored(thDim(), u8"\xca\xee\xec\xe0\xed\xe4\xe0\x20\xf7\xe0\xf2\xe0:")
        imgui.Spacing()

        imgui.PushItemWidth(math.max(S(60), aw_m - applyW - S(8)))
        imgui.PushStyleColor(imgui.Col.FrameBg,        iv4(r*0.14,g*0.14,b*0.14,1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, iv4(r*0.20,g*0.20,b*0.20,1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgActive,  iv4(r*0.28,g*0.28,b*0.28,1.0))
        imgui.InputText("##menuCmdInputFin", St.menuCmdBuf, 16)
        imgui.PopStyleColor(3)
        imgui.PopItemWidth()

        imgui.SameLine(0, S(8))
        imgui.PushStyleColor(imgui.Col.Button,        iv4(r*0.22,g*0.22,b*0.22,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(r*0.40,g*0.40,b*0.40,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(r*0.58,g*0.58,b*0.58,1.0))
        do local _pbmc2 = prettyBtnPush(8.0)
        if imgui.Button(u8"\xcf\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc##applyMenuCmdFin", imgui.ImVec2(applyW, S(24))) then
            local newCmd = ""
            pcall(function() newCmd = ffi.string(St.menuCmdBuf) end)
            local ok2, appliedCmd = registerMenuCommand(newCmd)
            if ok2 then
                cfg.menuOpenCmd = appliedCmd
                saveCfg()
                pcall(sampAddChatMessage, "{00FF88}[PC Stats] " .. "\xea\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe: /" .. appliedCmd, -1)
            else
                pcall(sampAddChatMessage, "{FF6666}[PC Stats] " .. "\xed\xe5\x20\xf3\xe4\xe0\xeb\xee\xf1\xfc\x20\xef\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc\x20\xea\xee\xec\xe0\xed\xe4\xf3", -1)
            end
        end
        prettyBtnPop(_pbmc2) end
        imgui.PopStyleColor(3)

        imgui.Spacing()
        imgui.TextColored(iv4(0.50,0.54,0.62,1.0), u8"\xd2\xe5\xea\xf3\xf9\xe0\xff: /" .. tostring(cfg.menuOpenCmd or "sw"))
    end
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

-- ── отдельное окно панели настроек вкладки "Финансы". По умолчанию
-- пристыковано справа от главного окна и двигается вместе с ним; кнопка
-- "Открепить" позволяет носить его отдельно в любом месте экрана ──
local function drawFinanceSettingsPanel()
    if not St._financeSettingsOpen then return end
    if not St._mainWinPos or not St._mainWinSize then return end

    local panelW = S(320)

    if not St._financeSettingsDetached then
        imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Always)
    else
        imgui.SetNextWindowSize(imgui.ImVec2(panelW, St._mainWinSize.y), imgui.Cond.Once)
        if _financeSettingsPos then
            imgui.SetNextWindowPos(imgui.ImVec2(_financeSettingsPos.x, _financeSettingsPos.y), imgui.Cond.Once)
        else
            imgui.SetNextWindowPos(imgui.ImVec2(St._mainWinPos.x + St._mainWinSize.x + S(10), St._mainWinPos.y), imgui.Cond.Once)
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

    -- закрытие панели по Esc теперь целиком обрабатывается в onKeyDown()
    -- (см. ниже) — раньше здесь был свой независимый перехват через
    -- imgui.IsKeyPressed, который конфликтовал с onKeyDown: оба слушателя
    -- реагировали на одно и то же нажатие Esc, но по разным путям, и в
    -- результате первое нажатие закрывало только эту панель, а onKeyDown
    -- не успевал (или не мог) погасить событие для игры, поэтому второе
    -- нажатие Esc долетало до Arizona и открывало её меню паузы поверх
    -- уже закрытого нашего окна. Теперь Esc обрабатывается один раз в
    -- одном месте — это устраняет и двойное нажатие, и утечку в паузу.

    -- ── шапка панели: заголовок + кнопка "Открепить/Закрепить" ──
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
    if St._resetCharScroll then imgui.SetScrollY(0) end
        local r,g,b = getAcc()

        -- ── кнопка управления вкладкой "Всего": подписана текстом, читаемый
        -- шрифт, толщина рамки 4px ──────────────────────────────────────
        -- (кнопка "Цели" перенесена на вкладку "Настройки", см. drawSettings)
        drawFinanceSettingsBlock(r, g, b)

        -- ── карточка "Меню" (команда чата для открытия окна) перенесена в
        -- панель "Настройки финансов" (кнопка "Настройки" выше) — см.
        -- drawFinanceSettingsPanelContent, раздел "Команда открытия меню" ──

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

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetCharScroll = false
end


-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 3: Š¯Š�Š�Š¢Š Š˛Š™Š�Š�
-- ============================================================
local function drawSettings(h, sw, sh)
    -- ā”€ā”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ Š¯Š�Š�Š¢Š Š˛Š•Š� (Š¾Š±Ń‹Ń‡Š½Ń‹Š¹ Ń�ŠŗŃ€Š¾Š»Š»: ŠŗŠ¾Š»ŠµŃ�Š¾ Š¼Ń‹Ń�Šø / ŠæŠ¾Š»Š¾Ń�Š° ŠæŃ€Š¾ŠŗŃ€Ń�Ń‚ŠŗŠø) ā”€ā”€
    imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
    imgui.BeginChild("##sset", imgui.ImVec2(0, h), false)
    if St._resetSettScroll then imgui.SetScrollY(0) end
            local r,g,b = getAcc()

        -- ── единая кнопка выбора цвета: вынесена наверх вкладки, открывает
        -- одно окно сразу с готовыми цветами, своим цветом и цветом фона
        -- строк (раньше было разбросано тремя блоками ниже по вкладке) ──
        do
            local prT,pgT,pbT = getAcc()
            -- ярче, чем было (было ×0.20/0.36/0.52)
            imgui.PushStyleColor(imgui.Col.Button,        iv4(math.min(1,prT*0.55),math.min(1,pgT*0.55),math.min(1,pbT*0.55),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prT*0.78),math.min(1,pgT*0.78),math.min(1,pbT*0.78),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prT,pgT,pbT,1.0))
            do local _pbTop = prettyBtnPush(10.0)
            if imgui.Button(u8"\xc2\xfb\xe1\xee\xf0\x20\xf6\xe2\xe5\xf2\xe0##openColorSettingsPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(34))) then
                if cfg.custR < 0 then
                    local _a = getTheme().acc
                    St.custRbuf[0]=_a[1]; St.custGbuf[0]=_a[2]; St.custBbuf[0]=_a[3]
                end
                if cfg.rowBgR < 0 then
                    local _a2 = getTheme().acc
                    St.rowBgRbuf[0]=_a2[1]; St.rowBgGbuf[0]=_a2[2]; St.rowBgBbuf[0]=_a2[3]
                end
                imgui.OpenPopup("##colorSettingsPopup")
            end
            prettyBtnPop(_pbTop) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(300), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            local _mpsTop = pushModernPopupStyle()
            if imgui.BeginPopup("##colorSettingsPopup") then
                -- Edinyy spisok vseh presetov (temy + kombo), edinyy dizayn
                -- knopok, dubley po tsvetu aktsenta sredi presetov net.
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
                    {u8"\xd0\xe5\xf1\xf3\xf0\xf1",     0.20,0.90,0.45, 0.05,0.30,0.14},  -- Resurs
                    {u8"\xc7\xee\xeb\xee\xf2\xee",     0.98,0.80,0.15, 0.40,0.30,0.03},  -- Zoloto
                    {u8"\xca\xee\xf0\xe0\xeb\xeb",     0.15,0.85,0.75, 0.04,0.32,0.30},  -- Korall
                    -- ── добавленные по просьбе дополнительные цвета ──
                    {u8"\xc0\xec\xe5\xf2\xe8\xf1\xf2", 0.65,0.35,0.90, 0.24,0.10,0.36},  -- Ametist
                    {u8"\xcc\xff\xf2\xe0",             0.25,0.95,0.75, 0.06,0.36,0.28},  -- Myata
                    {u8"\xcb\xe0\xe9\xec",             0.70,0.95,0.15, 0.24,0.34,0.03},  -- Laym
                    {u8"\xc8\xed\xe4\xe8\xe3\xee",     0.30,0.35,0.95, 0.08,0.10,0.42},  -- Indigo
                    {u8"\xd4\xeb\xe0\xec\xe8\xed\xe3\xee", 1.0,0.45,0.55, 0.42,0.10,0.16}, -- Flamingo
                    {u8"\xd1\xf2\xe0\xeb\xfc",         0.55,0.65,0.75, 0.16,0.20,0.26},  -- Stal
                }

                imgui.TextColored(thDim(), u8"\xc3\xee\xf2\xee\xe2\xfb\xe5\x20\xf6\xe2\xe5\xf2\xe0\x3a")
                imgui.Spacing()
                local av_c  = imgui.GetContentRegionAvail().x
                local perRow = 3
                local gap    = S(6)
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
                    local tip = u8"\xcf\xf0\xe5\xf1\xe5\xf2\x20\xab" .. cName .. u8"\xbb\x3a\x20\xed\xe0\xe6\xec\xe8\xf2\xe5\x2c\x20\xf7\xf2\xee\xe1\xfb\x20\xef\xf0\xe8\xec\xe5\xed\xe8\xf2\xfc"
                    if drawStyleSwatchButton("stylepreset"..i, cName, aR,aG,aB, bR,bG,bB, btnWC, S(46), isAct, tip) then
                        if themeIdx then
                            cfg.theme=themeIdx; cfg.custR=-1; cfg.custG=-1; cfg.custB=-1
                            St.custRbuf[0]=aR; St.custGbuf[0]=aG; St.custBbuf[0]=aB
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
                    local pr3,pg3,pb3 = getAcc()
                    imgui.PushStyleColor(imgui.Col.Button,        iv4(pr3*0.22,pg3*0.22,pb3*0.22,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr3*0.40,pg3*0.40,pb3*0.40,1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr3*0.58,pg3*0.58,pb3*0.58,1.0))
                    do local _pbc = prettyBtnPush(8.0)
                    if imgui.Button(u8"\xc7\xe0\xea\xf0\xfb\xf2\xfc##closeColorSettingsPopup", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(30))) then
                        imgui.CloseCurrentPopup()
                    end
                    prettyBtnPop(_pbc) end
                    imgui.PopStyleColor(3)
                end
                imgui.EndPopup()
            end
            popModernPopupStyle(_mpsTop)
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))


        secTitle(u8"\xd0\xe0\xe7\xec\xe5\xf0 \xee\xea\xed\xe0")
        local curWPct = cfg.winWPct > 0 and cfg.winWPct or 0.60
        local curHPct = cfg.winHPct > 0 and cfg.winHPct or 0.76
        St.winWbuf[0] = curWPct
        St.winHbuf[0] = curHPct

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
                imgui.PushStyleColor(imgui.Col.Border, iv4(r*0.7,g*0.7,b*0.7,0.55))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,38.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameBorderSize,1.2) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sw2", St.winWbuf, WIN_W_MIN, 0.98)
                if St.winWbuf[0] < WIN_W_MIN then St.winWbuf[0] = WIN_W_MIN end
                cfg.winWPct = St.winWbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(6)
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
                imgui.PushStyleColor(imgui.Col.Border, iv4(r*0.7,g*0.7,b*0.7,0.55))
                do local _svc2=0
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabRounding,16.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.GrabMinSize,38.0) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FrameBorderSize,1.2) then _svc2=_svc2+1 end
                if pcall(imgui.PushStyleVar,imgui.StyleVar.FramePadding,imgui.ImVec2(6, 8)) then _svc2=_svc2+1 end
                imgui.SliderFloat("##sh2", St.winHbuf, WIN_H_MIN, 0.98)
                if St.winHbuf[0] < WIN_H_MIN then St.winHbuf[0] = WIN_H_MIN end
                cfg.winHPct = St.winHbuf[0]
                if imgui.IsItemDeactivatedAfterEdit and imgui.IsItemDeactivatedAfterEdit() then
                    _sw_win_init = nil
                    saveCfg()
                end
                if _svc2>0 then pcall(imgui.PopStyleVar,_svc2) end; end
                imgui.PopStyleColor(6)
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
            St.fontSizeBuf[0] = curFS
            local dl_f = imgui.GetWindowDrawList()
            local pp_f = imgui.GetCursorScreenPos()
            local aw_f = imgui.GetContentRegionAvail().x
            local cardHf = S(46)
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

                imgui.SetCursorPos(imgui.ImVec2(S(16), (cardHf - S(22))*0.5))
                imgui.TextColored(iv4(0.70,0.82,1.0,1.0), u8"\xd8\xf0\xe8\xf4\xf2")
                imgui.SameLine(0,8)
                imgui.TextColored(iv4(1,1,1,1), string.format("%.0f%%", curFS*100))
                imgui.SameLine(0,10)
                stepBtn("fs_minus", "-", function()
                    cfg.fontSize = math.max(FONT_SIZE_MIN, math.floor((cfg.fontSize - 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)
                imgui.SameLine(0,4)
                stepBtn("fs_plus", "+", function()
                    cfg.fontSize = math.min(FONT_SIZE_MAX, math.floor((cfg.fontSize + 0.05)*100+0.5)/100)
                    St.fontSizeBuf[0] = cfg.fontSize; saveCfg()
                end, 28, 22)

            imgui.EndChild()
            imgui.PopStyleColor()
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ── свой цвет акцента: раньше пикер был всегда развёрнут прямо во
        -- вкладке и занимал много места — теперь это компактная кнопка,
        -- открывающая тот же пикер во всплывающем окне. Перед кнопкой —
        -- квадратик текущего цвета (клик по нему тоже открывает пикер),
        -- сама кнопка сделана ярче и стоит слева, а не на всю ширину ──
        secTitle(u8"\xd1\xe2\xee\xe9\x20\xf6\xe2\xe5\xf2")
        do
            local prA,pgA,pbA = St.custRbuf[0], St.custGbuf[0], St.custBbuf[0]
            local swSizeA = S(36)

            -- квадратик текущего цвета
            imgui.PushStyleColor(imgui.Col.Button,        iv4(prA,pgA,pbA,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prA*1.15),math.min(1,pgA*1.15),math.min(1,pbA*1.15),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prA,pgA,pbA,1.0))
            do local _pbSwA = prettyBtnPush(7.0)
            if imgui.Button("##accentColorSwatch", imgui.ImVec2(swSizeA, swSizeA)) then
                imgui.OpenPopup("##accentColorPopup")
            end
            prettyBtnPop(_pbSwA) end
            imgui.PopStyleColor(3)

            imgui.SameLine(0, S(8))
            -- сама кнопка "Изменить" — ярче, чем раньше (было ×0.30/0.46/0.62)
            imgui.PushStyleColor(imgui.Col.Button,        iv4(math.min(1,prA*0.85),math.min(1,pgA*0.85),math.min(1,pbA*0.85),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prA*1.05),math.min(1,pgA*1.05),math.min(1,pbA*1.05),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prA,pgA,pbA,1.0))
            do local _pbAcc = prettyBtnPush(9.0)
            if imgui.Button(u8"\xc8\xe7\xec\xe5\xed\xe8\xf2\xfc##openAccentColorPopup", imgui.ImVec2(S(140), swSizeA)) then
                imgui.OpenPopup("##accentColorPopup")
            end
            prettyBtnPop(_pbAcc) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(210), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            local _mpsAcc = pushModernPopupStyle()
            if imgui.BeginPopup("##accentColorPopup") then
                if not _custPickerVec then
                    _custPickerVec = imgui.new("float[3]", {St.custRbuf[0], St.custGbuf[0], St.custBbuf[0]})
                end
                _custPickerVec[0], _custPickerVec[1], _custPickerVec[2] = St.custRbuf[0], St.custGbuf[0], St.custBbuf[0]
                local okPicker = pcall(function()
                    imgui.PushItemWidth(S(150))
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
                imgui.EndPopup()
            end
            popModernPopupStyle(_mpsAcc)
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

        -- ── цвет фона строк: тоже теперь кнопка + всплывающий пикер, тот
        -- же стиль: квадратик цвета + яркая кнопка слева ──
        secTitle(u8"\xd4\xee\xed\x20\xf1\xf2\xf0\xee\xea")
        do
            local prB,pgB,pbB = St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0]
            local swSizeB = S(36)

            imgui.PushStyleColor(imgui.Col.Button,        iv4(prB,pgB,pbB,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prB*1.15),math.min(1,pgB*1.15),math.min(1,pbB*1.15),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prB,pgB,pbB,1.0))
            do local _pbSwB = prettyBtnPush(7.0)
            if imgui.Button("##rowBgColorSwatch", imgui.ImVec2(swSizeB, swSizeB)) then
                imgui.OpenPopup("##rowBgColorPopup")
            end
            prettyBtnPop(_pbSwB) end
            imgui.PopStyleColor(3)

            imgui.SameLine(0, S(8))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(math.min(1,prB*0.85),math.min(1,pgB*0.85),math.min(1,pbB*0.85),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(math.min(1,prB*1.05),math.min(1,pgB*1.05),math.min(1,pbB*1.05),1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(prB,pgB,pbB,1.0))
            do local _pbRow = prettyBtnPush(9.0)
            if imgui.Button(u8"\xc8\xe7\xec\xe5\xed\xe8\xf2\xfc##openRowBgColorPopup", imgui.ImVec2(S(140), swSizeB)) then
                imgui.OpenPopup("##rowBgColorPopup")
            end
            prettyBtnPop(_pbRow) end
            imgui.PopStyleColor(3)

            pcall(imgui.SetNextWindowSize, imgui.ImVec2(S(210), 0), imgui.Cond and imgui.Cond.Appearing or 0)
            local _mpsRow = pushModernPopupStyle()
            if imgui.BeginPopup("##rowBgColorPopup") then
                if not _rowBgPickerVec then
                    _rowBgPickerVec = imgui.new("float[3]", {St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0]})
                end
                _rowBgPickerVec[0], _rowBgPickerVec[1], _rowBgPickerVec[2] = St.rowBgRbuf[0], St.rowBgGbuf[0], St.rowBgBbuf[0]
                local okPicker2 = pcall(function()
                    imgui.PushItemWidth(S(150))
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
                imgui.EndPopup()
            end
            popModernPopupStyle(_mpsRow)
        end
        imgui.Spacing()
        imgui.Dummy(imgui.ImVec2(0, S(9)))

    -- ── случайный цвет: одна кнопка внизу вкладки, генерирует случайный
    -- акцентный цвет и сразу его применяет (по просьбе) ──
    imgui.Dummy(imgui.ImVec2(0, S(6)))
    secTitle(u8"\xd1\xeb\xf3\xf7\xe0\xe9\xed\xfb\xe9\x20\xf6\xe2\xe5\xf2")
    do
        local pr4,pg4,pb4 = getAcc()
        imgui.PushStyleColor(imgui.Col.Button,        iv4(pr4*0.35,pg4*0.35,pb4*0.35,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr4*0.55,pg4*0.55,pb4*0.55,1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr4*0.75,pg4*0.75,pb4*0.75,1.0))
        do local _pbRnd = prettyBtnPush(9.0)
        if imgui.Button(u8"\xd1\xeb\xf3\xf7\xe0\xe9\xed\xfb\xe9\x20\xf6\xe2\xe5\xf2##randomAccentColor", imgui.ImVec2(imgui.GetContentRegionAvail().x, S(34))) then
            math.randomseed((os.time() or 0) + (os.clock() or 0) * 1000)
            -- берём цвета не слишком тёмными (0.35..1.0 по каждому каналу),
            -- чтобы акцент оставался хорошо заметным на тёмном фоне
            local rr = 0.35 + math.random() * 0.65
            local gg = 0.35 + math.random() * 0.65
            local bb = 0.35 + math.random() * 0.65
            cfg.custR, cfg.custG, cfg.custB = rr, gg, bb
            St.custRbuf[0], St.custGbuf[0], St.custBbuf[0] = rr, gg, bb
            saveCfg()
        end
        prettyBtnPop(_pbRnd) end
        imgui.PopStyleColor(3)
    end

    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()

    St._resetSettScroll = false
end

-- ============================================================
--  Š’Š�Š›Š�Š”Š�Š� 4: Š˛ Š�Š�Š Š�Š�Š¢Š•  (Š²Ń�Šµ Š±Š»Š¾ŠŗŠø Ń� ŠŗŃ€Š°Ń�ŠøŠ²Š¾Š¹ Ń€Š°Š¼ŠŗŠ¾Š¹)
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

        -- Š‘Š°Š½Š½ŠµŃ€
        imgui.Spacing()
        local bannerH = SFtext(86) * 0.98
        local ps_a    = imgui.GetCursorScreenPos()
        local aw_a    = imgui.GetContentRegionAvail().x
        -- Š¤Š¾Š½ Š±Š°Š½Š½ŠµŃ€Š° Ń€ŠµŠ°Š³ŠøŃ€Ń�ŠµŃ‚ Š½Š° rowBg
        local banBgR = math.max(rra*0.22, 0.06)
        local banBgG = math.max(rga*0.22, 0.06)
        local banBgB = math.max(rba*0.22, 0.06)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(banBgR,banBgG,banBgB,1.0)), 12)
        dl_a:AddRectFilled(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a*0.5, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(rra*0.10,rga*0.10,rba*0.10,0.5)), 12)
        -- обводка баннера сделана ещё тоньше по просьбе (было 1.3)
        dl_a:AddRect(
            imgui.ImVec2(ps_a.x,      ps_a.y),
            imgui.ImVec2(ps_a.x+aw_a, ps_a.y+bannerH),
            imgui.ColorConvertFloat4ToU32(iv4(r,g,b,1.0)), 12, 0, 0.9)
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
            local title2 = "v" .. SCRIPT_VER .. "  |  Arizona RP PC"
            local sz1 = imgui.CalcTextSize(title1)
            local sz2 = imgui.CalcTextSize(title2)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz1.x*0.5, SFtext(14)))
            imgui.TextColored(banTitleCol, title1)
            imgui.SetCursorPos(imgui.ImVec2(aw_a*0.5 - sz2.x*0.5, SFtext(44)))
            imgui.TextColored(thAccBright(), title2)
        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.Spacing()

        -- ── лёгкая карточка: тоньше рамка, чем infoCard() в других вкладках —
        -- здесь текста немного, тяжёлая рамка смотрелась слишком грузно ──
        local function aboutCard(id, cardH, drawFn)
            cardH = SFtext(cardH)
            local rr2,rg2,rb2 = getRowBgColor()
            local dlc = imgui.GetWindowDrawList()
            local pc  = imgui.GetCursorScreenPos()
            local awc = imgui.GetContentRegionAvail().x
            local bgR = math.max(rr2*0.13, 0.07)
            local bgG = math.max(rg2*0.13, 0.07)
            local bgB = math.max(rb2*0.13, 0.07)
            dlc:AddRectFilled(
                imgui.ImVec2(pc.x,     pc.y),
                imgui.ImVec2(pc.x+awc, pc.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(bgR,bgG,bgB,0.97)), 10)
            dlc:AddRect(
                imgui.ImVec2(pc.x,     pc.y),
                imgui.ImVec2(pc.x+awc, pc.y+cardH),
                imgui.ColorConvertFloat4ToU32(iv4(r*0.55,g*0.55,b*0.55,0.50)), 10, 0, 0.8)
            imgui.PushStyleColor(imgui.Col.ChildBg, iv4(0,0,0,0))
            imgui.BeginChild(id, imgui.ImVec2(awc - 2, cardH), false,
                imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
                drawFn(awc, cardH)
            imgui.EndChild()
            imgui.PopStyleColor()
            imgui.Spacing()
        end

        -- размер текста вкладки "О скрипте" приведён к 100% (раньше был
        -- дополнительно уменьшен до 98%, а заголовки карточек ещё и
        -- увеличены до 108% — по просьбе весь текст сделан одного,
        -- обычного размера, без доп. масштабирования)
        local aboutBaseScale = St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25)

        secTitle(u8"\xd0\xe0\xe7\xf0\xe0\xe1\xee\xf2\xf7\xe8\xea")
        -- ── карточка разработчика расширена: компактные прямоугольные
        -- кнопки Telegram/Discord (примерно 20:4 по пропорциям) выведены
        -- прямо сюда, отдельная большая карточка "Связь" с крупными
        -- круглыми кнопками убрана — так меню компактнее ──
        aboutCard("##devcard", 118, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcd\xe8\xea \xe2 \xe8\xe3\xf0\xe5:")
            imgui.SameLine(0,8)
            imgui.TextColored(thAccBright(), "Marco_Santiago")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(42)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xc2\xe5\xf0\xf1\xe8\xff:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v" .. SCRIPT_VER)
            imgui.SameLine(0,14)
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xcf\xf0\xee\xe5\xea\xf2:")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(0.90,0.90,0.90,1.0), "Arizona RP PC")
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(72)))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0), "MoonLoader Lua Script")
            imgui.SetWindowFontScale(aboutBaseScale)

            -- компактные прямоугольные кнопки связи (~20x4 по пропорциям)
            local btnCW, btnCH = SFtext(96), SFtext(20)
            local gapC = SFtext(10)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(96)))
            do
                local tgHandle = "@Marco8877"
                local tgUrl    = "https://t.me/Marco8877"
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.09,0.42,0.68,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.13,0.58,0.90,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.18,0.72,1.00,1.0))
                do local _pbtg = prettyBtnPush(6.0)
                if imgui.Button(u8"Telegram##tgopen", imgui.ImVec2(btnCW, btnCH)) then
                    -- сначала пробуем открыть ссылку без консоли (WinAPI
                    -- ShellExecuteA), и только если ffi недоступен —
                    -- запасной os.execute('start ...'), который может на
                    -- мгновение показать окно cmd.exe
                    local opened = winOpenUrl(tgUrl)
                    if not opened then
                        pcall(function()
                            opened = os.execute('start "" "' .. tgUrl .. '"') ~= nil
                        end)
                    end
                    pcall(function()
                        if imgui.SetClipboardText then imgui.SetClipboardText(tgHandle) end
                    end)
                    if opened then
                        -- sampAddChatMessage хочет сырые CP1251-байты, а не UTF8 —
                        -- u8() тут был лишним и превращал текст в чате в кракозябры
                        pcall(sampAddChatMessage, "{00FF88}[MSW] " .. "\xee\xf2\xea\xf0\xfb\xe2\xe0\xfe \xd2\xe5\xeb\xe5\xe3\xf0\xe0\xec: " .. tgHandle, -1)
                    else
                        pcall(sampAddChatMessage, "{00CCFF}[MSW] Telegram: " .. tgHandle .. " (\xf1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xee)", -1)
                    end
                end
                prettyBtnPop(_pbtg) end
                imgui.PopStyleColor(3)
            end
            imgui.SameLine(0, gapC)
            do
                local dcHandle = "@marco_santiago888"
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.22,0.24,0.68,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.29,0.33,0.86,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.37,0.42,1.00,1.0))
                do local _pbdc = prettyBtnPush(6.0)
                if imgui.Button(u8"Discord##dccopy", imgui.ImVec2(btnCW, btnCH)) then
                    local copied = false
                    pcall(function()
                        if imgui.SetClipboardText then
                            imgui.SetClipboardText(dcHandle)
                            copied = true
                        end
                    end)
                    if copied then
                        pcall(sampAddChatMessage, "{00FF88}[MSW] " .. "\xd1\xea\xee\xef\xe8\xf0\xee\xe2\xe0\xed\xee: " .. dcHandle, -1)
                    else
                        pcall(sampAddChatMessage, "{7289DA}[MSW] Discord: " .. dcHandle, -1)
                    end
                end
                prettyBtnPop(_pbdc) end
                imgui.PopStyleColor(3)
            end
        end)


        -- Карточка описания скрипта
        secTitle(u8"\xce\xef\xe8\xf1\xe0\xed\xe8\xe5")
        aboutCard("##desccard", 78, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(12)))
            imgui.PushTextWrapPos(aw - SFtext(16))
            imgui.TextColored(iv4(0.85,0.87,0.95,1.0),
                u8"PC Stats \xf1\xee\xe1\xe8\xf0\xe0\xe5\xf2\x20\xf1\xf2\xe0\xf2\xe8\xf1\xf2\xe8\xea\xf3\x20\xef\xe5\xf0\xf1\xee\xed\xe0\xe6\xe0\x20\xe2\x20\xee\xe4\xed\xee\xec\x20\xee\xea\xed\xe5\x20\xe8\x2c\x20\xef\xf0\xe8\x20\xe6\xe5\xeb\xe0\xed\xe8\xe8\x2c\x20\xef\xf3\xe1\xeb\xe8\xea\xf3\xe5\xf2\x20\xe5\xb8\x20\xed\xe0\x20\xf1\xe0\xe9\xf2\xe5\x2d\xeb\xe8\xe4\xe5\xf0\xe1\xee\xf0\xe4\xe5\x20\xe4\xeb\xff\x20\xef\xee\xe8\xf1\xea\xe0\x20\xef\xee\x20\xed\xe8\xea\xf3\x2e")
            imgui.PopTextWrapPos()
            imgui.SetWindowFontScale(aboutBaseScale)
        end)
        -- ── карточка обновлений: версия, проверка на GitHub, кнопка
        -- обновить+перезапустить (появляется только если есть новая) ──
        secTitle(u8"\xce\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xff")
        aboutCard("##updcard", 118, function(aw, ch)
            imgui.SetWindowFontScale(aboutBaseScale)
            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(10)))
            imgui.TextColored(iv4(0.55,0.62,0.80,1.0), u8"\xd2\xe5\xea\xf3\xf9\xe0\xff\x20\xe2\xe5\xf0\xf1\xe8\xff\x3a")
            imgui.SameLine(0,8)
            imgui.TextColored(iv4(1,1,1,1), "v" .. SCRIPT_VER)

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(32)))
            imgui.PushTextWrapPos(aw - SFtext(16))
            if _updStatus then
                local stCol = _updAvailable and iv4(0.35,0.95,0.55,1.0) or iv4(0.68,0.72,0.82,1.0)
                imgui.TextColored(stCol, u8(_updStatus))
            else
                imgui.TextColored(iv4(0.45,0.48,0.56,1.0), "-")
            end
            imgui.PopTextWrapPos()

            local btnFullW = aw - SFtext(32)
            local btnHalfW = (btnFullW - SFtext(8)) * 0.5
            local pr,pg,pb = getAcc()

            imgui.SetCursorPos(imgui.ImVec2(SFtext(16), SFtext(64)))
            imgui.PushStyleColor(imgui.Col.Button,        iv4(pr*0.20,pg*0.20,pb*0.20,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(pr*0.36,pg*0.36,pb*0.36,1.0))
            imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(pr*0.52,pg*0.52,pb*0.52,1.0))
            do local _pbu = prettyBtnPush(8.0)
            local checkLabel = _updChecking and u8"\xcf\xf0\xee\xe2\xe5\xf0\xea\xe0\x2e\x2e\x2e" or u8"\xcf\xf0\xee\xe2\xe5\xf0\xe8\xf2\xfc\x20\xee\xe1\xed\xee\xe2\xeb\xe5\xed\xe8\xe5"
            if imgui.Button(checkLabel .. "##checkUpdateBtn", imgui.ImVec2(_updAvailable and btnHalfW or btnFullW, SFtext(28))) then
                checkForUpdate(false)
            end
            prettyBtnPop(_pbu) end
            imgui.PopStyleColor(3)

            if _updAvailable then
                imgui.SameLine(0, SFtext(8))
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.18,0.55,0.30,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.22,0.72,0.38,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.28,0.90,0.48,1.0))
                do local _pbu2 = prettyBtnPush(8.0)
                local upLabel = _updDownloading and u8"\xc7\xe0\xe3\xf0\xf3\xe7\xea\xe0\x2e\x2e\x2e" or u8"\xce\xe1\xed\xee\xe2\xe8\xf2\xfc\x20\xe8\x20\xef\xe5\xf0\xe5\xe7\xe0\xef\xf3\xf1\xf2\xe8\xf2\xfc"
                if imgui.Button(upLabel .. "##doUpdateBtn", imgui.ImVec2(btnHalfW, SFtext(28))) then
                    downloadAndApplyUpdate()
                end
                prettyBtnPop(_pbu2) end
                imgui.PopStyleColor(3)
            end
        end)


    -- ── нижний отступ, чтобы последний блок не прилипал к краю окна ──
    imgui.Dummy(imgui.ImVec2(0, S(40)))

    imgui.EndChild()
    imgui.PopStyleColor()
    St._resetSettScroll = false
end

-- ============================================================
--  ЗАКРЫТИЕ ГЛАВНОГО МЕНЮ ПО ESC — УБРАНО ПО ПРОСЬБЕ
-- ============================================================
-- Раньше здесь была функция onKeyDown(), которая перехватывала Esc и
-- закрывала меню скрипта (и панель настроек финансов) через глобальный
-- хук клавиатуры MoonLoader'а. По просьбе этот функционал полностью
-- убран: меню теперь закрывается ТОЛЬКО повторным вызовом команды чата
-- (см. registerMenuCommand / toggleMenuWindow ниже) или крестиком/своей
-- кнопкой в самом окне. Esc больше никак скриптом не перехватывается —
-- нажатие Esc ведёт себя как обычно в игре (открывает штатное меню
-- паузы Arizona), скрипт в это не вмешивается.

-- ============================================================
--  ГЛАВНОЕ ОКНО
-- ============================================================
imgui.OnFrame(
    function() return St.winOpen end,
    function(self)
        if St.winOpen then
        -- FIX: сбрасываем счётчики уникальных ID в начале каждого кадра
        St._metricTileIdx = 0
        St._chipIdx = 0
        St.chipSide = false
        local sw = imgui.GetIO().DisplaySize.x
        local sh = imgui.GetIO().DisplaySize.y

        -- Š°Š²Ń‚Š¾Š¼Š°Ń�Ń¨Ń‚Š°Š± Š²Ń�ŠµŠ³Š¾ UI ŠæŠ¾Š´ Ń‚ŠµŠŗŃ�Ń‰ŠµŠµ Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ (Š±Š°Š·Š° 1080p)
        if sh > 0 then
            St.UI_SCALE = math.max(St.UI_SCALE_MIN, math.min(St.UI_SCALE_MAX, sh / 1080.0))
        end

        -- ŠµŃ�Š»Šø Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ/Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ³Ń€Š¾Š²Š¾Š³Š¾ Š¾ŠŗŠ½Š° ŠøŠ·Š¼ŠµŠ½ŠøŠ»Š¾Ń�Ń� (Š²Ń‹Ń¨ŠµŠ» ŠøŠ· Š¾ŠŗŠ½Š° / Ń�Š¼ŠµŠ½ŠøŠ» Ń€Š°Š·Ń€ŠµŃ¨ŠµŠ½ŠøŠµ) ā€”
        -- Š·Š°Ń�Ń‚Š°Š²Š»Ń¸ŠµŠ¼ ŠæŠµŃ€ŠµŃ�Ń‡ŠøŃ‚Š°Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ ŠøŠ¼ŠæŠ»Ń�Ń‚-Š¾ŠŗŠ½Š°, ŠøŠ½Š°Ń‡Šµ Cond.Once Š±Š¾Š»Ń�Ń¸Šµ Š½Šµ Š´Š°Ń�Ń‚ ŠµŠ¼Ń� ŠøŠ·Š¼ŠµŠ½ŠøŃ‚Ń�Ń�Ń¸
        if math.abs(sw - St._lastSw) > 2 or math.abs(sh - St._lastSh) > 2 then
            if St._lastSw > 0 then _sw_win_init = nil end
            St._lastSw, St._lastSh = sw, sh
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

        -- ── анимированный сдвиг главного окна влево, пока открыта (и
        -- пристыкована) панель настроек "Финансы"; двигаем окно только
        -- на кадрах, где фаза анимации реально меняется, чтобы в остальное
        -- время окно оставалось свободно перетаскиваемым мышью ──
        do
            local tnow = os.clock()
            if St._finShiftLastTime == nil then St._finShiftLastTime = tnow end
            local dt = tnow - St._finShiftLastTime
            St._finShiftLastTime = tnow
            if dt < 0 or dt > 0.5 then dt = 0 end -- защита от скачков (первый кадр / лаги)

            local target = (St._financeSettingsOpen and not St._financeSettingsDetached) and 1.0 or 0.0
            local speed  = 6.0 -- скорость анимации, полный сдвиг за ~1/speed сек
            if St._finShiftAnim < target then
                St._finShiftAnim = math.min(target, St._finShiftAnim + dt*speed)
            elseif St._finShiftAnim > target then
                St._finShiftAnim = math.max(target, St._finShiftAnim - dt*speed)
            end

            -- FIX: раньше сдвигали на всю ширину панели (330), это было
            -- слишком далеко. Теперь сдвигаем на небольшое фиксированное
            -- расстояние (~4 маленьких квадратика по 24px) — если нужно
            -- ещё меньше/больше, просто поменяй число 96 ниже.
            local finShiftPx = S(96) * St._finShiftAnim

            -- FIX: раньше сдвиг считался ПРИРАЩЕНИЕМ к позиции окна из
            -- прошлого кадра (St._mainWinPos), которая сама уже могла быть
            -- сдвинута или устареть (например, после закрытия/переоткрытия
            -- окна). Ошибки накапливались и окно улетало влево гораздо
            -- сильнее, чем ширина панели. Теперь запоминаем "домашнюю"
            -- (несдвинутую) позицию окна ОДИН раз, когда сдвига ещё нет,
            -- и дальше всегда считаем целевую позицию от неё, а не от
            -- позиции прошлого кадра — дрейф невозможен в принципе.
            if St._finShiftAppliedPx < 0.5 and St._mainWinPos then
                St._finShiftAnchorX = St._mainWinPos.x
            end

            St._finShiftAppliedPx = finShiftPx

            if St._finShiftAnchorX and finShiftPx > 0.01 then
                imgui.SetNextWindowPos(imgui.ImVec2(St._finShiftAnchorX - finShiftPx, St._mainWinPos.y), imgui.Cond.Always)
            end
        end

        applyStyle()
        -- Š¼Š°Ń�Ń�Ń‚Š°Š± Ń�Ń€ŠøŃ„Ń‚Š°: ŠæŃ€ŠøŠ¼ŠµŠ½Ń¸ŠµŠ¼ Ń‡ŠµŃ€ŠµŠ· SetWindowFontScale ŠæŠ¾Ń�Š»Šµ Begin
        -- Š¯Š° Š�Š� Š¾ŠŗŠ½Š¾ Š¼Š¾Š¶Š½Š¾ Š´Š²ŠøŠ³Š°Ń‚Ń� Šø Š¼ŠµŠ½Ń¸Ń‚Ń� Ń€Š°Š·Š¼ŠµŃ€ Š¼Ń‹Ń�ŠŗŠ¾Š¹ (Š½Š° Š¼Š¾Š±ŠøŠ»Šµ Ń¨Ń‚Š¾
        -- Š±Ń‹Š»Š¾ Š¾Ń‚ŠŗŠ»ŃˇŃ‡ŠµŠ½Š¾, Ń‡Ń‚Š¾Š±Ń‹ Ń�Š»Ń�Ń‡Š°Š¹Š½Ń‹Šµ Ń‚Š°ŠæŃ‹ Š½Šµ Š´Š²ŠøŠ³Š°Š»Šø Š¾ŠŗŠ½Š¾ Š½Š° Ń‚Š°Ń‡Ń�ŠŗŃ€ŠøŠ½Šµ)
        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar
        imgui.Begin("###sw", nil, flags)
        imgui.SetWindowFontScale(St.UI_SCALE * (cfg.fontSize > 0 and cfg.fontSize or 1.25))

        -- закрытие главного меню по Esc теперь целиком в onKeyDown() —
        -- см. блок "ЗАКРЫТИЕ ГЛАВНОГО МЕНЮ ПО ESC" выше по файлу; там оно
        -- срабатывает надёжно независимо от фокуса ImGui-окна


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
                local titleStr = u8"  PC Stats  v1.1.2"
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
            -- иконки-префиксы перед текстом вкладок — настоящие иконки
            -- FontAwesome (fa-user/fa-hand-fist/fa-sack-dollar/fa-gear/
            -- fa-circle-info), подключены отдельным icon-шрифтом в
            -- MergeMode, см. блок "ШРИФТ ИКОНОК ВКЛАДОК" в начале файла
            local tabDef = {
                { ICON_USER.." "..u8"\xcf\xe5\xf0\xf1\xee\xed\xe0\xe6",    0.43,0.71,1.0  },
                { ICON_FIST.." "..u8"\xc1\xee\xe9",                          1.0, 0.55,0.20 },
                { ICON_SACK.." "..u8"\xd4\xe8\xed\xe0\xed\xf1\xfb",                  0.25,0.92,0.48 },
                { ICON_GEAR.." "..u8"\xcd\xe0\xf1\xf2\xf0\xee\xe9\xea\xe8", 0.75,0.75,0.80 },
                { ICON_INFO.." "..u8"\xce \xf1\xea\xf0.",                    0.75,0.45,1.0  },
            }
            for i, td in ipairs(tabDef) do
                if i > 1 then imgui.SameLine(0,S(4)) end
                if tabButton(td[1], St.activeTab==i, tw, td[2],td[3],td[4]) then
                    if St.activeTab ~= i then St._resetCharScroll = true; St._resetSettScroll = true; St.accPopupOpen = false end
                    St.activeTab=i
                    if cfg.lastTab ~= i then cfg.lastTab = i; saveCfg() end
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
        if St.activeTab == 1 and St.statsData and St.statsData.name ~= "" then
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
                imgui.TextColored(thAccBright(), u8(St.statsData.name))
                if St.statsData.accountNumber~="" then
                    imgui.SameLine(0,7)
                    imgui.TextColored(hdrTextCol, "["..St.statsData.accountNumber.."]")
                end
                -- Š�Ń‚Ń€Š¾ŠŗŠ° 2: Š£Ń€. + EXP + HP
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
        if St.waitingStats then
            imgui.TextColored(thGold(), u8"  \xe7\xe0\xe3\xf0\xf3\xe7\xea\xe0...")
            imgui.Spacing()
        elseif St.statusMsg ~= "" and St.statusMsg ~= u8"\xc3\xee\xf2\xee\xe2\xee" then
            imgui.TextColored(thGold(), "  "..St.statusMsg)
            imgui.Spacing()
        end

        -- ā”€ā”€ Š�Š•Š¢Š Š�Š�Š� (Ń‚Š¾Š»Ń�ŠŗŠ¾ Š²ŠŗŠ»Š°Š´ŠŗŠø 1-2) ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
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

        -- ā”€ā”€ Š�Š˛Š¯Š¢Š•Š¯Š¢ ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
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

        -- ā”€ā”€ Š¯Š�Š–Š¯Š�Š• Š�Š¯Š˛Š�Š�Š� ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€ā”€
        local r4,g4,b4 = getAcc()
        do
            if St.activeTab == 5 then
                -- Š’ŠŗŠ»Š°Š´ŠŗŠ° "Š¾ Ń�ŠŗŃ€ŠøŠæŃ‚Šµ": Š¢Š¾Š»Ń�ŠŗŠ¾ Š—Š°ŠŗŃ€Ń‹Ń‚Ń� (Š²Š¾ Š²Ń�Ńˇ Ń¨ŠøŃ€ŠøŠ½Ń�, Š±ŠµŠ· ŠŗŠ½Š¾ŠæŠŗŠø Š�Š±Š½Š¾Š²ŠøŃ‚Ń�)
                local awClose = imgui.GetContentRegionAvail().x
                imgui.PushStyleColor(imgui.Col.Button,        iv4(0.35,0.06,0.06,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, iv4(0.58,0.12,0.12,1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive,  iv4(0.80,0.22,0.22,1.0))
                if imgui.Button(u8"  \xc7\xe0\xea\xf0\xfb\xf2\xfc  ", imgui.ImVec2(awClose, S(40))) then
                    St.winOpen=false; St.activeTab=1; _sw_win_init=nil
                    St._financeSettingsOpen=false; St._finShiftAnim=0.0; St._finShiftAppliedPx=0.0; St._finShiftAnchorX=nil
                end
                imgui.PopStyleColor(3)
            else
                local bw = (imgui.GetContentRegionAvail().x - 6) * 0.5
                if St.activeTab == 4 then
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š½Š°Ń�Ń‚Ń€Š¾ŠµŠŗ: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� + Š—Š°ŠŗŃ€Ń‹Ń‚Ń�
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
                    -- Š’ŠŗŠ»Š°Š´ŠŗŠ° Š¤ŠøŠ½Š°Š½Ń�Ń‹: ŠŗŠ½Š¾ŠæŠŗŠ° Š�Š±Ń€Š¾Ń� ŠŗŃ�Ń€Ń�Š° Š²Š°Š»Ń�Ń‚ (Š²Š¼ŠµŃ�Ń‚Š¾ Š�Š±Š½Š¾Š²ŠøŃ‚Ń�)
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
                    St.winOpen=false; St.activeTab=1; _sw_win_init=nil
                    St._financeSettingsOpen=false; St._finShiftAnim=0.0; St._finShiftAppliedPx=0.0; St._finShiftAnchorX=nil
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
        end -- konec if St.winOpen

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
    -- St.statsData Š¯Š• Ń�Š±Ń€Š°Ń�Ń‹Š²Š°ŠµŠ¼ ā€” Ń�Ń‚Š°Ń€Ń‹Šµ Š´Š°Š½Š½Ń‹Šµ Š²ŠøŠ´Š½Ń‹ ŠæŠ¾ŠŗŠ° Š½Šµ ŠæŠ¾Š»Ń�Ń‡ŠøŠ¼ Š½Š¾Š²Ń‹Šµ
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
    -- Š·Š°Ń‰ŠøŃ‚Š° Š¾Ń‚ ŠæŃ�Ń�Ń‚Š¾Š³Š¾ ŠŗŠ¾Š»Š»ŠµŠŗŃ‚Š¾Ń€Š°
    if next(tdCollector) == nil then
        St.waitingStats = false
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
        St.statsData=parseStats(raw)
        St.statusMsg=u8"\xc3\xee\xf2\xee\xe2\xee"
        pcall(sendStatsReport)
    else
        St.statusMsg=u8"\xcd\xe5\xf2 \xe4\xe0\xed\xed\xfb\xf5"
    end
    St.waitingStats=false; captureStarted=false; tdCollector={}; tdCollectorSize=0
    finalizing = false
end

-- ============================================================
--  ОБРАБОТЧИКИ SAMP
-- ============================================================

function sampev.onShowDialog(id, style, title, btn1, btn2, text)
    -- ── автообновление курса валют через телефон (см. fetchRatesViaCEF):
    -- приложение "Криптовалюта" открывается напрямую по ID через RakNet
    -- (openCryptoAppDirect), поэтому здесь просто ждём диалог, который
    -- реально похож на экран "Курс валют" (проверяем и заголовок, и текст),
    -- разбираем его и закрываем — остальные диалоги не трогаем ──
    if _phoneFetchState == "waiting" then
        local handled = false
        pcall(function()
            if isCryptoRatesDialog(title, text) then
                local got = parsePhoneRatesText(tostring(text or ""))
                _phoneFetchState = false
                if got then
                    St._cefLastResult = "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0"
                    pcall(sampAddChatMessage, "{00FF88}[Stats] " .. "\xea\xf3\xf0\xf1\xfb \xee\xe1\xed\xee\xe2\xeb\xe5\xed\xfb \xe8\xe7 \xf2\xe5\xeb\xe5\xf4\xee\xed\xe0", -1)
                else
                    St._cefLastResult = "\xed\xe5 \xf3\xe4\xe0\xeb\xee\xf1\xfc \xf0\xe0\xe7\xee\xe1\xf0\xe0\xf2\xfc \xea\xf3\xf0\xf1\xfb \xe2 \xee\xf2\xea\xf0\xfb\xf2\xee\xec \xf0\xe0\xe7\xe4\xe5\xeb\xe5"
                    pcall(sampAddChatMessage, "{FF6666}[Stats] " .. tostring(St._cefLastResult), -1)
                end
                -- закрываем меню курсов и саму вкладку телефона, чтобы не
                -- оставлять телефон открытым поверх интерфейса игрока
                pcall(sampCloseCurrentDialog, -1)
                lua_thread.create(function()
                    wait(150)
                    pcall(sampCloseCurrentDialog, -1)
                end)
                handled = true
            end
        end)
        if handled then
            _cefFetching = false
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
                if St.waitingStats then isStatsDialog = true end
                St.statsData       = parseStats(cleaned)
                St.statusMsg       = u8"\xc3\xee\xf2\xee\xe2\xee"
                pcall(sendStatsReport)
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
    -- Š¾Š±Ń€Š°Š±Š°Ń‚Ń‹Š²Š°ŠµŠ¼ Š¢Š˛Š›Š¬Š�Š˛ ŠŗŠ¾Š³Š´Š° Š°ŠŗŃ‚ŠøŠ²Š½Š¾ Š¶Š´Ń‘Š¼ Š¾Ń‚Š²ŠµŃ‚ /stats
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
    -- 1. Š�Š½Š°Ń‡Š°Š»Š° Š³Ń€Ń�Š·ŠøŠ¼ ŠŗŠ¾Š½Ń„ŠøŠ³
    loadCfg()
    if saveCfgLater then saveCfg(); saveCfgLater = false end
    St.activeTab = cfg.lastTab or 1

    -- 2. Š�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·ŠøŃ€Ń�ŠµŠ¼ Š²Ń�Šµ Š±Ń�Ń„ŠµŃ€Ń‹
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
    -- Ń�ŠøŠ½Ń…Ń€Š¾Š½ŠøŠ·Š°Ń†ŠøŃ¸ Ń†Š²ŠµŃ‚Š° Ń„Š¾Š½Š° Ń�Ń‚Ń€Š¾Šŗ
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
    pcall(function() St.menuCmdBuf = imgui.new("char[16]", cfg.menuOpenCmd or "sw") end)

    -- 3. Š–Š´Ń‘Š¼ SAMP ā€” Š±ŠµŠ· Š»ŠøŃ�Š½ŠøŃ… Š·Š°Š´ŠµŃ€Š¶ŠµŠŗ
    repeat wait(100) until isSampAvailable()

    -- 4. Š ŠµŠ³ŠøŃ�Ń‚Ń€ŠøŃ€Ń�ŠµŠ¼ ŠŗŠ¾Š¼Š°Š½Š´Ń�
    -- 4. Регистрируем команду открытия меню (имя команды настраивается
    -- в "Настройках"; registerMenuCommand() умеет перерегистрировать её
    -- на лету при смене без перезапуска скрипта)
    function toggleMenuWindow()
        if not isSampAvailable() then return end
        St.winOpen = not St.winOpen
        if St.winOpen then
            _sw_win_init = nil
            requestStats()
        else
            St.activeTab = 1
        end
    end

    function registerMenuCommand(cmdName)
        cmdName = tostring(cmdName or "sw"):gsub("^/+", ""):gsub("%s+", "")
        if cmdName == "" then cmdName = "sw" end
        if _registeredMenuCmd then
            pcall(sampUnregisterChatCommand, _registeredMenuCmd)
        end
        local ok = pcall(sampRegisterChatCommand, cmdName, toggleMenuWindow)
        if ok then _registeredMenuCmd = cmdName end
        return ok, cmdName
    end

    registerMenuCommand(cfg.menuOpenCmd)

    -- уведомляем игрока в чат, что подхватилась ранее сохранённая
    -- (не дефолтная) команда открытия меню — по просьбе: "если игрок
    -- сменил команду и перезашёл, чтобы приходило уведомление в чат"
    if _restoredMenuCmd then
        pcall(sampAddChatMessage, "{00FF88}[PC Stats] " ..
            "\xc2\xee\xf1\xf1\xf2\xe0\xed\xee\xe2\xeb\xe5\xed\xe0\x20\xea\xee\xec\xe0\xed\xe4\xe0\x20\xee\xf2\xea\xf0\xfb\xf2\xe8\xff\x20\xec\xe5\xed\xfe: /" .. tostring(_registeredMenuCmd or cfg.menuOpenCmd), -1)
    end

    -- 5. Š�Š¾Š¾Š±Ń‰ŠµŠ½ŠøŠµ Š² Ń‡Š°Ń‚ ā€” Š¶Š´Ń‘Š¼ Š Š•Š�Š›Š¬Š¯Š«Š™ Ń�ŠæŠ°Š²Š½ ŠøŠ³Ń€Š¾ŠŗŠ°
    -- Avtoproverka obnovleniy pri starte skripta: tikho (bez soobshcheniya
    -- "obnovleniy net") proveryaem versiyu na GitHub cherez checkForUpdate.
    -- Sama checkForUpdate() uzhe pishet v chat "Dostupna novaya versiya: vX.X.X",
    -- kogda nahodit obnovlenie, dazhe v tikhom rezhime — eto i est' trebuemoe
    -- "esli est' novaya versiya - vyvodit' v chat". Esli obnovlenie nayden,
    -- srazu skachivaem i primenyaem ego avtomaticheski.
    lua_thread.create(function()
        wait(3000)
        pcall(checkForUpdate, true)
        local waited = 0
        while _updChecking and waited < 8000 do wait(200); waited = waited + 200 end
        if _updAvailable then
            pcall(downloadAndApplyUpdate)
        end
    end)

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
            "{00FF88}[MSW v1.1.2] {FFFFFF}PC Stats | Cmd: {00FF88}/sw", -1)
    end)

    -- 6. Š“Š»Š°Š²Š½Ń‹Š¹ Ń†ŠøŠŗŠ» ā€” Š² Š¾Ń‚Š´ŠµŠ»Ń�Š½Š¾Š¼ ŠæŠ¾Ń‚Š¾ŠŗŠµ, main() Š·Š°Š²ŠµŃ€Ń�Š°ŠµŃ‚Ń�Ń¸
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
