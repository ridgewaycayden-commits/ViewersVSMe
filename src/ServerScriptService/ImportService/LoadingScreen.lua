local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LoadingScreen = {}

-- Per-player tracking so newly-joined players also get the screen and any
-- in-progress status / error overlay. The bootstrap path runs server-side, so
-- the only reliable way to surface diagnostics in the native player (no F9
-- console available) is to mirror state into every player's PlayerGui.
local playerEntries = {} -- [player] = { gui, statusLabel, progressBar, errorFrame, errorLabel, errorDetail }
local cachedWorldName = nil
local cachedStatus = "Initializing..."
local cachedFraction = 0
local cachedErrorMessage = nil
local cachedErrorDetail = nil
local playerAddedConnection = nil
local playerRemovingConnection = nil

local function ensurePlayerHooks()
    if not playerAddedConnection then
        playerAddedConnection = Players.PlayerAdded:Connect(function(player)
            if cachedWorldName then
                LoadingScreen.Show(cachedWorldName)
            end
            if cachedErrorMessage then
                LoadingScreen.ShowError(cachedErrorMessage, cachedErrorDetail)
            end
        end)
    end
    if not playerRemovingConnection then
        playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
            playerEntries[player] = nil
        end)
    end
end

local function buildGui(player, worldName)
    local existing = playerEntries[player]
    if existing and existing.gui and existing.gui.Parent then
        return existing
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "LoadingScreen"
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local bg = Instance.new("Frame")
    bg.Name = "Background"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    bg.BackgroundTransparency = 1
    bg.BorderSizePixel = 0
    bg.Parent = gui

    TweenService:Create(bg, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {
        BackgroundTransparency = 0,
    }):Play()

    local title = Instance.new("TextLabel")
    title.Name = "CityName"
    title.Size = UDim2.new(0.8, 0, 0, 60)
    title.Position = UDim2.new(0.1, 0, 0.35, 0)
    title.BackgroundTransparency = 1
    title.Text = worldName or "Loading World"
    title.TextColor3 = Color3.fromRGB(240, 242, 248)
    title.TextSize = 42
    title.Font = Enum.Font.GothamBold
    title.Parent = bg

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(0.8, 0, 0, 24)
    subtitle.Position = UDim2.new(0.1, 0, 0.35, 65)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Arnis HD Pipeline v0.4.0 — Generated from OpenStreetMap"
    subtitle.TextColor3 = Color3.fromRGB(120, 125, 140)
    subtitle.TextSize = 16
    subtitle.Font = Enum.Font.Gotham
    subtitle.Parent = bg

    local barBg = Instance.new("Frame")
    barBg.Name = "ProgressBg"
    barBg.Size = UDim2.new(0.4, 0, 0, 4)
    barBg.Position = UDim2.new(0.3, 0, 0.55, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 42, 50)
    barBg.BorderSizePixel = 0
    barBg.Parent = bg

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 2)
    barCorner.Parent = barBg

    local barFill = Instance.new("Frame")
    barFill.Name = "ProgressFill"
    barFill.Size = UDim2.new(math.clamp(cachedFraction or 0, 0, 1), 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = barFill

    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(0.8, 0, 0, 20)
    status.Position = UDim2.new(0.1, 0, 0.55, 15)
    status.BackgroundTransparency = 1
    status.Text = cachedStatus or "Initializing..."
    status.TextColor3 = Color3.fromRGB(140, 150, 170)
    status.TextSize = 14
    status.Font = Enum.Font.Gotham
    status.Parent = bg

    local controls = Instance.new("TextLabel")
    controls.Name = "Controls"
    controls.Size = UDim2.new(0.8, 0, 0, 40)
    controls.Position = UDim2.new(0.1, 0, 0.85, 0)
    controls.BackgroundTransparency = 1
    controls.Text = "[V] Car   [J] Jetpack   [P] Parachute   [M] Map   [C] Cinematic"
    controls.TextColor3 = Color3.fromRGB(70, 75, 90)
    controls.TextSize = 12
    controls.Font = Enum.Font.Gotham
    controls.Parent = bg

    -- Error overlay (hidden until ShowError is called).
    local errorFrame = Instance.new("Frame")
    errorFrame.Name = "ErrorOverlay"
    errorFrame.Size = UDim2.new(0.85, 0, 0, 220)
    errorFrame.Position = UDim2.new(0.075, 0, 0.62, 0)
    errorFrame.BackgroundColor3 = Color3.fromRGB(40, 14, 18)
    errorFrame.BorderSizePixel = 0
    errorFrame.Visible = false
    errorFrame.Parent = bg

    local errorCorner = Instance.new("UICorner")
    errorCorner.CornerRadius = UDim.new(0, 6)
    errorCorner.Parent = errorFrame

    local errorStroke = Instance.new("UIStroke")
    errorStroke.Color = Color3.fromRGB(220, 80, 80)
    errorStroke.Thickness = 2
    errorStroke.Parent = errorFrame

    local errorTitle = Instance.new("TextLabel")
    errorTitle.Name = "ErrorTitle"
    errorTitle.Size = UDim2.new(1, -24, 0, 28)
    errorTitle.Position = UDim2.new(0, 12, 0, 10)
    errorTitle.BackgroundTransparency = 1
    errorTitle.Text = "BOOTSTRAP FAILED"
    errorTitle.TextColor3 = Color3.fromRGB(255, 120, 120)
    errorTitle.TextSize = 18
    errorTitle.Font = Enum.Font.GothamBold
    errorTitle.TextXAlignment = Enum.TextXAlignment.Left
    errorTitle.Parent = errorFrame

    local errorLabel = Instance.new("TextLabel")
    errorLabel.Name = "ErrorMessage"
    errorLabel.Size = UDim2.new(1, -24, 0, 50)
    errorLabel.Position = UDim2.new(0, 12, 0, 38)
    errorLabel.BackgroundTransparency = 1
    errorLabel.Text = ""
    errorLabel.TextColor3 = Color3.fromRGB(255, 220, 220)
    errorLabel.TextSize = 15
    errorLabel.Font = Enum.Font.GothamSemibold
    errorLabel.TextXAlignment = Enum.TextXAlignment.Left
    errorLabel.TextYAlignment = Enum.TextYAlignment.Top
    errorLabel.TextWrapped = true
    errorLabel.Parent = errorFrame

    local errorDetail = Instance.new("TextLabel")
    errorDetail.Name = "ErrorDetail"
    errorDetail.Size = UDim2.new(1, -24, 0, 110)
    errorDetail.Position = UDim2.new(0, 12, 0, 96)
    errorDetail.BackgroundTransparency = 1
    errorDetail.Text = ""
    errorDetail.TextColor3 = Color3.fromRGB(220, 200, 200)
    errorDetail.TextSize = 12
    errorDetail.Font = Enum.Font.Code
    errorDetail.TextXAlignment = Enum.TextXAlignment.Left
    errorDetail.TextYAlignment = Enum.TextYAlignment.Top
    errorDetail.TextWrapped = true
    errorDetail.Parent = errorFrame

    -- `player.PlayerGui` is auto-created by Roblox as soon as the Player
    -- instance exists, so it's always available without waiting. Using
    -- WaitForChild here would indefinitely yield the calling coroutine if
    -- the player has already loaded their character, because the property
    -- is read-only-on-the-server after that point. FindFirstChildOfClass
    -- is the safe read that works from both server and client contexts.
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if playerGui == nil then
        -- Extremely small window during player onboarding where the
        -- Player instance exists but PlayerGui hasn't replicated yet.
        -- Bounded wait so we never hang the caller forever.
        playerGui = player:WaitForChild("PlayerGui", 5)
    end
    if playerGui == nil then
        warn(("[LoadingScreen] No PlayerGui for %s after 5s; skipping build"):format(player.Name))
        return nil
    end
    gui.Parent = playerGui

    local entry = {
        gui = gui,
        statusLabel = status,
        progressBar = barFill,
        errorFrame = errorFrame,
        errorLabel = errorLabel,
        errorDetail = errorDetail,
    }
    playerEntries[player] = entry
    return entry
end

function LoadingScreen.Show(worldName)
    cachedWorldName = worldName or cachedWorldName or "Loading World"
    ensurePlayerHooks()
    for _, player in ipairs(Players:GetPlayers()) do
        local ok, err = pcall(buildGui, player, cachedWorldName)
        if not ok then
            warn(("[LoadingScreen] Failed to build GUI for %s: %s"):format(player.Name, tostring(err)))
        end
    end
end

function LoadingScreen.UpdateProgress(fraction, statusText)
    if typeof(fraction) == "number" then
        cachedFraction = math.clamp(fraction, 0, 1)
    end
    if statusText then
        cachedStatus = statusText
    end
    for _, entry in pairs(playerEntries) do
        if entry.progressBar and typeof(fraction) == "number" then
            TweenService:Create(entry.progressBar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
                Size = UDim2.new(cachedFraction, 0, 1, 0),
            }):Play()
        end
        if entry.statusLabel and statusText then
            entry.statusLabel.Text = statusText
        end
    end
