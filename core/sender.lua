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
    API_KEY         = _G.BF_API_KEY or "___REPLACE_ME___",   -- Nhận key từ server hoặc fallback
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
            url  = "https://tr-tt-5.onrender.com/data",
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
        -- Tool.ToolTip trên Roblox của Blox Fruits chứa loại vũ khí ("Sword", "Gun", "Melee")
        local toolTip = ""
        pcall(function()
            toolTip = tool.ToolTip or ""
        end)

        if (SWORDS[name] or toolTip == "Sword") and sword == "None" then
            sword = name
        elseif (GUNS[name] or toolTip == "Gun") and gun == "None" then
            gun = name
        elseif (MELEES[name] or toolTip == "Melee") and melee == "None" then
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

-- ─────────────────────────────────────────────────────────────
-- SERVER INVENTORY READER (Blox Fruits Remote)
-- ─────────────────────────────────────────────────────────────

local function GetServerInventory()
    local remotes = SafeFind({"ReplicatedStorage", "Remotes", "CommF"})
    if remotes and remotes:IsA("RemoteFunction") then
        local success, result = pcall(function()
            return remotes:InvokeServer("getInventory")
        end)
        if success and type(result) == "table" then
            return result
        end
    end
    return nil
end

local function GetInventory()
    local items = {}
    local rawInv = GetServerInventory()

    if rawInv then
        for _, item in ipairs(rawInv) do
            if type(item) == "table" and item.Name then
                table.insert(items, item.Name)
            end
        end
    else
        -- Fallback: Đọc từ Backpack
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, item in pairs(backpack:GetChildren()) do
                table.insert(items, item.Name)
            end
        end
    end
    return items
end

local function GetAccessories()
    local acc = {}
    local rawInv = GetServerInventory()

    if rawInv then
        for _, item in ipairs(rawInv) do
            if type(item) == "table" and item.Name then
                local t = item.Type
                if t == "Accessory" or t == "Wear" or IsAccessory(item.Name) then
                    table.insert(acc, item.Name)
                end
            end
        end
    else
        -- Fallback: Đọc từ Backpack
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, item in pairs(backpack:GetChildren()) do
                if IsAccessory(item.Name) then
                    table.insert(acc, item.Name)
                end
            end
        end
    end
    return acc
end

