
-- ====================================================================
--        AUTO FISH V5.5 - FIX WEBHOOK + SLIDER + AUTO CATCH
-- ====================================================================

-- 1. SISTEM KONTROL
getgenv().VinzHubRunning = true
local ScriptConnections = {} 

-- 2. NOTIFIKASI LAYAR HP
local function Notify(title, text, duration)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = title or "VinzHub",
            Text = text or "Notification",
            Duration = duration or 3
        })
    end)
end

Notify("VinzHub V5.6", "Memuat Script...", 2)

-- 3. CEK HTTP REQUEST
local requestFunc = http_request or request or HttpPost or syn.request
if not requestFunc then
    Notify("⚠️ Warning", "Executor HP ini tdk support Webhook!", 5)
end

-- ====================================================================
--                        LAYANAN (SERVICES)
-- ====================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- ====================================================================
--                        KONFIGURASI
-- ====================================================================
local CONFIG_FOLDER = "VinzHubMobile_Final"
local CONFIG_FILE = CONFIG_FOLDER .. "/config_v5.json"

local Config = {
    AutoFish = false,
    AutoSell = false,
    AutoCatch = false, -- Fitur Baru
    GPUSaver = false,
    BlatantMode = false,
    FishDelay = 0.9,   -- Default delay (detik)
    CatchDelay = 0.3,  -- Default delay catch
    TeleportLocation = "Sisyphus Statue",
    AutoFavorite = true,
    FavoriteRarity = "Mythic",
    WebhookURL = ""
}

local function ensureFolder()
    if not isfolder or not makefolder then return false end
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
    return true
end

local function saveConfig()
    if not writefile or not ensureFolder() then return end
    pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end)
end

local function loadConfig()
    if not readfile or not isfile or not isfile(CONFIG_FILE) then return end
    pcall(function()
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        for k, v in pairs(data) do Config[k] = v end
    end)
end

loadConfig()

-- ====================================================================
--                        LOKASI TELEPORT
-- ====================================================================
local LOCATIONS = {
    ["Spawn"] = CFrame.new(45.278, 252.563, 2987.109),
    ["Sisyphus Statue"] = CFrame.new(-3728.216, -135.074, -1012.127),
    ["Coral Reefs"] = CFrame.new(-3114.782, 1.320, 2237.523),
    ["Esoteric Depths"] = CFrame.new(3248.371, -1301.530, 1403.827),
    ["Crater Island"] = CFrame.new(1016.491, 20.092, 5069.273),
    ["Lost Isle"] = CFrame.new(-3618.157, 240.837, -1317.458),
    ["Weather Machine"] = CFrame.new(-1488.512, 83.173, 1876.303),
    ["Tropical Grove"] = CFrame.new(-2095.341, 197.200, 3718.080),
    ["Mount Hallow"] = CFrame.new(2136.623, 78.916, 3272.504),
    ["Treasure Room"] = CFrame.new(-3606.350, -266.574, -1580.973),
    ["Kohana"] = CFrame.new(-663.904, 3.046, 718.797),
    ["Underground Cellar"] = CFrame.new(2109.521, -94.188, -708.609),
    ["Ancient Jungle"] = CFrame.new(1831.714, 6.625, -299.279),
    ["Sacred Temple"] = CFrame.new(1466.922, -21.875, -622.836)
}

-- ====================================================================
--                        REMOTE EVENTS
-- ====================================================================
local Events = {}
local success_remote = pcall(function()
    local net = ReplicatedStorage.Packages._Index["sleitnick_net@0.2.0"].net
    Events.fishing = net:WaitForChild("RE/FishingCompleted", 10)
    Events.sell = net:WaitForChild("RF/SellAllItems", 10)
    Events.charge = net:WaitForChild("RF/ChargeFishingRod", 10)
    Events.minigame = net:WaitForChild("RF/RequestFishingMinigameStarted", 10)
    Events.equip = net:WaitForChild("RE/EquipToolFromHotbar", 10)
    Events.unequip = net:WaitForChild("RE/UnequipToolFromHotbar", 10)
    Events.favorite = net:WaitForChild("RE/FavoriteItem", 10)
end)

