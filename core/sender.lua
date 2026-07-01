--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║          Blox Fruits Account Manager — Lua Sender           ║
    ║          Compatible: Delta, Hydrogen, Fluxus, KRNL,         ║
    ║                      Arceus X, UGPhone, VMOS, VSPhone       ║
    ╚══════════════════════════════════════════════════════════════╝

    Chức năng:
      ✓ Đọc Level, Beli, Fragments, Race realtime
      ✓ Đọc Sea (tự tính từ level)
      ✓ Đọc Fruit, Sword, Gun, Melee hiện đang hold
      ✓ Đọc toàn bộ Inventory (Backpack)
      ✓ Đọc Accessories (Helm, Cape, Scarf)
      ✓ Đọc Materials (đếm số lượng)
      ✓ Gửi JSON về FastAPI relay
      ✓ API Key authentication
      ✓ Anti-spam (5 giây / lần)
      ✓ Auto retry tối đa 3 lần nếu lỗi
      ✓ Heartbeat online / offline
      ✓ Tự detect executor (syn.request / http_request / request)
]]

-- ═══════════════════════════════════════════════════════════════
-- CONFIG — Thay đổi tại đây
-- ═══════════════════════════════════════════════════════════════

local CONFIG = {
    API_KEY         = "BF_SECRET_2024",   -- Phải khớp với .env trên server
    UPDATE_INTERVAL = 5,                   -- Giây giữa mỗi lần gửi
    RETRY_LIMIT     = 3,                   -- Số lần retry mỗi endpoint nếu lỗi
    RETRY_DELAY     = 2,                   -- Giây chờ trước khi retry
    TIMEOUT         = 10,                  -- Timeout mỗi request
    DEBUG           = true,                -- In log ra console

    -- ─────────────────────────────────────────────────────────
    -- ENDPOINTS — Gửi song song đến tất cả server trong list
    -- ─────────────────────────────────────────────────────────
    ENDPOINTS = {
        {
            name = "Render Backend (Japan/HK)",
            url  = "https://tr-tt-3.onrender.com/relay",
        },
    },
}

-- ═══════════════════════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════════════════════

local HttpService  = game:GetService("HttpService")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local LocalPlayer  = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════
-- UTILS
-- ═══════════════════════════════════════════════════════════════

local function log(msg)
    if CONFIG.DEBUG then
        print("[BF-SENDER] " .. tostring(msg))
    end
end

local function warn_log(msg)
    warn("[BF-SENDER] " .. tostring(msg))
end

-- Safe traverse path trong game hierarchy
-- Ví dụ: SafeFind({"Players", "TestUser", "Data", "Level"})
local function SafeFind(path)
    local current = game
    for _, v in ipairs(path) do
        local child = current:FindFirstChild(v)
        if child then
            current = child
        else
            return nil
        end
    end
    return current
end

-- Safe get .Value từ node
local function SafeValue(path, default)
    local node = SafeFind(path)
    if node and node.Value ~= nil then
        return node.Value
    end
    return default
end

-- ═══════════════════════════════════════════════════════════════
-- HTTP SENDER — tự detect executor
-- ═══════════════════════════════════════════════════════════════

local function HttpPost(url, body)
    -- Thử syn.request (Synapse / Hydrogen / Delta)
    if syn and syn.request then
        local res = syn.request({
            Url     = url,
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })
        return res.Success or (res.StatusCode and res.StatusCode < 400), res.Body or ""
    end

    -- Thử http_request (Fluxus / Arceus X)
    if http_request then
        local res = http_request({
            Url     = url,
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })
        return res.Success or (res.StatusCode and res.StatusCode < 400), res.Body or ""
    end

    -- Thử request (KRNL)
    if request then
        local res = request({
            Url     = url,
            Method  = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = body,
        })
        return res.Success or (res.StatusCode and res.StatusCode < 400), res.Body or ""
    end

    -- Fallback: HttpService (chỉ hoạt động nếu HttpService được bật trong game)
    local ok, result = pcall(function()
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)
    return ok, result or ""
end

-- ═══════════════════════════════════════════════════════════════
-- PLAYER DATA READERS
-- ═══════════════════════════════════════════════════════════════

local function GetLevel()
    return SafeValue({"Players", LocalPlayer.Name, "Data", "Level"}, 0)
end

local function GetBeli()
    return SafeValue({"Players", LocalPlayer.Name, "Data", "Beli"}, 0)
end

local function GetFragments()
    return SafeValue({"Players", LocalPlayer.Name, "Data", "Fragments"}, 0)
end

local function GetRace()
    return SafeValue({"Players", LocalPlayer.Name, "Data", "Race"}, "Unknown")
end

-- Sea = tính từ level
local function GetSea()
    local lv = GetLevel()
    if lv < 700 then
        return 1
    elseif lv < 1500 then
        return 2
    else
        return 3
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EQUIPMENT READERS
-- ═══════════════════════════════════════════════════════════════

