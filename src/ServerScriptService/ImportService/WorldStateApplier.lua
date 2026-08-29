local gameLighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldStateApplier = {}
local WorldStateConfig = require(ReplicatedStorage.Shared.WorldStateConfig)
local WORLD_ROOT_ATTR = "ArnisWorldRootName"

local function resolveConfigValue(config, key)
    if type(config) == "table" and config[key] ~= nil then
        return config[key]
    end
    return WorldStateConfig[key]
end

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local function ensureAtmosphere()
    local atmosphere = gameLighting:FindFirstChildOfClass("Atmosphere")
    if not atmosphere then
        atmosphere = Instance.new("Atmosphere")
        atmosphere.Parent = gameLighting
    end

    -- Stronger depth cue for distant skylines (Cesium/Google Earth feel).
    -- DayNightCycle re-tunes these per phase, but we set sensible defaults
    -- that already match a cinematic midday look.
    atmosphere.Density = 0.2
    atmosphere.Offset = 0.15
    atmosphere.Glare = 0.0
    atmosphere.Haze = 0.0
    atmosphere.Color = Color3.fromRGB(199, 210, 225)
    atmosphere.Decay = Color3.fromRGB(92, 104, 124)
end

local function ensureSky()
    -- Default Roblox sky is fine, but explicitly creating one lets us pin
    -- celestial-body sizes and ensure SunAngularSize isn't 0 (which makes
    -- the sun a hard pinprick instead of a soft disc).
    local sky = gameLighting:FindFirstChildOfClass("Sky")
    if not sky then
        sky = Instance.new("Sky")
        sky.Name = "ArnisSky"
        sky.Parent = gameLighting
    end
    sky.SunAngularSize = 11 -- soft disc, ~3x default for atmospheric bloom
    sky.MoonAngularSize = 11
    sky.StarCount = 3000
end

local function ensureBloom()
    local bloom = gameLighting:FindFirstChildOfClass("BloomEffect")
    if not bloom then
        bloom = Instance.new("BloomEffect")
        bloom.Parent = gameLighting
    end

    bloom.Intensity = 0.6
    bloom.Size = 28
    bloom.Threshold = 1.6
end

local function ensureColorCorrection()
    local colorCorrection = gameLighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if not colorCorrection then
        colorCorrection = Instance.new("ColorCorrectionEffect")
        colorCorrection.Parent = gameLighting
    end

    -- Subtle filmic grade: slight desaturation, mild lift, warm white point.
    colorCorrection.Brightness = 0.015
    colorCorrection.Contrast = 0.09
    colorCorrection.Saturation = -0.04
    colorCorrection.TintColor = Color3.fromRGB(255, 250, 244)
end

local function ensureSunRays()
    local sunRays = gameLighting:FindFirstChildOfClass("SunRaysEffect")
    if not sunRays then
        sunRays = Instance.new("SunRaysEffect")
        sunRays.Parent = gameLighting
    end

    sunRays.Intensity = 0.18
    sunRays.Spread = 0.85
end

local function ensureDepthOfField()
    -- Mild far-field DOF blends distant skyline into atmosphere haze, the
    -- key Cesium/Google Earth depth cue. Kept subtle to avoid Bokeh artifacts.
    local dof = gameLighting:FindFirstChildOfClass("DepthOfFieldEffect")
    if not dof then
        dof = Instance.new("DepthOfFieldEffect")
        dof.Parent = gameLighting
    end
    dof.FarIntensity = 0.18
    dof.NearIntensity = 0
    dof.FocusDistance = 80
    dof.InFocusRadius = 220
end

local function applyAtmosphere()
    ensureAtmosphere()
    ensureSky()

    gameLighting.Brightness = 2.4
    gameLighting.EnvironmentDiffuseScale = 1
    gameLighting.EnvironmentSpecularScale = 1
    gameLighting.GlobalShadows = true
    -- Sharper, more directional sun shadows for a Cesium/Google Earth look.
    gameLighting.ShadowSoftness = 0.12
    -- Pin Technology lighting for accurate PBR + sun reflections on glass.
    pcall(function()
        gameLighting.Technology = Enum.Technology.Future
    end)

    ensureBloom()
    ensureColorCorrection()
    ensureSunRays()
    ensureDepthOfField()
end

function WorldStateApplier.Apply(manifest, config, options)
    local resolvedOptions = options or {}
    Workspace:SetAttribute(WORLD_ROOT_ATTR, resolvedOptions.worldRootName or "GeneratedWorld")

    if resolveConfigValue(config, "EnableAtmosphere") ~= false then
        applyAtmosphere()
    end

    if manifest and manifest.meta and manifest.meta.bbox then
        local bbox = manifest.meta.bbox
        local latitude = (bbox.minLat + bbox.maxLat) / 2
        local longitude = (bbox.minLon + bbox.maxLon) / 2
        local datetime = resolveConfigValue(config, "DateTime") or "auto"
        local dayNightCycle = require(script.Parent.DayNightCycle)
        dayNightCycle.Configure(latitude, longitude, datetime)

        if resolveConfigValue(config, "EnableDayNightCycle") ~= false then
            dayNightCycle.Start(resolveConfigValue(config, "DayNightSpeed"))
        end
    end

    if resolvedOptions.startMinimap == true and resolveConfigValue(config, "EnableMinimap") ~= false then
        local minimapService = require(script.Parent.MinimapService)
        minimapService.Start({
            worldRootName = resolvedOptions.worldRootName,
        })
    end

    if resolvedOptions.hideLoadingScreen == true then
        local loadingScreen = require(script.Parent.LoadingScreen)
        loadingScreen.Hide()
    end
end

return WorldStateApplier