if not success_remote or not Events.fishing then
    Notify("❌ ERROR", "Gagal load remote. Rejoin!", 10)
    return
end

-- ====================================================================
--                        MODULES
-- ====================================================================
local ItemUtility = require(ReplicatedStorage.Shared.ItemUtility)
local Replion = require(ReplicatedStorage.Packages.Replion)
local PlayerData = Replion.Client:WaitReplion("Data")

local RarityTiers = {Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Secret = 7}
local RarityColors = {
    Common = 10066329, Uncommon = 3066993, Rare = 1752220, 
    Epic = 10181046, Legendary = 16776960, Mythic = 15158332, Secret = 10027263
}

local function getRarityValue(rarity) return RarityTiers[rarity] or 0 end
local function getFishRarity(itemData)
    if not itemData or not itemData.Data then return "Common" end
    return itemData.Data.Rarity or "Common"
end

-- ====================================================================
--                  WEBHOOK SENDER (DIPERBAIKI)
-- ====================================================================
local function SendWebhook(fishName, rarity, weight, price)
    if Config.WebhookURL == "" or not string.find(Config.WebhookURL, "http") then return end
    if not requestFunc then return end
    if not getgenv().VinzHubRunning then return end

    local color = RarityColors[rarity] or 16777215
    local currentCoins = 0
    pcall(function() currentCoins = PlayerData:GetExpect("Currencies").Coins end)
    
    local embedData = {
        ["title"] = "🎣 Ikan Baru Tertangkap!",
        ["color"] = color,
        ["thumbnail"] = { ["url"] = "https://i.imgur.com/8QZ7r9a.png" },
        ["fields"] = {
            { ["name"] = "Player", ["value"] = LocalPlayer.DisplayName .. " (@"..LocalPlayer.Name..")", ["inline"] = false },
            { ["name"] = "Ikan", ["value"] = "**"..tostring(fishName).."**", ["inline"] = false },
            { ["name"] = "Detail", ["value"] = rarity .. " | " .. tostring(weight) .. "kg", ["inline"] = true },
            { ["name"] = "Harga", ["value"] = tostring(price) .. " Coins", ["inline"] = true }
        },
        ["footer"] = {
            ["text"] = "VinzHub V5.6 | Coins: " .. string.format("%d", currentCoins) .. " | " .. os.date("%X")
        }
    }

    local payload = HttpService:JSONEncode({ ["content"] = "", ["embeds"] = {embedData} })
    pcall(function()
        requestFunc({Url = Config.WebhookURL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = payload})
    end)
end

-- ====================================================================
--                        TELEPORT
-- ====================================================================
local Teleport = {}
function Teleport.to(locationName)
    local cframe = LOCATIONS[locationName]
    if not cframe then return end
    pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = cframe end)
    Notify("Teleport", "Ke " .. locationName, 2)
end

-- ====================================================================
--                        LOGIKA FISHING
-- ====================================================================
local isFishing = false
local fishingActive = false

local function castRod()
    pcall(function()
        Events.equip:FireServer(1)
        task.wait(0.05)
        Events.charge:InvokeServer(1763950945.397729)
        task.wait(0.02)
        Events.minigame:InvokeServer(-0.5718746185302734, 0.9378207075323894, 1763950947.629105)
    end)
end

local function fishingLoop()
    while fishingActive and getgenv().VinzHubRunning do
        if not isFishing then
            isFishing = true
            
            if Config.BlatantMode then
                -- MODE CEPAT (Blatant)
                pcall(function()
                    Events.equip:FireServer(1)
                    task.wait(0.01)
                    task.spawn(function()
                         Events.charge:InvokeServer(1); task.wait(0.01)
                         Events.minigame:InvokeServer(1, 1)
                    end)
                end)
                task.wait(Config.FishDelay) -- Delay Slider
                for i=1, 3 do pcall(function() Events.fishing:FireServer() end) end
            else
                -- MODE NORMAL
                castRod()
                task.wait(Config.FishDelay) -- Delay Slider
                pcall(function() Events.fishing:FireServer() end)
            end
            
            task.wait(Config.CatchDelay) -- Delay Slider
            isFishing = false
        else
            task.wait(0.1)
        end
    end
