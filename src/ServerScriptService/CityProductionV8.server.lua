-- CityProductionV8.server.lua
-- VIEWERS VS ME - PRODUCTION CITY V8
-- Additive final-world polish. Keeps the stable V6/V7 city and builds a denser,
-- stream-readable quarantine district on top without replacing the working map.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local old = workspace:FindFirstChild("CityProductionV8")
if old then old:Destroy() end
local world = Instance.new("Folder")
world.Name = "CityProductionV8"
world.Parent = workspace

local rng = Random.new(82926)

local function part(name,size,cf,color,material,collide,parent)
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Metal
	p.Anchored=true;p.CanCollide=collide==true;p.CanTouch=false;p.CanQuery=collide==true;p.CastShadow=true
	p.Parent=parent or world
	return p
end

local function invisibleAnchor(name,pos,parent)
	local p=part(name,Vector3.new(.2,.2,.2),CFrame.new(pos),Color3.new(1,1,1),Enum.Material.SmoothPlastic,false,parent)
	p.Transparency=1;p.CastShadow=false
	return p
end

local function point(pos,color,brightness,range,parent)
	local a=invisibleAnchor("LightAnchor",pos,parent)
	local l=Instance.new("PointLight");l.Color=color;l.Brightness=brightness;l.Range=range;l.Shadows=false;l.Parent=a
	return a,l
end

local function neon(name,size,cf,color,parent)
	local p=part(name,size,cf,color,Enum.Material.Neon,false,parent);p.CastShadow=false
	return p
end

local function surfaceText(board,text,color,face)
	local gui=Instance.new("SurfaceGui");gui.Face=face or Enum.NormalId.Front;gui.LightInfluence=0;gui.PixelsPerStud=45;gui.Parent=board
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.TextColor3=color;t.TextStrokeTransparency=.2;t.Text=text;t.Parent=gui
end

-- Final lighting grade: still bright enough for a phone stream.
Lighting.ClockTime=21.4
Lighting.Brightness=3.55
Lighting.ExposureCompensation=.72
Lighting.Ambient=Color3.fromRGB(72,80,105)
Lighting.OutdoorAmbient=Color3.fromRGB(102,112,142)
Lighting.ShadowSoftness=.18
Lighting.EnvironmentDiffuseScale=.68
Lighting.EnvironmentSpecularScale=1

local bloom=Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect",Lighting)
bloom.Intensity=1.15;bloom.Size=38;bloom.Threshold=.82
local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect",Lighting)
cc.Brightness=.055;cc.Contrast=.23;cc.Saturation=.08;cc.TintColor=Color3.fromRGB(225,232,255)
local atm=Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere",Lighting)
atm.Density=.18;atm.Haze=1.05;atm.Glare=.08;atm.Color=Color3.fromRGB(176,190,225);atm.Decay=Color3.fromRGB(66,75,112)

-- Wet road puddles/reflections. Thin, non-queryable parts do not interfere with AI LOS/pathing.
for i=1,58 do
	local onNS=i%2==0
	local roadLine=({-200,-100,0,100,200})[rng:NextInteger(1,5)]
	local x,z
	if onNS then x=roadLine+rng:NextNumber(-10,10);z=rng:NextNumber(-225,225) else x=rng:NextNumber(-225,225);z=roadLine+rng:NextNumber(-10,10) end
	local sx=rng:NextNumber(3,10);local sz=rng:NextNumber(2,7)
	local p=part("RainPuddle",Vector3.new(sx,.025,sz),CFrame.new(x,.34,z)*CFrame.Angles(0,rng:NextNumber(0,math.pi),0),Color3.fromRGB(34,42,56),Enum.Material.Glass,false)
	p.Transparency=.38;p.Reflectance=.18;p.CastShadow=false
end

-- Proper lane markings and broken crosswalks.
for _,x in ipairs({-200,-100,0,100,200}) do
	for z=-220,220,22 do
		neon("RoadDash",Vector3.new(.18,.035,7),CFrame.new(x,.38,z),Color3.fromRGB(225,207,142))
	end