local function GetMaterials()
    local mats = {}
    local rawInv = GetServerInventory()

    if rawInv then
        for _, item in ipairs(rawInv) do
            if type(item) == "table" and item.Name then
                local t = item.Type
                if t == "Material" or string.find(t or "", "Material") then
                    mats[item.Name] = item.Count or item.Value or 1
                end
            end
        end
    else
        -- Fallback: Đếm từ Backpack
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if backpack then
            for _, item in pairs(backpack:GetChildren()) do
                mats[item.Name] = (mats[item.Name] or 0) + 1
            end
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

    -- Cập nhật thông số lên GUI trước khi gửi
    if Sender.UpdateUI then
        Sender:UpdateUI(payload)
    end

    -- Gửi song song: mỗi endpoint chạy trong task riêng
    for _, endpoint in ipairs(CONFIG.ENDPOINTS) do
        local ep = endpoint  -- capture cho closure
        task.spawn(function()
            SendToEndpoint(ep, encoded, 0)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- IN-GAME GUI (Góc trái màn hình)
-- ═══════════════════════════════════════════════════════════════

local ScreenGui = nil
local MainFrame = nil
local StatusLabel = nil
local LevelLabel = nil
local MoneyLabel = nil
local FruitLabel = nil
local ToggleBtn = nil

function Sender:CreateGUI()
    -- Tránh tạo trùng lặp
    local targetParent = nil
    local success, _ = pcall(function()
        targetParent = game:GetService("CoreGui")
    end)
    if not success or not targetParent then
        targetParent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local existing = targetParent:FindFirstChild("BF_AccountManagerUI")
    if existing then existing:Destroy() end

    -- ScreenGui
    ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "BF_AccountManagerUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = targetParent

    -- Nút Toggle (Thu nhỏ / Mở rộng) ở góc trái
    ToggleBtn = Instance.new("TextButton")
    ToggleBtn.Name = "ToggleButton"
    ToggleBtn.Size = UDim2.new(0, 40, 0, 40)
    ToggleBtn.Position = UDim2.new(0, 10, 0, 120) -- Đặt dưới menu mặc định của Roblox
    ToggleBtn.BackgroundColor3 = Color3.fromRGB(22, 24, 33)
    ToggleBtn.BorderSizePixel = 1
    ToggleBtn.BorderColor3 = Color3.fromRGB(59, 130, 246)
    ToggleBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
    ToggleBtn.Font = Enum.Font.SourceSansBold
    ToggleBtn.TextSize = 18
    ToggleBtn.Text = "🏴‍☠️"
    ToggleBtn.Parent = ScreenGui

    -- Bo góc nút toggle
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 8)
    toggleCorner.Parent = ToggleBtn

    -- Main Panel
    MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 220, 0, 210)
    MainFrame.Position = UDim2.new(0, 60, 0, 120)
    MainFrame.BackgroundColor3 = Color3.fromRGB(22, 24, 33)
    MainFrame.BorderSizePixel = 1
    MainFrame.BorderColor3 = Color3.fromRGB(59, 130, 246)
    MainFrame.Visible = true
    MainFrame.Parent = ScreenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 10)
    frameCorner.Parent = MainFrame

    -- Header Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
    title.TextColor3 = Color3.fromRGB(59, 130, 246)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 14
    title.Text = "  BLOX FRUITS MANAGER"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = MainFrame

    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 10)
    titleCorner.Parent = title

    -- Status Label
    StatusLabel = Instance.new("TextLabel")
    StatusLabel.Size = UDim2.new(1, -20, 0, 25)
    StatusLabel.Position = UDim2.new(0, 10, 0, 40)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.TextColor3 = Color3.fromRGB(16, 185, 129)
    StatusLabel.Font = Enum.Font.SourceSansBold
    StatusLabel.TextSize = 13
    StatusLabel.Text = "Status: Active"
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = MainFrame

    -- Level Label
    LevelLabel = Instance.new("TextLabel")
    LevelLabel.Size = UDim2.new(1, -20, 0, 25)
    LevelLabel.Position = UDim2.new(0, 10, 0, 65)
    LevelLabel.BackgroundTransparency = 1
    LevelLabel.TextColor3 = Color3.fromRGB(241, 245, 249)
    LevelLabel.Font = Enum.Font.SourceSans
    LevelLabel.TextSize = 13
    LevelLabel.Text = "Level: --"
    LevelLabel.TextXAlignment = Enum.TextXAlignment.Left
    LevelLabel.Parent = MainFrame

    -- Money Label
    MoneyLabel = Instance.new("TextLabel")
    MoneyLabel.Size = UDim2.new(1, -20, 0, 25)
    MoneyLabel.Position = UDim2.new(0, 10, 0, 90)
    MoneyLabel.BackgroundTransparency = 1
    MoneyLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
    MoneyLabel.Font = Enum.Font.SourceSans
    MoneyLabel.TextSize = 13
    MoneyLabel.Text = "Beli: -- | Frag: --"
    MoneyLabel.TextXAlignment = Enum.TextXAlignment.Left
    MoneyLabel.Parent = MainFrame

    -- Fruit Label
    FruitLabel = Instance.new("TextLabel")
    FruitLabel.Size = UDim2.new(1, -20, 0, 25)
    FruitLabel.Position = UDim2.new(0, 10, 0, 115)
    FruitLabel.BackgroundTransparency = 1
    FruitLabel.TextColor3 = Color3.fromRGB(139, 92, 246)
    FruitLabel.Font = Enum.Font.SourceSans
    FruitLabel.TextSize = 13
    FruitLabel.Text = "Fruit: --"
    FruitLabel.TextXAlignment = Enum.TextXAlignment.Left
    FruitLabel.Parent = MainFrame

    -- Force Send Button
    local sendBtn = Instance.new("TextButton")
    sendBtn.Size = UDim2.new(0, 95, 0, 30)
    sendBtn.Position = UDim2.new(0, 10, 0, 150)
    sendBtn.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
    sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    sendBtn.Font = Enum.Font.SourceSansBold
    sendBtn.TextSize = 12
    sendBtn.Text = "Force Send"
    sendBtn.Parent = MainFrame

    local sendCorner = Instance.new("UICorner")
    sendCorner.CornerRadius = UDim.new(0, 5)
    sendCorner.Parent = sendBtn

    -- Auto Send Toggle Button
    local autoBtn = Instance.new("TextButton")
    autoBtn.Size = UDim2.new(0, 95, 0, 30)
    autoBtn.Position = UDim2.new(0, 115, 0, 150)
    autoBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    autoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoBtn.Font = Enum.Font.SourceSansBold
    autoBtn.TextSize = 12
    autoBtn.Text = "Auto: ON"
    autoBtn.Parent = MainFrame

    local autoCorner = Instance.new("UICorner")
    autoCorner.CornerRadius = UDim.new(0, 5)
    autoCorner.Parent = autoBtn

    -- ─── UI INTERACTIONS ───

    -- Toggle ẩn/hiện bảng menu
    ToggleBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = not MainFrame.Visible
        ToggleBtn.Text = MainFrame.Visible and "🏴‍☠️" or "☰"
    end)

    -- Force Send
    sendBtn.MouseButton1Click:Connect(function()
        sendBtn.Text = "Sending..."
        sendBtn.Active = false
        task.spawn(function()
            Sender:SendAll("online")
            task.wait(0.5)
            sendBtn.Text = "Force Send"
            sendBtn.Active = true
        end)
    end)

    -- Toggle Auto Send
    autoBtn.MouseButton1Click:Connect(function()
        if Sender.Running then
            Sender:Stop()
            autoBtn.Text = "Auto: OFF"
            autoBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
            StatusLabel.Text = "Status: Disabled"
            StatusLabel.TextColor3 = Color3.fromRGB(239, 68, 68)
        else
            Sender:Start()
            autoBtn.Text = "Auto: ON"
            autoBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
            StatusLabel.Text = "Status: Active"
            StatusLabel.TextColor3 = Color3.fromRGB(16, 185, 129)
        end
    end)
end

function Sender:UpdateUI(payload)
    if not MainFrame then return end
    pcall(function()
        LevelLabel.Text = "Level: " .. tostring(payload.level)
        MoneyLabel.Text = "Beli: " .. tostring(payload.beli) .. " | Frag: " .. tostring(payload.fragments)
        FruitLabel.Text = "Fruit: " .. tostring(payload.fruit)
    end)
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

    -- Tạo GUI nếu chưa có
    if not ScreenGui then
        self:CreateGUI()
    end

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

