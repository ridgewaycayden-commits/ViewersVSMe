-- WeaponPolish.client.lua
-- VIEWERS VS ME - WEAPON POLISH V1
-- Add-on visual layer for the working AutoCombat FPS viewmodels.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local watchedModel = nil
local watchedMuzzle = nil
local lastMuzzleVisible = true

local function part(model,name,size,cf,color,material)
	local p=Instance.new("Part")
	p.Name=name
	p.Size=size
	p.CFrame=cf
	p.Color=color
	p.Material=material or Enum.Material.Metal
	p.Anchored=true
	p.CanCollide=false
	p.CanTouch=false
	p.CanQuery=false
	p.CastShadow=false
	p.Parent=model
	return p
end

local function detectWeapon(model)
	if model:FindFirstChild("Blade") then return "Sword" end
	if model:FindFirstChild("Barrel6") then return "Minigun" end
	if model:FindFirstChild("Pump") then return "Shotgun" end
	if model:FindFirstChild("Slide") then return "Pistol" end
	if model:FindFirstChild("SideGlow") then return "SMG" end
	return "Rifle"
end

local function addRel(model,name,size,rel,color,material)
	local root=model.PrimaryPart or model:FindFirstChild("Root")
	if not root then return end
	return part(model,name,size,root.CFrame*rel,color,material)
end

local function polish(model)
	if not model or model:GetAttribute("WeaponPolished") then return end
	local root=model.PrimaryPart or model:FindFirstChild("Root")
	if not root then return end
	model:SetAttribute("WeaponPolished",true)

	local black=Color3.fromRGB(8,10,13)
	local dark=Color3.fromRGB(22,25,31)
	local steel=Color3.fromRGB(86,96,110)
	local steel2=Color3.fromRGB(150,158,170)
	local red=Color3.fromRGB(255,50,60)
	local cyan=Color3.fromRGB(55,220,255)
	local orange=Color3.fromRGB(255,145,45)
	local weapon=detectWeapon(model)

	if weapon=="Rifle" then
		addRel(model,"Polish_MagWell",Vector3.new(.48,.40,.50),CFrame.new(.05,-.38,-.35),black,Enum.Material.Metal)
		addRel(model,"Polish_ChargingHandle",Vector3.new(.18,.13,.40),CFrame.new(.36,.23,.03),steel2,Enum.Material.Metal)
		addRel(model,"Polish_FrontSight",Vector3.new(.10,.34,.10),CFrame.new(.05,.38,-3.20),black,Enum.Material.Metal)
		addRel(model,"Polish_RearSight",Vector3.new(.16,.30,.10),CFrame.new(.05,.47,.20),black,Enum.Material.Metal)
		for i=0,5 do
			addRel(model,"Polish_SideVent"..i,Vector3.new(.05,.12,.18),CFrame.new(.31,.04,-1.30-i*.23)*CFrame.Angles(0,0,math.rad(20)),red,Enum.Material.Neon)
		end
		addRel(model,"Polish_LaserHousing",Vector3.new(.24,.22,.54),CFrame.new(-.28,.08,-2.08),dark,Enum.Material.Metal)
		addRel(model,"Polish_Laser",Vector3.new(.06,.06,.18),CFrame.new(-.28,.08,-2.44),red,Enum.Material.Neon)
	elseif weapon=="SMG" then
		addRel(model,"Polish_CompactSight",Vector3.new(.40,.32,.48),CFrame.new(.12,.53,-.78),black,Enum.Material.Metal)
		addRel(model,"Polish_SightGlass",Vector3.new(.24,.18,.04),CFrame.new(.12,.53,-1.04),cyan,Enum.Material.Neon)
		addRel(model,"Polish_MuzzleCage",Vector3.new(.25,.25,.48),CFrame.new(.12,.02,-3.14),black,Enum.Material.Metal)
		for i=0,3 do addRel(model,"Polish_Vent"..i,Vector3.new(.04,.13,.17),CFrame.new(.38,.09,-.96-i*.24),cyan,Enum.Material.Neon) end
	elseif weapon=="Shotgun" then
		addRel(model,"Polish_HeatShield",Vector3.new(.38,.18,2.10),CFrame.new(.08,.24,-2.35),black,Enum.Material.DiamondPlate)
		for i=0,6 do addRel(model,"Polish_ShellPort"..i,Vector3.new(.07,.10,.18),CFrame.new(.35,.08,-.65-i*.25),orange,Enum.Material.Neon) end
		addRel(model,"Polish_FrontBead",Vector3.new(.08,.10,.08),CFrame.new(.08,.22,-3.78),red,Enum.Material.Neon)
	elseif weapon=="Pistol" then
		addRel(model,"Polish_Comp",Vector3.new(.44,.35,.42),CFrame.new(.28,.03,-2.15),black,Enum.Material.Metal)
		addRel(model,"Polish_RedDot",Vector3.new(.30,.25,.34),CFrame.new(.28,.36,-.36),black,Enum.Material.Metal)
		addRel(model,"Polish_RedDotGlass",Vector3.new(.18,.13,.035),CFrame.new(.28,.36,-.55),red,Enum.Material.Neon)
		for i=0,2 do addRel(model,"Polish_SlideCut"..i,Vector3.new(.05,.16,.20),CFrame.new(.51,.08,-.38-i*.32),red,Enum.Material.Neon) end
	elseif weapon=="Minigun" then
		addRel(model,"Polish_Reactor",Vector3.new(.60,.60,.52),CFrame.new(.05,.06,.62),dark,Enum.Material.Metal)
		addRel(model,"Polish_ReactorCore",Vector3.new(.34,.34,.56),CFrame.new(.05,.06,.62),red,Enum.Material.Neon)
		addRel(model,"Polish_FrontRing",Vector3.new(.82,.82,.12),CFrame.new(.05,-.02,-3.78),black,Enum.Material.Metal)
		for i=0,3 do addRel(model,"Polish_PowerLine"..i,Vector3.new(.045,.045,1.12),CFrame.new(.43-i*.22,.34,-1.20)*CFrame.Angles(math.rad(90),0,0),red,Enum.Material.Neon) end
	elseif weapon=="Sword" then
		addRel(model,"Polish_Pommel",Vector3.new(.38,.30,.38),CFrame.new(.38,-.78,-.08),steel,Enum.Material.Metal)
		for i=0,5 do addRel(model,"Polish_Rune"..i,Vector3.new(.035,.10,.32),CFrame.new(.31,.04,-1.18-i*.45)*CFrame.Angles(0,0,math.rad(20)),red,Enum.Material.Neon) end
	end