end
for _,z in ipairs({-200,-100,0,100,200}) do
	for x=-220,220,22 do
		neon("RoadDash",Vector3.new(7,.035,.18),CFrame.new(x,.39,z),Color3.fromRGB(225,207,142))
	end
end
for _,p in ipairs({Vector3.new(0,.4,36),Vector3.new(0,.4,-36),Vector3.new(36,.4,0),Vector3.new(-36,.4,0)}) do
	for i=-4,4 do
		local horizontal=math.abs(p.X)>1
		local cf=horizontal and CFrame.new(p.X,p.Y,p.Z+i*2.15) or CFrame.new(p.X+i*2.15,p.Y,p.Z)
		part("CrosswalkStripe",horizontal and Vector3.new(5,.025,1.1) or Vector3.new(1.1,.025,5),cf,Color3.fromRGB(178,184,194),Enum.Material.Concrete,false)
	end
end

local function trafficLight(pos,rot)
	local m=Instance.new("Model");m.Name="DeadTrafficLight";m.Parent=world
	local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
	part("Pole",Vector3.new(.65,12,.65),cf*CFrame.new(0,6,0),Color3.fromRGB(37,41,47),Enum.Material.Metal,true,m)
	part("Arm",Vector3.new(8,.42,.42),cf*CFrame.new(3.6,11.2,0),Color3.fromRGB(37,41,47),Enum.Material.Metal,false,m)
	local box=part("Signal",Vector3.new(1.45,3.7,1.15),cf*CFrame.new(7.05,9.8,0),Color3.fromRGB(18,20,24),Enum.Material.Metal,false,m)
	for i,c in ipairs({Color3.fromRGB(255,45,55),Color3.fromRGB(255,178,45),Color3.fromRGB(62,220,100)}) do
		local lamp=neon("SignalLamp",Vector3.new(.66,.66,.12),box.CFrame*CFrame.new(0,1.05-(i-1)*1.05,-.64),c,m)
		lamp.Transparency=i==1 and .08 or .78
	end
end
trafficLight(Vector3.new(-30,0,-30),0);trafficLight(Vector3.new(30,0,30),180);trafficLight(Vector3.new(-30,0,30),90);trafficLight(Vector3.new(30,0,-30),-90)

local function dumpster(pos,rot)
	local m=Instance.new("Model");m.Name="AlleyDumpster";m.Parent=world
	local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
	part("Bin",Vector3.new(4.6,3.1,2.8),cf*CFrame.new(0,1.55,0),Color3.fromRGB(37,58,53),Enum.Material.Metal,true,m)
	part("Lid",Vector3.new(4.8,.22,3),cf*CFrame.new(0,3.2,-.15)*CFrame.Angles(math.rad(-8),0,0),Color3.fromRGB(28,37,36),Enum.Material.Metal,false,m)
	for x=-1,1,2 do part("Wheel",Vector3.new(.55,.55,.45),cf*CFrame.new(x*1.65,.35,1.08)*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(12,13,15),Enum.Material.SmoothPlastic,false,m).Shape=Enum.PartType.Cylinder end
end
for _,d in ipairs({{Vector3.new(72,0,58),20},{Vector3.new(-72,0,62),-35},{Vector3.new(132,0,-65),75},{Vector3.new(-136,0,-62),-78},{Vector3.new(58,0,-142),10},{Vector3.new(-62,0,145),170}}) do dumpster(d[1],d[2]) end

