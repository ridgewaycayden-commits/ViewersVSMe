--[[
    AtmosphereConfig.lua
    Sets baseline AAA lighting, atmosphere, and post-processing effects.

    Called once after world_ready in BootstrapAustin. DayNightCycle.lua handles
    time-of-day animation and lerps atmospheric values from this baseline toward
    its per-phase targets — this module only sets the initial state.
]]

local Lighting = game:GetService("Lighting")

local AtmosphereConfig = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Find or create a child of the given class under Lighting.
local function ensureEffect(className, name)
    local existing = Lighting:FindFirstChildOfClass(className)
    if existing then
        return existing
    end
    local effect = Instance.new(className)
    effect.Name = name or className
    effect.Parent = Lighting
    return effect
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Apply AAA baseline lighting + atmosphere + post-processing to the Lighting
--- service. Safe to call multiple times; idempotent.
function AtmosphereConfig.Apply()
    -- ── Lighting service properties ──────────────────────────────────
    -- Lighting.Technology is a protected property in Roblox 2026 —
    -- server scripts lack RobloxScript capability to write it. Must be
    -- set in Studio place settings or via the rbxlx XML patcher.
    pcall(function()
        Lighting.Technology = Enum.Technology.Future
    end)
    Lighting.GlobalShadows = true
    Lighting.Brightness = 2
    Lighting.EnvironmentDiffuseScale = 0.5
    Lighting.EnvironmentSpecularScale = 0.5
    Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)

    -- ── Atmosphere ───────────────────────────────────────────────────
    local atmo = ensureEffect("Atmosphere", "Atmosphere")
    atmo.Density = 0.3
    atmo.Offset = 0.25
    atmo.Color = Color3.fromRGB(199, 210, 225)
    atmo.Decay = Color3.fromRGB(92, 92, 102)
    atmo.Glare = 0.5
    atmo.Haze = 2

    -- ── ColorCorrectionEffect ────────────────────────────────────────
    local cc = ensureEffect("ColorCorrectionEffect", "ColorCorrection")
    cc.Brightness = 0.05
    cc.Contrast = 0.1
    cc.Saturation = 0.15
    cc.TintColor = Color3.fromRGB(255, 248, 240)

    -- ── BloomEffect ──────────────────────────────────────────────────
    local bloom = ensureEffect("BloomEffect", "Bloom")
    bloom.Intensity = 0.4
    bloom.Size = 24
    bloom.Threshold = 1.5

    -- ── SunRaysEffect ────────────────────────────────────────────────
    local sunRays = ensureEffect("SunRaysEffect", "SunRays")
    sunRays.Intensity = 0.12
    sunRays.Spread = 0.6

    print("[AtmosphereConfig] AAA baseline lighting + atmosphere applied.")
end

return AtmosphereConfig