end

-- AUTO CATCH LOOP (BARU: Terpisah agar lebih responsif)
task.spawn(function()
    while getgenv().VinzHubRunning do
        if Config.AutoCatch and not isFishing then
            pcall(function() Events.fishing:FireServer() end)
        end
        task.wait(0.2) -- Cek setiap 0.2 detik
    end
end)

-- Auto Sell
task.spawn(function()
    while getgenv().VinzHubRunning do
        task.wait(Config.SellDelay)
        if Config.AutoSell then pcall(function() Events.sell:InvokeServer() end) end
    end
end)

-- Auto Favorite
task.spawn(function()
    while getgenv().VinzHubRunning do
        task.wait(5)
        if Config.AutoFavorite then
            pcall(function()
                local items = PlayerData:GetExpect("Inventory").Items
                local targetVal = getRarityValue(Config.FavoriteRarity)
                if targetVal < 6 then targetVal = 6 end 
                for _, item in ipairs(items) do
                    local data = ItemUtility:GetItemData(item.Id)
                    if data and data.Data then
                        local rVal = getRarityValue(getFishRarity(data))
                        if rVal >= targetVal and not item.Favorited then
                            Events.favorite:FireServer(item.UUID)
                            task.wait(0.3)
                        end
                    end
                end
            end)
        end
    end
end)

-- Anti AFK
local afkConn = LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)
table.insert(ScriptConnections, afkConn)

-- ====================================================================
--                        UI LIBRARY
-- ====================================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "🎣 VinzHub V5.6",
    LoadingTitle = "Mobile Slider & Fix",
    ConfigurationSaving = { Enabled = false }
})

local MainTab = Window:CreateTab("🏠 Utama", 4483362458)
local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

-- === MAIN TAB ===
MainTab:CreateToggle({
    Name = "🤖 Auto Fish (Utama)",
    CurrentValue = Config.AutoFish,
    Callback = function(v)
        Config.AutoFish = v
        fishingActive = v
        if v then task.spawn(fishingLoop); Notify("ON", "Mulai Mancing...", 2)
        else 
            pcall(function() Events.unequip:FireServer() end)
            isFishing = false
            Notify("OFF", "Stop...", 2)
        end
        saveConfig()
    end
})

MainTab:CreateToggle({
    Name = "🎯 Auto Catch (Bantuan Tangkap)",
    CurrentValue = Config.AutoCatch,
    Callback = function(v) Config.AutoCatch = v; saveConfig() end
})

MainTab:CreateToggle({
    Name = "⚡ Blatant Mode (Brutal)", CurrentValue = Config.BlatantMode,
    Callback = function(v) Config.BlatantMode = v; saveConfig() end
})

-- SLIDERS (PENGATUR DELAY)
MainTab:CreateSection("Pengaturan Waktu (Slider)")

MainTab:CreateSlider({
    Name = "Tunggu Ikan (Detik)",
    Range = {0.1, 5.0}, -- Min 0.1, Max 5.0
    Increment = 0.1,
    Suffix = "Detik",
    CurrentValue = Config.FishDelay,
    Flag = "FishDelaySlider", 
    Callback = function(Value)
        Config.FishDelay = Value
        saveConfig()
    end
})

MainTab:CreateSlider({
    Name = "Jeda Setelah Tangkap",
    Range = {0.1, 2.0},
    Increment = 0.1,
    Suffix = "Detik",
    CurrentValue = Config.CatchDelay,
    Flag = "CatchDelaySlider",
    Callback = function(Value)
        Config.CatchDelay = Value
        saveConfig()
    end
})

