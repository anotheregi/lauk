-- =====================================================
-- FISH IT SECRET FISH NOTIFIER (DENGAN FILTER RARITY)
-- =====================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer

-- ================== KONFIGURASI ==================
local WebhookURL = ""  -- Akan diisi lewat GUI
local NotifierEnabled = true
local BotUsername = "Rayzer keren"
local BotAvatarUrl = "https://i.imgur.com/3PuhVRE.png"

-- ================== DATA IKAN & FILTER ==================
local FishData = {}          -- key: nama ikan, value: {tier = X, icon = "assetId"}
local SelectedFilter = "Secret"  -- default: Secret (tier 7)
-- Tier mapping (sesuaikan dengan game)
local TIER = {
    Legendary = 5,
    Mythic = 6,
    Secret = 7
}

-- ================== FUNGSI PEMINDAIAN DATA IKAN ==================
local function tableCount(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Fungsi ekstrak asset ID dari string icon
local function extractAssetId(iconString)
    if type(iconString) ~= "string" then return nil end
    return iconString:match("(%d+)")
end

local function scanFishData()
    local fishData = {}
    local itemsFolder = ReplicatedStorage:FindFirstChild("Items")
    if not itemsFolder then
        warn("[FishNotifier] Folder 'Items' tidak ditemukan.")
        return fishData
    end

    local function scanFolder(folder)
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("ModuleScript") then
                local success, module = pcall(require, child)
                if success and type(module) == "table" then
                    -- Pola 1: module memiliki field Data dengan Type = "Fish"
                    if module.Data and type(module.Data) == "table" and module.Data.Type == "Fish" then
                        local fishName = module.Data.Name
                        local tier = module.Data.Tier
                        local icon = module.Data.Icon
                        if fishName and tier then
                            fishData[string.lower(fishName)] = {
                                tier = tonumber(tier) or 0,
                                icon = extractAssetId(icon)
                            }
                            print("[FishNotifier] Found fish: " .. fishName .. " | Tier: " .. tier .. " | Icon: " .. tostring(icon))
                        end
                    -- Pola 2: module berisi tabel-tabel ikan (key bisa nama ikan)
                    else
                        for key, value in pairs(module) do
                            if type(value) == "table" then
                                -- Cek apakah value memiliki indikasi ikan
                                if value.Type == "Fish" or value.Name then
                                    local fishName = value.Name or key
                                    local tier = value.Tier or (value.Data and value.Data.Tier)
                                    local icon = value.Icon or (value.Data and value.Data.Icon)
                                    if fishName and tier then
                                        fishData[string.lower(fishName)] = {
                                            tier = tonumber(tier) or 0,
                                            icon = extractAssetId(icon)
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            elseif child:IsA("Folder") then
                scanFolder(child)
            end
        end
    end

    scanFolder(itemsFolder)
    return fishData
end

-- Inisialisasi data ikan
FishData = scanFishData()
print("[FishNotifier] Total data ikan: " .. tableCount(FishData))

-- ================== FUNGSI PARSING PESAN (REGEX DIPERBAIKI) ==================
local function parseFishMessage(msg)
    local username = msg:match("%]: ?([^%s]+) obtained")
    if not username then return nil end

    local fullFishText, weightStr = msg:match("%](.-) %(([%d%.]+)kg%)")
    if not fullFishText then return nil end

    local weight = tonumber(weightStr)

    local mutation, fishName = fullFishText:match("^(%u+)%s+(.+)")
    if not mutation then fishName = fullFishText end

    local rarityText = msg:match("with a (1 in [%d%.]+[KM]? chance!)")
    if not rarityText then return nil end

    return {
        username = username,
        fishName = fishName,
        weight = weight,
        rarityText = rarityText,
        mutation = mutation
    }
end

-- ================== FUNGSI PENGIRIMAN WEBHOOK ==================
local function sendDiscordWebhook(url, embedData, callback)
    local payload = {
        username = BotUsername,
        avatar_url = BotAvatarUrl,
        embeds = {embedData}
    }
    local json = HttpService:JSONEncode(payload)
    
    local success = false
    local resultMsg = ""
    
    -- Metode 1: HttpService:PostAsync
    local ok, err = pcall(function()
        HttpService:PostAsync(url, json, Enum.HttpContentType.ApplicationJson)
    end)
    if ok then
        success = true
        resultMsg = "Webhook terkirim (HttpService)"
    else
        -- Metode 2: syn.request
        if syn and syn.request then
            ok, err = pcall(function()
                syn.request({
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = json
                })
            end)
            if ok then
                success = true
                resultMsg = "Webhook terkirim (syn.request)"
            end
        end
        
        -- Metode 3: request
        if not success and request then
            ok, err = pcall(function()
                request({
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = json
                })
            end)
            if ok then
                success = true
                resultMsg = "Webhook terkirim (request)"
            end
        end
        
        -- Metode 4: http.request
        if not success and http and http.request then
            ok, err = pcall(function()
                http.request({
                    Url = url,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = json
                })
            end)
            if ok then
                success = true
                resultMsg = "Webhook terkirim (http.request)"
            end
        end
    end
    
    if callback then
        callback(success, success and resultMsg or ("Gagal: " .. tostring(err)))
    end
end
--==================================
-- ================== ICON SYSTEM (SECRET ONLY + CACHE + FALLBACK) ==================
local DEFAULT_THUMBNAIL = "https://i.imgur.com/3PuhVRE.png"
local IconCache = {}

local function fetchThumbnailURL(assetId)
    if not assetId then return nil end

    local requestFunc = syn and syn.request or request or http_request
    if not requestFunc then return nil end

    local url = "https://thumbnails.roblox.com/v1/assets?assetIds="
        .. assetId
        .. "&size=420x420&format=Png&isCircular=false"

    local response = requestFunc({
        Url = url,
        Method = "GET"
    })

    if not response or not response.Body then
        return nil
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(response.Body)
    end)

    if not ok or not decoded then
        return nil
    end

    if decoded.data and #decoded.data > 0 then
        return decoded.data[1].imageUrl
    end

    return nil
end

local function getFishIconURL(fishName)
    local key = string.lower(fishName)

    if IconCache[key] then
        return IconCache[key]
    end

    local info = FishData[key]
    if not info or not info.icon then
        IconCache[key] = DEFAULT_THUMBNAIL
        return DEFAULT_THUMBNAIL
    end

    local cdnUrl = fetchThumbnailURL(info.icon)
    if cdnUrl then
        IconCache[key] = cdnUrl
        return cdnUrl
    end

    IconCache[key] = DEFAULT_THUMBNAIL
    return DEFAULT_THUMBNAIL
end

-- ================== SEND NOTIF ==================
local function sendNotification(data)
    if WebhookURL == "" or not NotifierEnabled then return end

    local iconUrl = getFishIconURL(data.fishName)

    local embed = {
        title = "**🎣 " .. SelectedFilter:upper() .. " FISH CAUGHT! 🎣**",
        description = "Notification by **Rayzerpedia**",
        color = 0x76ff7a,

        thumbnail = {
            url = iconUrl
        },

        fields = {
            {name = "Username", value = "`@"..data.username.."`", inline = true},
            {name = "Fish Name", value = "`"..data.fishName.."`", inline = true},
            {name = "Mutation", value = "`"..(data.mutation or "-").."`", inline = true},
            {name = "Weight", value = "`"..data.weight.." kg`", inline = true},
            {name = "Rarity", value = "`"..data.rarityText.."`", inline = true}
        },

        footer = {
            text = "dsc.gg/rayzerpedia  •  " .. os.date("%d-%m-%Y")
        }
    }

    sendDiscordWebhook(WebhookURL, embed)
end



-- ================== CARI REMOTE EVENT ==================
local function findRemoteEvent(name)
    -- path standar
    local folder = ReplicatedStorage:FindFirstChild("Packages") and
                   ReplicatedStorage.Packages:FindFirstChild("_Index") and
                   ReplicatedStorage.Packages._Index:FindFirstChild("sleitnick_net@0.2.0")
    if folder then
        local remote = folder:FindFirstChild("RE/" .. name)
        if remote then return remote end
    end
    -- Fallback: cari di seluruh ReplicatedStorage
    for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and v.Name == name then
            return v
        end
    end
    return nil
end

-- ================== PASANG LISTENER ==================
local function setupListener()
    for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
        if remote:IsA("RemoteEvent") then
            remote.OnClientEvent:Connect(function(...)
                local args = {...}
                
                for _, arg in ipairs(args) do
                    if type(arg) == "string" and string.find(arg, "obtained a") then
                        local parsed = parseFishMessage(arg)
                        
                        if parsed then
                            -- Debug: print all parsed data
                            print("[Debug] Parsed fish:", parsed.fishName)
                            
                            -- Fix: Look up fish in FishData with exact or partial match
                            local tier = nil
                            local matchedFishName = nil
                            
                            -- Try exact match first
                            if FishData[parsed.fishName] then
                                tier = FishData[parsed.fishName].tier
                                matchedFishName = parsed.fishName
                            else
                                -- Try partial match (fish name contains the key)
                                for fishKey, fishInfo in pairs(FishData) do
                                    if string.find(parsed.fishName, fishKey) or string.find(fishKey, parsed.fishName) then
                                        tier = fishInfo.tier
                                        matchedFishName = fishKey
                                        break
                                    end
                                end
                            end
                            
                            print("[Debug] Matched fish:", matchedFishName, "Tier:", tier)
                            
                            local requiredTier = TIER[SelectedFilter]
                            
                            -- Send notification if tier matches or if fish not found in database (fallback)
                            if tier and tier == requiredTier then
                                print("[✓] Kirim notifikasi:", parsed.fishName)
                                sendNotification(parsed)
                            elseif not matchedFishName then
                                -- Fish not found in database, send notification anyway as fallback
                             --   print("[✓] Kirim notifikasi (fallback):", parsed.fishName)
                            --    sendNotification(parsed)
                            end
                                print("[x] Tier tidak cocok. Ditangkap:", tier, "Dibutuhkan:", requiredTier)
                            end
                        end
                    end
                end
            end)
        end
    end

    print("[✓] Listener universal terpasang (Fish It mode)")
end

-- ================== GUI DENGAN FILTER ==================
local function createGUI()
    -- Hapus GUI lama jika ada
    local existing = Player.PlayerGui:FindFirstChild("FishNotifierGUI")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "FishNotifierGUI"
    screenGui.Parent = Player.PlayerGui

    -- Toggle button (⚙️)
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(0, 40, 0, 40)
    toggleButton.Position = UDim2.new(1, -50, 0, 10)
    toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    toggleButton.Text = "⚙️"
    toggleButton.TextSize = 20
    toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleButton.Visible = true  -- Changed from false to true so users can access settings
    toggleButton.Parent = screenGui

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 8)
    toggleCorner.Parent = toggleButton

    -- UI Utama
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 420, 0, 350)  -- Lebih besar untuk filter
    frame.Position = UDim2.new(0.5, -210, 0.5, -175)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Visible = true
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    title.Text = "Fish It Notifier Settings"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 18
    title.Font = Enum.Font.GothamBold
    title.Parent = frame

    -- Close button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 5)
    closeBtn.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Parent = frame

    local cornerClose = Instance.new("UICorner")
    cornerClose.CornerRadius = UDim.new(0, 5)
    cornerClose.Parent = closeBtn

    -- Webhook URL
    local urlLabel = Instance.new("TextLabel")
    urlLabel.Size = UDim2.new(1, -20, 0, 30)
    urlLabel.Position = UDim2.new(0, 10, 0, 50)
    urlLabel.BackgroundTransparency = 1
    urlLabel.Text = "Webhook URL:"
    urlLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    urlLabel.TextXAlignment = Enum.TextXAlignment.Left
    urlLabel.TextSize = 14
    urlLabel.Font = Enum.Font.Gotham
    urlLabel.Parent = frame

    local urlBox = Instance.new("TextBox")
    urlBox.Size = UDim2.new(1, -20, 0, 35)
    urlBox.Position = UDim2.new(0, 10, 0, 80)
    urlBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    urlBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    urlBox.PlaceholderText = "https://discord.com/api/webhooks/..."
    urlBox.Text = WebhookURL
    urlBox.TextSize = 14
    urlBox.Font = Enum.Font.Gotham
    urlBox.ClearTextOnFocus = false
    urlBox.Parent = frame

    local cornerUrl = Instance.new("UICorner")
    cornerUrl.CornerRadius = UDim.new(0, 5)
    cornerUrl.Parent = urlBox

    -- Status
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -20, 0, 30)
    statusLabel.Position = UDim2.new(0, 10, 0, 120)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: " .. (tableCount(FishData) > 0 and ("Data ikan: " .. tableCount(FishData)) or "Data ikan tidak ditemukan")
    statusLabel.TextColor3 = tableCount(FishData) > 0 and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = frame

    -- Filter Section
    local filterLabel = Instance.new("TextLabel")
    filterLabel.Size = UDim2.new(1, -20, 0, 20)
    filterLabel.Position = UDim2.new(0, 10, 0, 150)
    filterLabel.BackgroundTransparency = 1
    filterLabel.Text = "Filter Rarity:"
    filterLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    filterLabel.TextXAlignment = Enum.TextXAlignment.Left
    filterLabel.TextSize = 12
    filterLabel.Font = Enum.Font.Gotham
    filterLabel.Parent = frame

    -- Tombol filter
    local filterY = 175
    local btnWidth = 120
    local btnSpacing = 10
    local btnStartX = 10

    local function createFilterButton(text, xPos)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, btnWidth, 0, 30)
        btn.Position = UDim2.new(0, xPos, 0, filterY)
        btn.Text = text
        btn.TextSize = 14
        btn.Font = Enum.Font.GothamBold
        btn.Parent = frame
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 5)
        btnCorner.Parent = btn
        return btn
    end

    local btnLegendary = createFilterButton("Legendary", btnStartX)
    local btnMythic = createFilterButton("Mythic", btnStartX + btnWidth + btnSpacing)
    local btnSecret = createFilterButton("Secret", btnStartX + 2*(btnWidth + btnSpacing))

    -- Fungsi update warna tombol aktif
    local function updateFilterButtons()
        btnLegendary.BackgroundColor3 = (SelectedFilter == "Legendary") and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(80, 80, 80)
        btnMythic.BackgroundColor3 = (SelectedFilter == "Mythic") and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(80, 80, 80)
        btnSecret.BackgroundColor3 = (SelectedFilter == "Secret") and Color3.fromRGB(0, 200, 0) or Color3.fromRGB(80, 80, 80)
    end
    updateFilterButtons()

    btnLegendary.MouseButton1Click:Connect(function()
        SelectedFilter = "Legendary"
        updateFilterButtons()
    end)
    btnMythic.MouseButton1Click:Connect(function()
        SelectedFilter = "Mythic"
        updateFilterButtons()
    end)
    btnSecret.MouseButton1Click:Connect(function()
        SelectedFilter = "Secret"
        updateFilterButtons()
    end)

    -- Tombol Test Webhook
    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(0.5, -15, 0, 35)
    testBtn.Position = UDim2.new(0, 10, 0, 220)
    testBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    testBtn.Text = "Test Webhook"
    testBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testBtn.TextSize = 14
    testBtn.Font = Enum.Font.GothamBold
    testBtn.Parent = frame

    local cornerTest = Instance.new("UICorner")
    cornerTest.CornerRadius = UDim.new(0, 5)
    cornerTest.Parent = testBtn

    -- Tombol Simpan & Aktifkan
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.5, -15, 0, 35)
    saveBtn.Position = UDim2.new(0.5, 5, 0, 220)
    saveBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 0)
    saveBtn.Text = "Simpan & Aktifkan"
    saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveBtn.TextSize = 14
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.Parent = frame

    local cornerSave = Instance.new("UICorner")
    cornerSave.CornerRadius = UDim.new(0, 5)
    cornerSave.Parent = saveBtn

    -- Tombol Rescan Data
    local rescanBtn = Instance.new("TextButton")
    rescanBtn.Size = UDim2.new(1, -20, 0, 30)
    rescanBtn.Position = UDim2.new(0, 10, 0, 265)
    rescanBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    rescanBtn.Text = "Rescan Data Ikan"
    rescanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    rescanBtn.TextSize = 12
    rescanBtn.Font = Enum.Font.Gotham
    rescanBtn.Parent = frame

    local cornerRescan = Instance.new("UICorner")
    cornerRescan.CornerRadius = UDim.new(0, 5)
    cornerRescan.Parent = rescanBtn

    -- Event tombol test
    testBtn.MouseButton1Click:Connect(function()
        local url = urlBox.Text
        if url == "" then
            statusLabel.Text = "Status: Masukkan URL terlebih dahulu!"
            statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            return
        end
        statusLabel.Text = "Status: Mengirim test..."
        statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)

        local testEmbed = {
            title = "✅ Test Notification",
            description = "Webhook berhasil terhubung!",
            color = 0x76ff7a,
            fields = {
                {name = "Status", value = "Koneksi sukses", inline = true}
            },
            footer = {text = "Rayzerpedia • Test " .. os.date("%H:%M:%S")}
        }

        sendDiscordWebhook(url, testEmbed, function(success, message)
            if success then
                statusLabel.Text = "Status: " .. message
                statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
            else
                statusLabel.Text = "Status: " .. message
                statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            end
        end)
    end)

    -- Event tombol simpan
    saveBtn.MouseButton1Click:Connect(function()
        local url = urlBox.Text
        if url == "" then
            statusLabel.Text = "Status: URL tidak boleh kosong!"
            statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
            return
        end
        WebhookURL = url
        NotifierEnabled = true
        statusLabel.Text = "Status: Tersimpan dan aktif!"
        statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    end)

    -- Event tombol rescan
    rescanBtn.MouseButton1Click:Connect(function()
        statusLabel.Text = "Status: Memindai ulang data..."
        statusLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
        local newData = scanFishData()
        FishData = newData
        local count = tableCount(newData)
        if count > 0 then
            statusLabel.Text = "Status: Ditemukan " .. count .. " data ikan"
            statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        else
            statusLabel.Text = "Status: Data ikan tidak ditemukan"
            statusLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
        end
    end)

    -- Close button
    closeBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        toggleButton.Visible = true
    end)

    -- Toggle button
    toggleButton.MouseButton1Click:Connect(function()
        frame.Visible = true
        toggleButton.Visible = false
        frame.Active = true
    end)

    -- Drag functionality
    local dragging = false
    local dragStart, startPos

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    frame.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ================== INISIALISASI ==================
if Player then
    createGUI()
    setupListener()
else
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    Player = Players.LocalPlayer
    createGUI()
    setupListener()
end
