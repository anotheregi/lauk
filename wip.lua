-- =====================================================
-- FISH IT NOTIFIER - CLEAN & FAST VERSION
-- Strict Rarity Filter | Optimized | No Fallback
-- =====================================================

-- ================== SERVICES ==================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

-- ================== CONFIG ==================
local WebhookURL = "https://discord.com/api/webhooks/1473582182718115933/WapyrLJwWEJKITU5czzSzBiqDLHD7jIlTddWhKls2msrozUCwjS427NKhaj49BhGsdu6"
local NotifierEnabled = true
local BotUsername = "Rayzer keren"
local BotAvatarUrl = "https://i.imgur.com/3PuhVRE.png"

-- ================== FILTER ==================
local SelectedFilter = "Legendary"

local TIER = {
    Legendary = 5,
    Mythic = 6,
    Secret = 7
}

-- ================== DATA STORAGE ==================
local FishData = {}       -- [lowercaseName] = { tier = number, icon = assetId }
local IconCache = {}
local ListenerConnected = false
local FishRemote = nil

local DEFAULT_THUMBNAIL = "https://i.imgur.com/3PuhVRE.png"

-- =====================================================
-- ================== UTILITIES ==================
-- =====================================================

local function extractAssetId(iconString)
    if type(iconString) ~= "string" then return nil end
    return iconString:match("(%d+)")
end

-- =====================================================
-- ================== SCAN FISH DATA ==================
-- =====================================================
local function loadFishData()

    local count = 0

    local ItemsFolder = ReplicatedStorage:WaitForChild("Items")

    for _, obj in ipairs(ItemsFolder:GetDescendants()) do
        if obj:IsA("ModuleScript") then

            local ok, moduleData = pcall(require, obj)
            if ok and type(moduleData) == "table" then

                local data = moduleData.Data

                if type(data) == "table"
                and data.Type == "Fish"
                and data.Name
                and data.Tier then

                    FishData[string.lower(data.Name)] = {
                        tier = tonumber(data.Tier) or 0,
                        icon = extractAssetId(data.Icon)
                    }

                    count += 1
                end
            end
        end
    end

    print("[FishNotifier] Loaded:", count)
    return count > 0
end


-- =====================================================
-- ================== PARSE MESSAGE ==================
-- =====================================================

local function parseFishMessage(msg)
    local username = msg:match('%[Server%]:</font></b> ([^%s]+) obtained')
    if not username then return nil end

    local fullFishText, weightStr =
        msg:match('<b><font color="[^"]+">(.-) %(([%d%.]+)kg%)</font></b>')

    if not fullFishText then return nil end

    local weight = tonumber(weightStr)

    local mutation, fishName = fullFishText:match('^(%u+)%s+(.+)')
    if not mutation then
        fishName = fullFishText
    end

    local rarityText = msg:match('with a (1 in [%d%.]+[KM]? chance!)')
    if not rarityText then return nil end

    return {
        username = username,
        fishName = fishName,
        weight = weight,
        rarityText = rarityText,
        mutation = mutation
    }
end

-- =====================================================
-- ================== ICON SYSTEM ==================
-- =====================================================

local function fetchThumbnailURL(assetId)
    if not assetId then return nil end

    local url =
        ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false")
        :format(assetId)

    local success, response = pcall(function()
        return HttpService:GetAsync(url)
    end)

    if not success then return nil end

    local data = HttpService:JSONDecode(response)
    if data and data.data and #data.data > 0 then
        return data.data[1].imageUrl
    end

    return nil
end

local function getFishIconURL(fishName)
    local cleanName = string.lower(fishName)

    if IconCache[cleanName] then
        return IconCache[cleanName]
    end

    local info = FishData[cleanName]
    if not info or not info.icon then
        IconCache[cleanName] = DEFAULT_THUMBNAIL
        return DEFAULT_THUMBNAIL
    end

    local cdn = fetchThumbnailURL(info.icon)
    IconCache[cleanName] = cdn or DEFAULT_THUMBNAIL

    return IconCache[cleanName]
end

-- =====================================================
-- ================== WEBHOOK ==================
-- =====================================================

local function sendDiscordWebhook(url, embed)
    if url == "" then return end

    local payload = {
        username = BotUsername,
        avatar_url = BotAvatarUrl,
        embeds = {embed}
    }

    local json = HttpService:JSONEncode(payload)

    pcall(function()
        HttpService:PostAsync(url, json, Enum.HttpContentType.ApplicationJson)
    end)
end

local function sendNotification(data)
    if not NotifierEnabled or WebhookURL == "" then return end

    local iconUrl = getFishIconURL(data.fishName)

    local embed = {
        title = "🎣 " .. SelectedFilter:upper() .. " FISH CAUGHT!",
        color = 0x76ff7a,

        thumbnail = { url = iconUrl },

        fields = {
            {name="User", value="@"..data.username, inline=true},
            {name="Fish", value=data.fishName, inline=true},
            {name="Mutation", value=data.mutation or "-", inline=true},
            {name="Weight", value=data.weight.." kg", inline=true},
            {name="Rarity", value=data.rarityText, inline=true}
        },

        footer = {
            text = os.date("%d-%m-%Y %H:%M:%S")
        }
    }

    sendDiscordWebhook(WebhookURL, embed)
end

-- =====================================================
-- ================== LISTENER ==================
-- =====================================================

local function findFishRemote()
    for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
        if remote:IsA("RemoteEvent") and
           string.find(remote.Name:lower(), "fish") then
            return remote
        end
    end
    return nil
end

local function setupListener()
    if ListenerConnected then return end

    FishRemote = findFishRemote()
    if not FishRemote then
        warn("[FishNotifier] Remote fish tidak ditemukan.")
        return
    end

    ListenerConnected = true

    FishRemote.OnClientEvent:Connect(function(message)
        if type(message) ~= "string" then return end
        if not string.find(message, "obtained") then return end

        local parsed = parseFishMessage(message)
        if not parsed then return end

        local cleanName = string.lower(parsed.fishName)
        local fishInfo = FishData[cleanName]
        if not fishInfo then return end

        local requiredTier = TIER[SelectedFilter]

        if fishInfo.tier == requiredTier then
            sendNotification(parsed)
        end
    end)

    print("[FishNotifier] Clean listener active.")
end

-- =====================================================
-- ================== START ==================
-- =====================================================

task.spawn(function()

    local success = loadFishData()
    if not success then
        warn("[FishNotifier] Data ikan kosong. Listener tidak dipasang.")
        return
    end

    if Player then
        setupListener()
    else
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
        Player = Players.LocalPlayer
        setupListener()
    end

end)