-- Danh sách weapon theo category
local SWORDS = {
    ["Cursed Dual Katana"] = true,
    ["Shark Anchor"]       = true,
    ["Yama"]               = true,
    ["Tushita"]            = true,
    ["Dual Headed Blade"]  = true,
    ["Dark Blade"]         = true,
    ["Dragon Trident"]     = true,
    ["Saber"]              = true,
    ["Saddi"]              = true,
    ["Shisui"]             = true,
    ["Wando"]              = true,
    ["Pole (1st Form)"]    = true,
    ["Pole (2nd Form)"]    = true,
    ["True Triple Katana"] = true,
    ["Triple Katana"]      = true,
    ["Midnight Blade"]     = true,
    ["Gravity Cane"]       = true,
    ["Buddy Sword"]        = true,
    ["Bisento"]            = true,
    ["Bisento V2"]         = true,
    ["Canvander"]          = true,
    ["Dark Dagger"]        = true,
    ["Rengoku"]            = true,
    ["Sharkman Karate"]    = true,
    ["Hallow Scythe"]      = true,
    ["Iceberg Rapier"]     = true,
    ["Longsword"]          = true,
    ["Soul Cane"]          = true,
    ["Trident"]            = true,
}

local GUNS = {
    ["Soul Guitar"]    = true,
    ["Kabucha"]        = true,
    ["Serpent Bow"]    = true,
    ["Flintlock"]      = true,
    ["Musket"]         = true,
    ["Refined Slingshot"] = true,
    ["Slingshot"]      = true,
    ["Double Gun"]     = true,
    ["Cannon"]         = true,
    ["Bazooka"]        = true,
    ["Acidum Rifle"]   = true,
    ["Ice Spear"]      = true,
    ["Bizarre Rifle"]  = true,
}

local MELEES = {
    ["Godhuman"]       = true,
    ["Sanguine Art"]   = true,
    ["Superhuman"]     = true,
    ["Death Step"]     = true,
    ["Electric Claw"]  = true,
    ["Dark Step"]      = true,
    ["Combat"]         = true,
    ["Water Kung Fu"]  = true,
    ["Dragon Breath"]  = true,
    ["Sharkman Karate"] = true,
    ["Fishman Karate"] = true,
    ["Black Leg"]      = true,
}

local FRUITS = {
    -- Mythical
    ["Leopard Fruit"] = true, ["Dragon Fruit"] = true,
    -- Legendary
    ["Dough Fruit"] = true, ["Soul Fruit"] = true,
    ["Venom Fruit"] = true, ["Control Fruit"] = true,
    ["Spirit Fruit"] = true, ["Mammoth Fruit"] = true,
    ["T-Rex Fruit"] = true, ["Kitsune Fruit"] = true,
    -- Rare
    ["Quake Fruit"] = true, ["Blizzard Fruit"] = true,
    ["Gravity Fruit"] = true, ["Portal Fruit"] = true,
    ["Phoenix Fruit"] = true, ["Rumble Fruit"] = true,
    ["Pain Fruit"] = true, ["Magma Fruit"] = true,
    -- Common (thêm nếu cần)
    ["Flame Fruit"] = true, ["Ice Fruit"] = true,
    ["Smoke Fruit"] = true, ["Shadow Fruit"] = true,
    ["Light Fruit"] = true, ["Dark Fruit"] = true,
}

-- Đọc tool đang hold trên tay character
local function GetHeldTool()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Tool")
end

-- Đọc tất cả tool trong Backpack + tay
local function GetAllTools()
    local tools = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
    end
    local heldTool = GetHeldTool()
    if heldTool then
        table.insert(tools, heldTool)
    end
    return tools
end

local function GetCurrentFruit()
    -- Ưu tiên tool đang cầm
    local held = GetHeldTool()
    if held then
        local name = held.Name
        if FRUITS[name] then return name end
        if string.find(name, "Fruit") then return name end
    end

    -- Tìm trong backpack
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if FRUITS[item.Name] or string.find(item.Name, "Fruit") then
                return item.Name
            end
        end
    end

    return "None"
end

local function GetWeapons()
    local sword = "None"
    local gun   = "None"
    local melee = "None"

    for _, tool in pairs(GetAllTools()) do
        local name = tool.Name
        if SWORDS[name] and sword == "None" then
            sword = name
        elseif GUNS[name] and gun == "None" then
            gun = name
        elseif MELEES[name] and melee == "None" then
            melee = name
        end
    end

    return sword, gun, melee
end

-- ═══════════════════════════════════════════════════════════════
-- INVENTORY READERS
-- ═══════════════════════════════════════════════════════════════

local ACCESSORY_KEYWORDS = {
    "Helm", "Cape", "Scarf", "Hat", "Coat",
    "Helmet", "Cloak", "Mask", "Bandana",
    "Crown", "Glasses", "Horns", "Wings",
    "Coat", "Jacket", "Armor",
}