-- Rooftop silhouettes: water tanks, antennas, HVAC, satellite dishes.
local roofPositions={Vector3.new(-145,36,-145),Vector3.new(145,39,-145),Vector3.new(-145,42,145),Vector3.new(145,37,145),Vector3.new(-48,34,150),Vector3.new(52,40,-150)}
for i,pos in ipairs(roofPositions) do
	local m=Instance.new("Model");m.Name="RooftopUtility";m.Parent=world
	local tank=part("WaterTank",Vector3.new(7,7,7),CFrame.new(pos),Color3.fromRGB(45,49,57),Enum.Material.Metal,false,m);tank.Shape=Enum.PartType.Cylinder
	part("TankStand",Vector3.new(5,.4,5),CFrame.new(pos-Vector3.new(0,4.1,0)),Color3.fromRGB(31,34,40),Enum.Material.Metal,false,m)
	local mast=part("Antenna",Vector3.new(.25,11,.25),CFrame.new(pos+Vector3.new(5,5,0)),Color3.fromRGB(65,70,80),Enum.Material.Metal,false,m)
	local beacon=neon("AntennaBeacon",Vector3.new(.65,.65,.65),mast.CFrame*CFrame.new(0,5.7,0),Color3.fromRGB(255,45,55),m);beacon.Shape=Enum.PartType.Ball
	local light=Instance.new("PointLight");light.Color=beacon.Color;light.Range=18;light.Brightness=1.5;light.Parent=beacon
	task.spawn(function() while beacon.Parent do beacon.Transparency=.05;light.Enabled=true;task.wait(.22);beacon.Transparency=.7;light.Enabled=false;task.wait(.72) end end)
end

-- Quarantine checkpoint at the main northern approach.
local checkpoint=Instance.new("Model");checkpoint.Name="MainQuarantineCheckpoint";checkpoint.Parent=world
for _,x in ipairs({-13,13}) do
	part("CheckpointTower",Vector3.new(5,18,5),CFrame.new(x,9,-72),Color3.fromRGB(42,46,53),Enum.Material.DiamondPlate,true,checkpoint)
	local lamp=neon("WarningLamp",Vector3.new(2,.4,2),CFrame.new(x,18.3,-72),x<0 and Color3.fromRGB(255,55,65) or Color3.fromRGB(55,170,255),checkpoint)
	local l=Instance.new("PointLight");l.Color=lamp.Color;l.Brightness=3;l.Range=34;l.Parent=lamp
end
part("CheckpointBridge",Vector3.new(31,2.4,3.2),CFrame.new(0,17,-72),Color3.fromRGB(40,43,49),Enum.Material.Metal,true,checkpoint)
local checkpointSign=part("CheckpointSign",Vector3.new(20,4,.35),CFrame.new(0,13.8,-70.2),Color3.fromRGB(12,14,18),Enum.Material.Metal,false,checkpoint)
surfaceText(checkpointSign,"QUARANTINE // LOCKDOWN",Color3.fromRGB(255,70,75),Enum.NormalId.Front)
for x=-10,10,5 do
	part("ConcreteBlock",Vector3.new(3.8,2.7,4),CFrame.new(x,1.35,-62+rng:NextNumber(-1.5,1.5))*CFrame.Angles(0,math.rad(rng:NextNumber(-18,18)),0),Color3.fromRGB(78,80,84),Enum.Material.Concrete,true,checkpoint)
end

-- Central boss arena re-dress.
local arena=Instance.new("Folder");arena.Name="TitanArenaDress";arena.Parent=world
for a=0,315,45 do
	local r=33;local rad=math.rad(a);local pos=Vector3.new(math.cos(rad)*r,1.1,math.sin(rad)*r)
	local pillar=part("ArenaPylon",Vector3.new(2.2,5.2,2.2),CFrame.new(pos),Color3.fromRGB(28,31,38),Enum.Material.Metal,true,arena)
	local core=neon("ArenaPylonCore",Vector3.new(.65,3.4,.65),pillar.CFrame, a%90==0 and Color3.fromRGB(70,225,255) or Color3.fromRGB(255,55,80),arena)
	local l=Instance.new("PointLight");l.Color=core.Color;l.Brightness=2.4;l.Range=22;l.Parent=core
end
local centerRing=part("TitanSeal",Vector3.new(.08,24,24),CFrame.new(0,.58,0)*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(255,45,60),Enum.Material.Neon,false,arena);centerRing.Shape=Enum.PartType.Cylinder;centerRing.Transparency=.68;centerRing.CastShadow=false

