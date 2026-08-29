-- CityOverhaul.server.lua
-- V6 "NEON QUARANTINE" CITY TRANSFORMATION
-- Put in ServerScriptService as CityOverhaul.
-- This heavily transforms the existing map instead of only adding a few props.

local Lighting = game:GetService("Lighting")

local oldCity = workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")

if not oldCity then
	warn("CITY V6: existing city folder not found.")
	return
end

local oldOverlay = oldCity:FindFirstChild("V5Overhaul")
if oldOverlay then oldOverlay:Destroy() end

local prior = workspace:FindFirstChild("NeonQuarantineV6")
if prior then prior:Destroy() end

local world = Instance.new("Folder")
world.Name = "NeonQuarantineV6"
world.Parent = workspace

Lighting.ClockTime = 21.15
Lighting.Brightness = 3.75
Lighting.ExposureCompensation = .9
Lighting.Ambient = Color3.fromRGB(84,92,118)
Lighting.OutdoorAmbient = Color3.fromRGB(120,128,155)
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = .22
Lighting.EnvironmentDiffuseScale = .72
Lighting.EnvironmentSpecularScale = 1

local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere",Lighting)
atm.Density = .15
atm.Offset = .05
atm.Haze = .8
atm.Glare = .12
atm.Color = Color3.fromRGB(180,198,235)
atm.Decay = Color3.fromRGB(80,95,140)

local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect",Lighting)
bloom.Intensity = 1.05
bloom.Size = 40
bloom.Threshold = .9

local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect",Lighting)
cc.Brightness = .09
cc.Contrast = .18
cc.Saturation = .12
cc.TintColor = Color3.fromRGB(225,235,255)

