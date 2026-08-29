-- BrighterMap.server.lua
-- Put in ServerScriptService.
-- Brightens the existing nighttime TikTok city without rebuilding it.

local Lighting = game:GetService("Lighting")

Lighting.ClockTime = 20.2
Lighting.Brightness = 3.2
Lighting.ExposureCompensation = 0.65
Lighting.Ambient = Color3.fromRGB(85, 92, 112)
Lighting.OutdoorAmbient = Color3.fromRGB(105, 112, 135)
Lighting.EnvironmentDiffuseScale = 0.55
Lighting.EnvironmentSpecularScale = 0.75
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.35

-- Keep the night atmosphere, but remove the heavy darkness/fog.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.05
	atmosphere.Haze = 0.8
	atmosphere.Glare = 0.08
	atmosphere.Color = Color3.fromRGB(185, 195, 220)
	atmosphere.Decay = Color3.fromRGB(90, 105, 145)
end

local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if bloom then
	bloom.Intensity = 0.75
	bloom.Size = 28
	bloom.Threshold = 1.1
else
	bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.75
	bloom.Size = 28
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
end

local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if color then
	color.Brightness = 0.08
	color.Contrast = 0.06
	color.Saturation = 0.08
else
	color = Instance.new("ColorCorrectionEffect")
	color.Brightness = 0.08
	color.Contrast = 0.06
	color.Saturation = 0.08
	color.Parent = Lighting
end

-- Add soft overhead street illumination around the generated city.
local city = workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")
if city then
	local old = city:FindFirstChild("StreamLighting")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "StreamLighting"
	folder.Parent = city

	for x = -240, 240, 80 do
		for z = -240, 240, 80 do
			local anchor = Instance.new("Part")
			anchor.Name = "FillLight"
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.Transparency = 1
			anchor.Size = Vector3.new(1,1,1)
			anchor.Position = Vector3.new(x, 24, z)
			anchor.Parent = folder

			local light = Instance.new("PointLight")
			light.Brightness = 1.15
			light.Range = 58
			light.Shadows = false
			light.Color = Color3.fromRGB(205, 215, 255)
			light.Parent = anchor
		end
	end
end

print("TikTok city brighter stream lighting enabled.")