end

function LoadingScreen.SetStatus(statusText)
    LoadingScreen.UpdateProgress(nil, statusText)
end

function LoadingScreen.ShowError(message, detail)
    cachedErrorMessage = message or cachedErrorMessage or "Unknown error"
    cachedErrorDetail = detail or cachedErrorDetail
    -- Make sure a screen exists for everyone, even if Show wasn't called.
    if not cachedWorldName then
        cachedWorldName = "Austin, TX"
    end
    LoadingScreen.Show(cachedWorldName)
    for _, entry in pairs(playerEntries) do
        if entry.errorFrame then
            entry.errorFrame.Visible = true
        end
        if entry.errorLabel then
            entry.errorLabel.Text = tostring(cachedErrorMessage)
        end
        if entry.errorDetail then
            entry.errorDetail.Text = tostring(cachedErrorDetail or "")
        end
        if entry.statusLabel then
            entry.statusLabel.Text = "Bootstrap halted — see error below"
            entry.statusLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        end
    end
    warn(("[LoadingScreen] ShowError: %s | %s"):format(tostring(message), tostring(detail or "")))
end

function LoadingScreen.Hide()
    -- Don't hide if an error is being shown — keep diagnostics visible.
    if cachedErrorMessage then
        return
    end
    for player, entry in pairs(playerEntries) do
        local gui = entry.gui
        if gui and gui.Parent then
            local bg = gui:FindFirstChild("Background")
            if bg then
                TweenService:Create(bg, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
                    BackgroundTransparency = 1,
                }):Play()
                for _, child in ipairs(bg:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        TweenService:Create(child, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
                            TextTransparency = 1,
                        }):Play()
                    elseif child:IsA("Frame") then
                        TweenService:Create(child, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
                            BackgroundTransparency = 1,
                        }):Play()
                    end
                end
            end
            local destroyTarget = gui
            local capturedPlayer = player
            task.delay(2, function()
                if destroyTarget and destroyTarget.Parent then
                    destroyTarget:Destroy()
                end
                playerEntries[capturedPlayer] = nil
            end)
        end
    end
    cachedWorldName = nil
    cachedStatus = "Initializing..."
    cachedFraction = 0
end

return LoadingScreen