-- WEBHOOK SECTION
MainTab:CreateSection("Webhook Discord")
MainTab:CreateInput({
    Name = "URL Webhook", PlaceholderText = "Tempel Link disini...", CurrentValue = Config.WebhookURL,
    Callback = function(t) Config.WebhookURL = t; saveConfig(); Notify("Saved", "Webhook tersimpan", 2) end
})

MainTab:CreateButton({
    Name = "Test Webhook",
    Callback = function()
        if Config.WebhookURL == "" then
            Notify("Gagal", "URL Kosong!", 2)
        else
            Notify("Mengirim...", "Cek Discord kamu!", 2)
            SendWebhook("Test Ikan", "Mythic", 99.9, 10000)
        end
    end
})

-- === SETTINGS TAB ===
SettingsTab:CreateSection("Fitur Lain")
SettingsTab:CreateToggle({
    Name = "💰 Auto Sell", CurrentValue = Config.AutoSell,
    Callback = function(v) Config.AutoSell = v; saveConfig() end
})
SettingsTab:CreateToggle({
    Name = "⭐ Auto Favorite", CurrentValue = Config.AutoFavorite,
    Callback = function(v) Config.AutoFavorite = v; saveConfig() end
})
SettingsTab:CreateDropdown({
    Name = "Rarity Favorite", Options = {"Mythic", "Secret"}, CurrentOption = Config.FavoriteRarity,
    Callback = function(v) Config.FavoriteRarity = v; saveConfig() end
})

SettingsTab:CreateSection("System")
SettingsTab:CreateToggle({
    Name = "📱 GPU Saver (Layar Hitam)", CurrentValue = Config.GPUSaver,
    Callback = function(v) 
        Config.GPUSaver = v
        pcall(function() RunService:Set3dRenderingEnabled(not v) end)
    end
})

SettingsTab:CreateButton({
    Name = "🔴 Unload Script (Matikan)",
    Callback = function()
        getgenv().VinzHubRunning = false
        fishingActive = false
        Config.AutoFish = false
        Config.AutoCatch = false
        
        for _, conn in pairs(ScriptConnections) do
            if conn then conn:Disconnect() end
        end
        
        RunService:Set3dRenderingEnabled(true)
        Rayfield:Destroy()
        Notify("Unloaded", "Script dimatikan!", 3)
    end
})

-- ====================================================================
--     EVENT LISTENER WEBHOOK (LOGIKA BARU - FIX FORMAT)
-- ====================================================================
if Events.fishing then
    local hookConn = Events.fishing.OnClientEvent:Connect(function(...)
        if not getgenv().VinzHubRunning then return end
        local args = {...}
        
        -- DEBUG: Coba parsing data dengan dua cara
        pcall(function()
            local fishName = "Unknown"
            local fishRarity = "Common"
            local fishWeight = 0
            local fishPrice = 0
            
            -- CARA 1: Jika Data adalah Table (Modern Game)
            if args[1] and type(args[1]) == "table" then
                local d = args[1]
                fishName = d.Name or d.fishName or fishName
                fishRarity = d.Rarity or fishRarity
                fishWeight = tonumber(d.Weight) or 0
                fishPrice = d.Price or (fishWeight * 15)
                
            -- CARA 2: Jika Data Terpisah (Old/Simple Game)
            elseif args[1] and type(args[1]) == "string" then
                fishName = args[1]
                -- Coba tebak posisi argumen lain
                if args[2] and type(args[2]) == "number" then fishWeight = args[2] end
                if args[3] and type(args[3]) == "string" then fishRarity = args[3] end
                fishPrice = fishWeight * 15
            end
            
            -- Hanya kirim jika nama ikan valid
            if fishName ~= "Unknown" then
                SendWebhook(fishName, fishRarity, fishWeight, fishPrice)
                Notify("Dapat Ikan!", fishName, 2)
            end
        end)
    end)
    table.insert(ScriptConnections, hookConn)
end

Rayfield:Notify({Title = "VinzHub V5.6", Content = "Siap! Gunakan Slider untuk Delay.", Duration = 5})