local function IsAccessory(name)
    for _, kw in ipairs(ACCESSORY_KEYWORDS) do
        if string.find(name, kw, 1, true) then
            return true
        end
    end
    return false
end

local function GetInventory()
    local items = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            table.insert(items, item.Name)
        end
    end
    return items
end

local function GetAccessories()
    local acc = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if IsAccessory(item.Name) then
                table.insert(acc, item.Name)
            end
        end
    end
    return acc
end

local function GetMaterials()
    local mats = {}
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            local name = item.Name
            mats[name] = (mats[name] or 0) + 1
        end
    end
    return mats
end

-- ═══════════════════════════════════════════════════════════════
-- PAYLOAD BUILDER
-- ═══════════════════════════════════════════════════════════════

local function BuildPayload(statusStr)
    local sword, gun, melee = GetWeapons()

    return {
        api_key      = CONFIG.API_KEY,
        username     = LocalPlayer.Name,
        user_id      = LocalPlayer.UserId,
        level        = GetLevel(),
        beli         = GetBeli(),
        fragments    = GetFragments(),
        race         = GetRace(),
        sea          = GetSea(),
        fruit        = GetCurrentFruit(),
        sword        = sword,
        gun          = gun,
        melee        = melee,
        inventory    = GetInventory(),
        accessories  = GetAccessories(),
        materials    = GetMaterials(),
        status       = statusStr or "online",
        timestamp    = os.time(),
    }
end

-- ═══════════════════════════════════════════════════════════════
-- SENDER CORE
-- ═══════════════════════════════════════════════════════════════

local Sender = {
    Running = false,
}

-- ─────────────────────────────────────────────────────────────
-- Gửi đến 1 endpoint cụ thể, có retry riêng
-- ─────────────────────────────────────────────────────────────
local function SendToEndpoint(endpoint, encoded, retryCount)
    retryCount = retryCount or 0

    local ok, response = pcall(function()
        local s, r = HttpPost(endpoint.url, encoded)
        return s
    end)

    if ok and response then
        log("[" .. endpoint.name .. "] OK")
    else
        if retryCount < CONFIG.RETRY_LIMIT then
            warn_log("[" .. endpoint.name .. "] Failed — retry " .. (retryCount + 1)
                     .. "/" .. CONFIG.RETRY_LIMIT)
            task.wait(CONFIG.RETRY_DELAY)
            SendToEndpoint(endpoint, encoded, retryCount + 1)
        else
            warn_log("[" .. endpoint.name .. "] Max retry reached, skip")
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Encode payload và gửi song song đến TẤT CẢ endpoints
-- ─────────────────────────────────────────────────────────────
function Sender:SendAll(statusStr)
    local payload = BuildPayload(statusStr)

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(payload)
    end)

    if not ok then
        warn_log("JSONEncode failed: " .. tostring(encoded))
        return
    end

    log(">> Sending to " .. #CONFIG.ENDPOINTS .. " endpoints (lv "
        .. payload.level .. ")")

    -- Gửi song song: mỗi endpoint chạy trong task riêng
    for _, endpoint in ipairs(CONFIG.ENDPOINTS) do
        local ep = endpoint  -- capture cho closure
        task.spawn(function()
            SendToEndpoint(ep, encoded, 0)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- HEARTBEAT LOOP
-- ═══════════════════════════════════════════════════════════════

function Sender:Start()
    if self.Running then return end
    self.Running = true

    log("==========================================")
    log("  Blox Fruits Account Sender START")
    log("  User: " .. LocalPlayer.Name)
    log("  Endpoints: " .. #CONFIG.ENDPOINTS)
    for i, ep in ipairs(CONFIG.ENDPOINTS) do
        log("    [" .. i .. "] " .. ep.name .. " - " .. ep.url)
    end
    log("  Interval: " .. CONFIG.UPDATE_INTERVAL .. "s")
    log("==========================================")

    -- Gửi lần đầu ngay lập tức
    task.spawn(function()
        task.wait(1) -- Chờ game load
        self:SendAll("online")
    end)

    -- Heartbeat loop — gửi đến tất cả endpoints mỗi interval
    task.spawn(function()
        while self.Running do
            task.wait(CONFIG.UPDATE_INTERVAL)
            self:SendAll("online")
        end
    end)

    -- Gửi offline signal đến TẤT CẢ endpoints khi player leave
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            self.Running = false
            pcall(function()
                local payload = BuildPayload("offline")
                local encoded = HttpService:JSONEncode(payload)
                for _, ep in ipairs(CONFIG.ENDPOINTS) do
                    local endpoint = ep
                    task.spawn(function()
                        HttpPost(endpoint.url, encoded)
                        log("[" .. endpoint.name .. "] Offline signal sent")
                    end)
                end
            end)
        end
    end)
end

function Sender:Stop()
    self.Running = false
    log("Sender stopped")
end

-- ═══════════════════════════════════════════════════════════════
-- START
-- ═══════════════════════════════════════════════════════════════

Sender:Start()