end

local function spawnMuzzleFX(muzzle)
	if not muzzle or not muzzle.Parent then return end
	local light=Instance.new("PointLight")
	light.Color=muzzle.Color
	light.Brightness=5
	light.Range=12
	light.Shadows=false
	light.Parent=muzzle
	Debris:AddItem(light,.06)

	local flash=Instance.new("Part")
	flash.Name="WeaponPolishFlash"
	flash.Anchored=true
	flash.CanCollide=false
	flash.CanTouch=false
	flash.CanQuery=false
	flash.Material=Enum.Material.Neon
	flash.Color=muzzle.Color
	flash.Size=Vector3.new(.12,.12,.65)
	flash.CFrame=muzzle.CFrame*CFrame.new(0,0,-.32)
	flash.Parent=workspace
	Debris:AddItem(flash,.045)
end

local function hookModel(model)
	if not model or model.Name~="FPSViewModel" then return end
	watchedModel=model
	polish(model)
	watchedMuzzle=model:FindFirstChild("Muzzle")
	lastMuzzleVisible = watchedMuzzle and watchedMuzzle.Transparency < .5 or false
end

camera.ChildAdded:Connect(function(child)
	if child.Name=="FPSViewModel" then
		task.defer(function()
			task.wait()
			hookModel(child)
		end)
	end
end)

for _,child in ipairs(camera:GetChildren()) do if child.Name=="FPSViewModel" then hookModel(child) end end

RunService.RenderStepped:Connect(function()
	if watchedModel and watchedModel.Parent~=camera then
		watchedModel=nil
		watchedMuzzle=nil
	end
	if watchedModel and not watchedModel:GetAttribute("WeaponPolished") then polish(watchedModel) end
	if watchedModel and (not watchedMuzzle or not watchedMuzzle.Parent) then watchedMuzzle=watchedModel:FindFirstChild("Muzzle") end
	if watchedMuzzle then
		local visible=watchedMuzzle.Transparency<.5
		if visible and not lastMuzzleVisible then spawnMuzzleFX(watchedMuzzle) end
		lastMuzzleVisible=visible
	end
end)

print("WEAPON POLISH V1 READY - upgraded silhouettes, sights, vents, power cores, and muzzle FX.")