-- Storefront signs / holographic city identity.
local signs={
	{"24H MEDICAL",Vector3.new(88,9,-115),25,Color3.fromRGB(80,255,170)},
	{"EVAC ROUTE CLOSED",Vector3.new(-94,11,-112),-22,Color3.fromRGB(255,70,70)},
	{"SECTOR 07",Vector3.new(112,14,88),155,Color3.fromRGB(75,210,255)},
	{"STAY INSIDE",Vector3.new(-118,12,94),-155,Color3.fromRGB(255,175,55)},
	{"VIEWERS ARE WATCHING",Vector3.new(0,28,156),180,Color3.fromRGB(255,65,150)},
}
for _,s in ipairs(signs) do
	local board=part("StorefrontSign",Vector3.new(18,3.8,.3),CFrame.new(s[2])*CFrame.Angles(0,math.rad(s[3]),0),Color3.fromRGB(10,12,17),Enum.Material.Metal,false)
	surfaceText(board,s[1],s[4])
	local l=Instance.new("PointLight");l.Color=s[4];l.Brightness=1.7;l.Range=23;l.Parent=board
end

-- Broken fencing / alley clutter kept outside the main player lanes.
for i=1,34 do
	local side=rng:NextInteger(1,4);local x,z,rot
	if side==1 then x=rng:NextNumber(-210,210);z=235;rot=0 elseif side==2 then x=rng:NextNumber(-210,210);z=-235;rot=0 elseif side==3 then x=235;z=rng:NextNumber(-210,210);rot=90 else x=-235;z=rng:NextNumber(-210,210);rot=90 end
	local fence=part("BrokenFence",Vector3.new(rng:NextNumber(5,11),4,.18),CFrame.new(x,2,z)*CFrame.Angles(math.rad(rng:NextNumber(-5,5)),math.rad(rot),math.rad(rng:NextNumber(-12,12))),Color3.fromRGB(67,70,75),Enum.Material.DiamondPlate,false)
	fence.Transparency=.12
end

-- Sparks and electrical failures.
for _,pos in ipairs({Vector3.new(44,5,-42),Vector3.new(-48,7,52),Vector3.new(104,6,-92),Vector3.new(-112,5,-105),Vector3.new(92,8,118)}) do
	local a=invisibleAnchor("ElectricalFault",pos)
	local e=Instance.new("ParticleEmitter");e.Rate=0;e.Lifetime=NumberRange.new(.18,.42);e.Speed=NumberRange.new(8,19);e.SpreadAngle=Vector2.new(35,35);e.Acceleration=Vector3.new(0,-24,0);e.Color=ColorSequence.new(Color3.fromRGB(180,225,255),Color3.fromRGB(255,170,55));e.LightEmission=1;e.Size=NumberSequence.new(.09);e.Parent=a
	task.spawn(function() while a.Parent do task.wait(rng:NextNumber(2.2,6));e:Emit(rng:NextInteger(7,15)) end end)
end

-- Low-cost drifting ash to give depth without replacing the existing rain.
local ash=invisibleAnchor("AshField",Vector3.new(0,35,0))
local ae=Instance.new("ParticleEmitter");ae.Rate=42;ae.Lifetime=NumberRange.new(7,11);ae.Speed=NumberRange.new(2,5);ae.Acceleration=Vector3.new(.4,-.7,.1);ae.SpreadAngle=Vector2.new(180,180);ae.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,.16)});ae.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.35),NumberSequenceKeypoint.new(1,1)});ae.Color=ColorSequence.new(Color3.fromRGB(180,185,195));ae.EmissionDirection=Enum.NormalId.Bottom;ae.Shape=Enum.ParticleEmitterShape.Box;ae.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume;ae.Parent=ash

-- Slowly pulse the center seal and checkpoint lights for life without expensive per-frame loops.
task.spawn(function()
	while centerRing.Parent do
		TweenService:Create(centerRing,TweenInfo.new(1.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=.35}):Play();task.wait(1.4)
		TweenService:Create(centerRing,TweenInfo.new(1.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Transparency=.72}):Play();task.wait(1.4)
	end
end)

print("CITY PRODUCTION V8 READY - wet streets, checkpoint, rooftop skyline, arena, storefronts, clutter, sparks, ash.")