local function makePart(name,size,cframe,color,material,parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = true
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Parent = parent or world
	return p
end

local function noCollision(p)
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

local function neonStrip(cframe,size,color,parent)
	local p = makePart("NeonStrip",size,cframe,color,Enum.Material.Neon,parent)
	noCollision(p)
	local light = Instance.new("PointLight")
	light.Brightness = 1.1
	light.Range = 17
	light.Shadows = false
	light.Color = color
	light.Parent = p
	return p
end

local function streetLamp(pos,cyan)
	local model = Instance.new("Model")
	model.Name = "StreetLamp"
	model.Parent = world
	makePart("Pole",Vector3.new(.5,13,.5),CFrame.new(pos+Vector3.new(0,6.5,0)),Color3.fromRGB(35,40,48),Enum.Material.Metal,model)
	local arm = makePart("Arm",Vector3.new(4,.35,.35),CFrame.new(pos+Vector3.new(1.7,12.6,0)),Color3.fromRGB(42,46,55),Enum.Material.Metal,model)
	noCollision(arm)
	local color = cyan and Color3.fromRGB(90,225,255) or Color3.fromRGB(255,80,145)
	local lamp = makePart("Lamp",Vector3.new(1.2,.28,1.2),CFrame.new(pos+Vector3.new(3.4,12.5,0)),color,Enum.Material.Neon,model)
	noCollision(lamp)
	local light = Instance.new("PointLight")
	light.Brightness = 2.4
	light.Range = 38
	light.Shadows = false
	light.Color = color
	light.Parent = lamp
end

local function sign(text,pos,size,color,rotation)
	local board = makePart("Billboard",size or Vector3.new(16,5,.5),CFrame.new(pos)*CFrame.Angles(0,math.rad(rotation or 0),0),Color3.fromRGB(12,14,20),Enum.Material.Metal)
	noCollision(board)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 55
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1,1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = .35
	label.Parent = gui
	local light = Instance.new("PointLight")
	light.Brightness = 2.1
	light.Range = 25
	light.Color = color
	light.Parent = board
end

local function wreckedCar(pos,rot,color)
	local m = Instance.new("Model")
	m.Name = "WreckedCar"
	m.Parent = world
	local cf = CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
	makePart("Body",Vector3.new(6.3,1.4,10),cf*CFrame.new(0,1.2,0),color,Enum.Material.Metal,m)
	local hood = makePart("Hood",Vector3.new(5.7,.45,3),cf*CFrame.new(0,2,-3),Color3.fromRGB(28,30,35),Enum.Material.Metal,m)
	makePart("Cabin",Vector3.new(5.1,1.7,4),cf*CFrame.new(0,2.5,.2),Color3.fromRGB(25,32,40),Enum.Material.Glass,m)
	for x=-1,1,2 do
		for z=-1,1,2 do
			local w = makePart("Wheel",Vector3.new(1.45,1.45,.8),cf*CFrame.new(x*3,-.1,z*3.3)*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(15,15,18),Enum.Material.SmoothPlastic,m)
			w.Shape = Enum.PartType.Cylinder
		end
	end
	local hazard = Instance.new("PointLight")
	hazard.Brightness = 1.4
	hazard.Range = 12
	hazard.Color = Color3.fromRGB(255,75,35)
	hazard.Parent = hood
end

local function barricade(pos,rot)
	local m = Instance.new("Model")
	m.Name = "QuarantineBarricade"
	m.Parent = world
	local cf = CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
	local beam = makePart("Beam",Vector3.new(9,2.6,.8),cf*CFrame.new(0,2,0),Color3.fromRGB(65,68,75),Enum.Material.Metal,m)
	for i=-2,2 do
		neonStrip(beam.CFrame*CFrame.new(i*1.7,0,-.43),Vector3.new(.65,2.4,.08),i%2==0 and Color3.fromRGB(255,70,90) or Color3.fromRGB(255,185,55),m)
	end
	makePart("LegL",Vector3.new(.5,3,.5),cf*CFrame.new(-3.6,.5,0),Color3.fromRGB(45,48,55),Enum.Material.Metal,m)
	makePart("LegR",Vector3.new(.5,3,.5),cf*CFrame.new(3.6,.5,0),Color3.fromRGB(45,48,55),Enum.Material.Metal,m)
end

local function burningBarrel(pos)
	local barrel = makePart("BurningBarrel",Vector3.new(2.1,3,2.1),CFrame.new(pos+Vector3.new(0,1.5,0)),Color3.fromRGB(60,52,48),Enum.Material.Metal)
	barrel.Shape = Enum.PartType.Cylinder
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 4
	fire.Color = Color3.fromRGB(255,155,65)
	fire.SecondaryColor = Color3.fromRGB(255,65,20)
	fire.Parent = barrel
	local light = Instance.new("PointLight")
	light.Brightness = 2.4
	light.Range = 24
	light.Color = Color3.fromRGB(255,145,75)
	light.Parent = barrel
end

makePart("BattleDistrict",Vector3.new(520,2,520),CFrame.new(0,-1,0),Color3.fromRGB(23,25,30),Enum.Material.Asphalt)

for x=-200,200,100 do
	makePart("NorthSouthRoad",Vector3.new(30,.3,500),CFrame.new(x,.15,0),Color3.fromRGB(19,21,25),Enum.Material.Asphalt)
	neonStrip(CFrame.new(x-14.5,.35,0),Vector3.new(.22,.12,500),Color3.fromRGB(55,170,255))
	neonStrip(CFrame.new(x+14.5,.35,0),Vector3.new(.22,.12,500),Color3.fromRGB(255,55,135))
end
for z=-200,200,100 do
	makePart("EastWestRoad",Vector3.new(500,.3,30),CFrame.new(0,.18,z),Color3.fromRGB(19,21,25),Enum.Material.Asphalt)
	neonStrip(CFrame.new(0,.38,z-14.5),Vector3.new(500,.12,.22),Color3.fromRGB(255,55,135))
	neonStrip(CFrame.new(0,.38,z+14.5),Vector3.new(500,.12,.22),Color3.fromRGB(55,170,255))
end

makePart("CentralPlaza",Vector3.new(72,.7,72),CFrame.new(0,.35,0),Color3.fromRGB(38,42,50),Enum.Material.Slate)
for angle=0,315,45 do
	local rad = math.rad(angle)
	local x = math.cos(rad)*31
	local z = math.sin(rad)*31
	neonStrip(CFrame.new(x,.75,z)*CFrame.Angles(0,-rad,0),Vector3.new(10,.3,.35),angle%90==0 and Color3.fromRGB(70,225,255) or Color3.fromRGB(255,65,145))
end

sign("VIEWERS VS ME",Vector3.new(0,17,-38),Vector3.new(22,6,.6),Color3.fromRGB(75,225,255),0)
sign("QUARANTINE ZONE",Vector3.new(0,12,43),Vector3.new(20,4,.5),Color3.fromRGB(255,70,125),180)
sign("NO SAFE ZONE",Vector3.new(110,14,-95),Vector3.new(18,4,.5),Color3.fromRGB(255,185,70),45)
sign("SURVIVE",Vector3.new(-115,18,105),Vector3.new(15,5,.5),Color3.fromRGB(255,70,120),-45)

for x=-200,200,50 do
	streetLamp(Vector3.new(x,0,-17),x%100==0)
	streetLamp(Vector3.new(x,0,17),x%100~=0)
end
for z=-200,200,50 do
	local cyan = z%100==0
	streetLamp(Vector3.new(-17,0,z),cyan)
	streetLamp(Vector3.new(17,0,z),not cyan)
end

local decorated = 0
for _,obj in ipairs(oldCity:GetDescendants()) do
	if obj:IsA("BasePart") and decorated < 90 then
		local s = obj.Size
		if s.Y >= 18 and s.X >= 8 and s.Z >= 8 then
			decorated += 1
			local c = decorated%2==0 and Color3.fromRGB(65,220,255) or Color3.fromRGB(255,65,150)
			local y = obj.Position.Y + s.Y/2 + .35
			neonStrip(CFrame.new(obj.Position.X,y,obj.Position.Z),Vector3.new(math.max(3,s.X*.65),.22,.3),c)
			if decorated%3==0 then
				neonStrip(CFrame.new(obj.Position.X+s.X/2+.2,obj.Position.Y,obj.Position.Z),Vector3.new(.22,math.max(6,s.Y*.6),.3),c)
			end
		end
	end
end

local cars = {
	{Vector3.new(45,0,-8),18,Color3.fromRGB(75,80,92)},
	{Vector3.new(-54,0,10),-24,Color3.fromRGB(92,44,44)},
	{Vector3.new(95,0,28),72,Color3.fromRGB(42,60,82)},
	{Vector3.new(-105,0,-35),8,Color3.fromRGB(88,82,45)},
	{Vector3.new(24,0,106),-66,Color3.fromRGB(52,56,65)},
	{Vector3.new(150,0,-112),33,Color3.fromRGB(50,75,72)},
	{Vector3.new(-150,0,140),-17,Color3.fromRGB(72,50,70)}
}
for _,d in ipairs(cars) do wreckedCar(d[1],d[2],d[3]) end

for _,d in ipairs({
	{Vector3.new(0,0,-65),0},{Vector3.new(0,0,65),0},{Vector3.new(-65,0,0),90},
	{Vector3.new(65,0,0),90},{Vector3.new(105,0,-100),45},{Vector3.new(-105,0,100),45}
}) do barricade(d[1],d[2]) end

for _,p in ipairs({
	Vector3.new(28,0,26),Vector3.new(-30,0,40),Vector3.new(78,0,-42),Vector3.new(-75,0,-70),
	Vector3.new(15,0,112),Vector3.new(118,0,90),Vector3.new(-125,0,-95)
}) do burningBarrel(p) end

for i=1,120 do
	local size = Vector3.new(math.random(1,4),math.random(1,2),math.random(1,5))
	local p = makePart("StreetDebris",size,CFrame.new(math.random(-220,220),size.Y/2,math.random(-220,220))*CFrame.Angles(math.rad(math.random(-15,15)),math.rad(math.random(0,359)),math.rad(math.random(-15,15))),Color3.fromRGB(math.random(38,68),math.random(38,68),math.random(42,75)),Enum.Material.Concrete)
	p.CanCollide = false
end

for x=-200,200,80 do
	for z=-200,200,80 do
		local anchor = makePart("StreamFillLight",Vector3.new(.5,.5,.5),CFrame.new(x,28,z),Color3.new(1,1,1))
		anchor.Transparency = 1
		noCollision(anchor)
		local light = Instance.new("PointLight")
		light.Brightness = 1.45
		light.Range = 70
		light.Shadows = false
		light.Color = Color3.fromRGB(205,220,255)
		light.Parent = anchor
	end
end

print("CITY V6: Neon Quarantine transformation loaded. Decorated buildings:",decorated)
