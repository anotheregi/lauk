-- =====================================================
-- FISH IT NOTIFIER - FINAL STABLE VERSION
-- Optimized | Clean | Auto Remote | All Executors
-- =====================================================

-- ================== SERVICES ==================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer

-- ================== CONFIG ==================
local WebhookURL = "https://discord.com/api/webhooks/1473582182718115933/WapyrLJwWEJKITU5czzSzBiqDLHD7jIlTddWhKls2msrozUCwjS427NKhaj49BhGsdu6"
local NotifierEnabled = true
local SelectedFilter = "Legendary" -- Legendary / Mythic / Secret

local BotUsername = "rayzerkeren"
local BotAvatarUrl = "https://i.imgur.com/3PuhVRE.png"

-- ================== TIER MAP ==================
local TIER = {
    Legendary = 5,
    Mythic = 6,
    Secret = 7
}

-- ================== STORAGE ==================
local FishData = {}
local IconCache = {}
local ListenerConnected = false
local DEFAULT_THUMBNAIL = "https://i.imgur.com/3PuhVRE.png"

-- =====================================================
-- ================== UTILITIES ==================
-- =====================================================

local function extractAssetId(iconString)
    if type(iconString) ~= "string" then return nil end
    return iconString:match("(%d+)")
end

-- =====================================================
-- ================== LOAD FISH DATA ==================
-- =====================================================

local function loadFishData()
    local ItemsFolder = ReplicatedStorage:WaitForChild("Items", 10)
    if not ItemsFolder then
        warn("[FishNotifier] Items folder tidak ditemukan.")
        return false
    end

    repeat task.wait() until #ItemsFolder:GetDescendants() > 0

    local count = 0

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

    print("[FishNotifier] Fish Loaded:", count)
    return count > 0
end

-- =====================================================
-- ================== PARSE MESSAGE ==================
-- =====================================================

local function parseFishMessage(msg)

    local username = msg:match("%]:</font></b> ([^%s]+) obtained")
    if not username then return nil end

    local fullFishText, weightStr =
        msg:match('<b><font color="[^"]+">(.-) %(([%d%.]+)kg%)</font></b>')

    if not fullFishText then return nil end

    local mutation, fishName = fullFishText:match("^(%u+)%s+(.+)")
    if not mutation then
        fishName = fullFishText
    end

    local rarityText = msg:match("(1 in [%d%.]+[KM]? chance!)")
    if not rarityText then return nil end

    return {
        username = username,
        fishName = fishName,
        weight = tonumber(weightStr),
        rarityText = rarityText,
        mutation = mutation
    }
end

-- =====================================================
-- ================== ICON SYSTEM ==================
-- =====================================================

local function fetchThumbnailURL(assetId)
    if not assetId then return nil end

    local url = ("https://thumbnails.roblox.com/v1/assets?assetIds=%s&size=420x420&format=Png&isCircular=false")
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

local function sendDiscordWebhook(embed)

    if not NotifierEnabled or WebhookURL == "" then return end

    local payload = {
        username = BotUsername,
        avatar_url = BotAvatarUrl,
        embeds = {embed}
    }

    local json = HttpService:JSONEncode(payload)

    local httpRequest =
        (syn and syn.request)
        or (http and http.request)
        or (request)
        or (http_request)
        or (fluxus and fluxus.request)

    if not httpRequest then
        warn("[FishNotifier] Executor tidak support HTTP request.")
        return
    end

    local success, response = pcall(function()
        return httpRequest({
            Url = WebhookURL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = json
        })
    end)

    print("[FishNotifier] Webhook sent:", success)
end

-- =====================================================
-- ================== FIND REMOTE ==================
-- =====================================================

local function findFishRemote()
    for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
        if remote:IsA("RemoteEvent")
        and string.find(remote.Name:lower(), "fish") then
            return remote
        end
    end
    return nil
end

-- =====================================================
-- ================== LISTENER ==================
-- =====================================================

local function setupListener()

    if ListenerConnected then return end

    local FishRemote = findFishRemote()
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

        local fishInfo = FishData[string.lower(parsed.fishName)]
        if not fishInfo then return end

        local requiredTier = TIER[SelectedFilter]

        print("Detected:", parsed.fishName, "| Tier:", fishInfo.tier)

        if fishInfo.tier == requiredTier then

            local embed = {
                title = "🎣 " .. SelectedFilter:upper() .. " FISH CAUGHT!",
                color = 0x76ff7a,
                thumbnail = {url = getFishIconURL(parsed.fishName)},
                fields = {
                    {name="User", value="@"..parsed.username, inline=true},
                    {name="Fish", value=parsed.fishName, inline=true},
                    {name="Mutation", value=parsed.mutation or "-", inline=true},
                    {name="Weight", value=parsed.weight.." kg", inline=true},
                    {name="Rarity", value=parsed.rarityText, inline=true}
                },
                footer = {text = os.date("%d-%m-%Y %H:%M:%S")}
            }

            sendDiscordWebhook(embed)
        end

    end)

    print("[FishNotifier] Listener active.")
end

-- =====================================================
-- ================== START ==================
-- =====================================================

task.spawn(function()

    local success = loadFishData()
    if not success then
        warn("[FishNotifier] Data kosong.")
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
