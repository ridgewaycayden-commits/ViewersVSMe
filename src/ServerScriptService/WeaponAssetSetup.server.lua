-- WeaponAssetSetup.server.lua
-- VIEWERS VS ME - imports the user's Toolbox gun models into ReplicatedStorage for the custom combat system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local wanted = {
	AK47 = true,
	Handgun = true,
	HyperlaserGun = true,
	Knife = true,
	Minigun = true,
	RocketLauncher = true,
}

local folder = ReplicatedStorage:FindFirstChild("WeaponAssets")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "WeaponAssets"
	folder.Parent = ReplicatedStorage
end

local function sanitize(root)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("ModuleScript")
			or obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
			obj:Destroy()
		end
	end
end

for name in pairs(wanted) do
	local source = StarterPack:FindFirstChild(name)
	if source then
		sanitize(source)
		local old = folder:FindFirstChild(name)
		if old then old:Destroy() end
		source.Parent = folder
		print("WEAPON ASSET READY:", name)
	else
		warn("WEAPON ASSET MISSING FROM STARTERPACK:", name)
	end
end

print("WEAPON ASSET SETUP READY - Toolbox weapons sanitized and stored in ReplicatedStorage")
