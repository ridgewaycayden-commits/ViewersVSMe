-- Nuketown2025.server.lua
-- VIEWERS VS ME - Nuketown 2025 inspired gameplay map, rebuilt from original Roblox geometry.
-- V4: tighter classic layout, cleaner house silhouettes, better vehicles, proper daytime lighting.

local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local ROOT="Nuketown2025"

local function P(parent,name,size,cf,color,material,collide)
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=collide~=false;p.CanTouch=false;p.CanQuery=collide~=false
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent
	return p
end
local function W(parent,name,size,cf,color,material,collide)
	local p=Instance.new("WedgePart")
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=collide~=false;p.CanTouch=false;p.CanQuery=collide~=false;p.Parent=parent
	return p
end
local function M(parent,name)local m=Instance.new("Model");m.Name=name;m.Parent=parent;return m end
local function G(parent,name,size,cf,tint)
	local p=P(parent,name,size,cf,tint or Color3.fromRGB(42,73,86),Enum.Material.Glass,false);p.Transparency=.2;return p
end
local function TXT(p,text,color,face)
	local g=Instance.new("SurfaceGui");g.Face=face or Enum.NormalId.Front;g.PixelsPerStud=45;g.Parent=p
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Text=text;t.TextColor3=color;t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.Parent=g
end
local function cyl(parent,name,size,cf,color,material,collide)
	local p=P(parent,name,size,cf,color,material,collide);p.Shape=Enum.PartType.Cylinder;return p
end

for _,name in ipairs({ROOT,"RealMidtown","ManhattanMidtownV10","NeonQuarantineV6","CityCinematicV7","CityProductionV8"})do
	local old=workspace:FindFirstChild(name);if old then old:Destroy()end
end
local oldCity=workspace:FindFirstChild("TikTokAFKCity")or workspace:FindFirstChild("TikTokCity")
if oldCity then for _,o in ipairs(oldCity:GetDescendants())do if o:IsA("BasePart")then o.Transparency=1;o.CanCollide=false;o.CanQuery=false elseif o:IsA("Light")then o.Enabled=false end end end

local oldSpawns=workspace:FindFirstChild("NuketownZombieSpawns");if oldSpawns then oldSpawns:Destroy()end
local root=Instance.new("Folder");root.Name=ROOT;root.Parent=workspace

-- Clean BO2-style sunny test-site presentation. No legacy city-night bloom.
Lighting.ClockTime=14.1
Lighting.Brightness=2.15
Lighting.ExposureCompensation=-.05
Lighting.Ambient=Color3.fromRGB(125,130,136)
Lighting.OutdoorAmbient=Color3.fromRGB(176,180,183)
Lighting.EnvironmentDiffuseScale=.65
Lighting.EnvironmentSpecularScale=.35
Lighting.GlobalShadows=true
Lighting.ShadowSoftness=.28
local atm=Lighting:FindFirstChildOfClass("Atmosphere")or Instance.new("Atmosphere",Lighting)
atm.Density=.055;atm.Offset=.05;atm.Haze=.18;atm.Glare=0;atm.Color=Color3.fromRGB(228,222,208);atm.Decay=Color3.fromRGB(183,169,145)
local bloom=Lighting:FindFirstChildOfClass("BloomEffect")or Instance.new("BloomEffect",Lighting);bloom.Intensity=.08;bloom.Size=12;bloom.Threshold=2
local cc=Lighting:FindFirstChildOfClass("ColorCorrectionEffect")or Instance.new("ColorCorrectionEffect",Lighting);cc.Brightness=0;cc.Contrast=.05;cc.Saturation=-.04

local asphalt=Color3.fromRGB(63,64,65)
local concrete=Color3.fromRGB(200,196,183)
local lawn=Color3.fromRGB(78,132,61)
local desert=Color3.fromRGB(178,150,105)
local trim=Color3.fromRGB(225,220,203)
local dark=Color3.fromRGB(51,56,61)

-- Compact classic map footprint.
P(root,"Desert",Vector3.new(390,1,350),CFrame.new(0,-.55,0),desert,Enum.Material.Sand,true)
P(root,"Road",Vector3.new(104,.6,300),CFrame.new(0,.04,0),asphalt,Enum.Material.Asphalt,true)
local circle=P(root,"CulDeSac",Vector3.new(128,.62,128),CFrame.new(0,.07,0),asphalt,Enum.Material.Asphalt,true);circle.Shape=Enum.PartType.Cylinder;circle.Orientation=Vector3.new(0,0,90)
for _,x in ipairs({-58,58})do P(root,"Sidewalk",Vector3.new(13,.68,292),CFrame.new(x,.28,0),concrete,Enum.Material.Concrete,true)end
for _,z in ipairs({-101,101})do
	P(root,"FrontLawn",Vector3.new(156,.42,56),CFrame.new(0,.18,z),lawn,Enum.Material.Grass,true)
	P(root,"BackLawn",Vector3.new(184,.42,55),CFrame.new(0,.18,z+(z>0 and 55 or -55)),lawn,Enum.Material.Grass,true)
end
-- segmented round curb
for i=0,39 do local a=i/40*math.pi*2;local x,z=math.cos(a)*68,math.sin(a)*68;P(root,"CircleCurb",Vector3.new(10,.78,1.8),CFrame.new(x,.42,z)*CFrame.Angles(0,-a,0),concrete,Enum.Material.Concrete,true)end

local function fenceLine(parent,startPos,finishPos)
	local delta=finishPos-startPos;local len=delta.Magnitude;local count=math.max(1,math.floor(len/4))
	for i=0,count do local pos=startPos:Lerp(finishPos,i/count);P(parent,"FencePost",Vector3.new(.7,5.5,.7),CFrame.new(pos+Vector3.new(0,2.75,0)),Color3.fromRGB(211,205,184),Enum.Material.Wood,true)end
	local mid=(startPos+finishPos)/2;P(parent,"FenceRail",Vector3.new(.5,.55,len),CFrame.lookAt(mid+Vector3.new(0,1.8,0),finishPos+Vector3.new(0,1.8,0)),Color3.fromRGB(211,205,184),Enum.Material.Wood,true)
	P(parent,"FenceRail",Vector3.new(.5,.55,len),CFrame.lookAt(mid+Vector3.new(0,4.0,0),finishPos+Vector3.new(0,4.0,0)),Color3.fromRGB(211,205,184),Enum.Material.Wood,true)
end

local function frontWindow(h,cf,w,hgt)
	G(h,"FrontWindow",Vector3.new(w,hgt,.35),cf,Color3.fromRGB(47,78,91))
	P(h,"WinTop",Vector3.new(w+.6,.5,.65),cf*CFrame.new(0,hgt/2+.3,0),trim,Enum.Material.Metal,false)
	P(h,"WinBottom",Vector3.new(w+.6,.5,.65),cf*CFrame.new(0,-hgt/2-.3,0),trim,Enum.Material.Metal,false)
	P(h,"WinL",Vector3.new(.5,hgt+.6,.65),cf*CFrame.new(-w/2-.3,0,0),trim,Enum.Material.Metal,false)
	P(h,"WinR",Vector3.new(.5,hgt+.6,.65),cf*CFrame.new(w/2+.3,0,0),trim,Enum.Material.Metal,false)
end

local function buildHouse(name,z,main,accent,num,garageSide)
	local h=M(root,name)
	local d=z>0 and -1 or 1 -- direction toward center
	local front=z+d*30
	local back=z-d*30
	local gx=garageSide*50

	-- footprint / shell
	P(h,"GroundFloor",Vector3.new(72,1,58),CFrame.new(0,.5,z),Color3.fromRGB(164,153,135),Enum.Material.WoodPlanks,true)
	P(h,"RearWall",Vector3.new(72,18,2),CFrame.new(0,9,back),main,nil,true)
	P(h,"LeftWall",Vector3.new(2,18,58),CFrame.new(-35,9,z),main,nil,true)
	P(h,"RightWall",Vector3.new(2,18,58),CFrame.new(35,9,z),main,nil,true)
	-- center-facing lower facade: door + picture windows, not a blank giant wall
	P(h,"LowerBand",Vector3.new(72,4,2),CFrame.new(0,16,front),trim,nil,true)
	P(h,"FrontPierL",Vector3.new(9,14,2),CFrame.new(-31.5,7,front),main,nil,true)
	P(h,"FrontPierML",Vector3.new(6,14,2),CFrame.new(-10,7,front),main,nil,true)
	P(h,"FrontPierMR",Vector3.new(6,14,2),CFrame.new(10,7,front),main,nil,true)
	P(h,"FrontPierR",Vector3.new(9,14,2),CFrame.new(31.5,7,front),main,nil,true)
	frontWindow(h,CFrame.new(-21,8,front+d*1.05),14,8)
	frontWindow(h,CFrame.new(21,8,front+d*1.05),14,8)
	G(h,"FrontDoor",Vector3.new(11,12,.35),CFrame.new(0,6.5,front+d*1.05),Color3.fromRGB(40,69,80))
	P(h,"DoorFrame",Vector3.new(12.5,.7,.7),CFrame.new(0,13,front+d*1.1),trim,Enum.Material.Metal,false)

	-- second floor tighter and slightly cantilevered, matching the classic silhouette
	P(h,"SecondFloor",Vector3.new(72,1,58),CFrame.new(0,18.5,z),Color3.fromRGB(163,153,140),Enum.Material.WoodPlanks,true)
	P(h,"UpperRear",Vector3.new(72,17,2),CFrame.new(0,27,back),main,nil,true)
	P(h,"UpperLeft",Vector3.new(2,17,58),CFrame.new(-35,27,z),main,nil,true)
	P(h,"UpperRight",Vector3.new(2,17,58),CFrame.new(35,27,z),main,nil,true)
	P(h,"UpperFrontBandTop",Vector3.new(72,4,2),CFrame.new(0,33.5,front),main,nil,true)
	P(h,"UpperFrontBandBottom",Vector3.new(72,4,2),CFrame.new(0,20.5,front),main,nil,true)
	P(h,"UpperFrontL",Vector3.new(17,13,2),CFrame.new(-27.5,27,front),main,nil,true)
	P(h,"UpperFrontR",Vector3.new(17,13,2),CFrame.new(27.5,27,front),main,nil,true)
	frontWindow(h,CFrame.new(0,27,front+d*1.08),36,9)
	for x=-15,15,7.5 do P(h,"WindowFin",Vector3.new(1.1,12,2.5),CFrame.new(x,27,front+d*1.5),accent,nil,false)end
	-- retro horizontal trim band
	P(h,"AccentBand",Vector3.new(72,2.2,2.5),CFrame.new(0,18.8,front+d*1.5),accent,nil,false)

	-- low-pitch dark roof with actual shape instead of giant flat brick
	P(h,"RoofCenter",Vector3.new(76,1.2,16),CFrame.new(0,36.5,z),dark,Enum.Material.Slate,true)
	W(h,"RoofFront",Vector3.new(76,7,23),CFrame.new(0,36.2,z+d*19)*CFrame.Angles(0,math.pi,0),dark,Enum.Material.Slate,true)
	W(h,"RoofRear",Vector3.new(76,7,23),CFrame.new(0,36.2,z-d*19),dark,Enum.Material.Slate,true)

	-- side garage/carport, open toward center
	local g=M(h,"Garage")
	P(g,"GarageFloor",Vector3.new(31,1,42),CFrame.new(gx,.5,z+d*1),Color3.fromRGB(176,175,166),Enum.Material.Concrete,true)
	P(g,"GarageBack",Vector3.new(31,13,2),CFrame.new(gx,6.5,z-d*20),trim,nil,true)
	P(g,"GarageOuter",Vector3.new(2,13,42),CFrame.new(gx+garageSide*15,6.5,z+d*1),trim,nil,true)
	P(g,"GarageInner",Vector3.new(2,13,42),CFrame.new(gx-garageSide*15,6.5,z+d*1),trim,nil,true)
	P(g,"GarageHeader",Vector3.new(31,3,2),CFrame.new(gx,11.5,front+d*.5),trim,nil,true)
	P(g,"GarageRoof",Vector3.new(34,1.3,45),CFrame.new(gx,13.1,z+d*1),dark,Enum.Material.Slate,true)
	P(g,"GarageAccent",Vector3.new(33,1.5,2.5),CFrame.new(gx,12.1,front+d*1.2),accent,nil,false)

	-- rear deck and exterior stairs
	P(h,"RearDeck",Vector3.new(34,1,13),CFrame.new(0,18.8,back-d*7),Color3.fromRGB(166,169,165),Enum.Material.Metal,true)
	for i=0,10 do P(h,"ExteriorStep",Vector3.new(11,1,3),CFrame.new(26,i*1.55+1,back-d*(7+i*2)),Color3.fromRGB(157,160,158),Enum.Material.Metal,true)end
	P(h,"RearPatio",Vector3.new(70,.6,20),CFrame.new(0,.3,back-d*12),concrete,Enum.Material.Concrete,true)

	-- number plate
	local plate=P(h,"HouseNumber",Vector3.new(7,4,.4),CFrame.new(27,11.5,front+d*1.1),Color3.fromRGB(237,234,216),nil,false)
	TXT(plate,tostring(num),Color3.fromRGB(48,51,53),d==1 and Enum.NormalId.Back or Enum.NormalId.Front)

	-- rear fencing, with openings on side paths
	fenceLine(h,Vector3.new(-78,0,back-d*41),Vector3.new(78,0,back-d*41))
	fenceLine(h,Vector3.new(-78,0,back-d*41),Vector3.new(-78,0,back-d*6))
	fenceLine(h,Vector3.new(78,0,back-d*41),Vector3.new(78,0,back-d*6))
end

buildHouse("BlueHouse",-100,Color3.fromRGB(73,164,183),Color3.fromRGB(69,185,153),11,-1)
buildHouse("OrangeHouse",100,Color3.fromRGB(215,151,75),Color3.fromRGB(224,199,69),13,1)

-- center vehicles: more detailed silhouettes, less giant blockiness
local function wheel(parent,cf)
	local p=cyl(parent,"Wheel",Vector3.new(4.1,4.1,1.5),cf,Color3.fromRGB(22,23,24),Enum.Material.SmoothPlastic,true)
	local hub=cyl(parent,"Hub",Vector3.new(2.1,2.1,1.58),cf,Color3.fromRGB(115,118,119),Enum.Material.Metal,false);return p,hub
end

local bus=M(root,"SchoolBus")
local bcf=CFrame.new(-13,0,-8)*CFrame.Angles(0,math.rad(2),0)
P(bus,"Chassis",Vector3.new(17,2.4,58),bcf*CFrame.new(0,2.1,0),Color3.fromRGB(57,54,42),Enum.Material.Metal,true)
P(bus,"Lower",Vector3.new(17,5.2,58),bcf*CFrame.new(0,5.2,0),Color3.fromRGB(210,169,42),Enum.Material.Metal,true)
P(bus,"Upper",Vector3.new(16.2,6.5,53),bcf*CFrame.new(0,10.7,0),Color3.fromRGB(225,186,48),Enum.Material.Metal,true)
W(bus,"FrontSlope",Vector3.new(16.2,5.5,6),bcf*CFrame.new(0,9.3,-29),Color3.fromRGB(215,173,43),Enum.Material.Metal,true)
P(bus,"Rear",Vector3.new(16.2,10.5,3),bcf*CFrame.new(0,8,29.5),Color3.fromRGB(205,160,38),Enum.Material.Metal,true)
for z=-20,20,8 do for _,x in ipairs({-8.22,8.22})do G(bus,"Window",Vector3.new(.28,3.8,5.8),bcf*CFrame.new(x,11.1,z),Color3.fromRGB(43,64,69))end end
G(bus,"Windshield",Vector3.new(13.5,4,.3),bcf*CFrame.new(0,11.2,-32.1),Color3.fromRGB(42,61,65))
for _,x in ipairs({-7.7,7.7})do for _,z in ipairs({-19,19})do wheel(bus,bcf*CFrame.new(x,2.4,z)*CFrame.Angles(0,0,math.rad(90)))end end
P(bus,"FrontBumper",Vector3.new(17.8,1.2,1.5),bcf*CFrame.new(0,3.1,-32.2),Color3.fromRGB(78,79,77),Enum.Material.Metal,true)
local bs=P(bus,"Sign",Vector3.new(10,2,.3),bcf*CFrame.new(0,14.1,-32.15),Color3.fromRGB(244,205,57),nil,false);TXT(bs,"SCHOOL BUS",Color3.fromRGB(35,36,35),Enum.NormalId.Front)

local truck=M(root,"MovingTruck")
local tcf=CFrame.new(14,0,11)*CFrame.Angles(0,math.rad(-4),0)
P(truck,"Cargo",Vector3.new(18,13.5,37),tcf*CFrame.new(0,8,8),Color3.fromRGB(205,207,201),Enum.Material.Metal,true)
P(truck,"Stripe",Vector3.new(18.2,2,37.2),tcf*CFrame.new(0,8.6,8),Color3.fromRGB(67,148,163),Enum.Material.Metal,false)
P(truck,"CabLower",Vector3.new(17,5.5,15),tcf*CFrame.new(0,4.5,-18),Color3.fromRGB(172,61,49),Enum.Material.Metal,true)
W(truck,"CabHood",Vector3.new(17,6,10),tcf*CFrame.new(0,8,-21.5)*CFrame.Angles(0,math.pi,0),Color3.fromRGB(183,66,53),Enum.Material.Metal,true)
G(truck,"Windshield",Vector3.new(13.5,4,.3),tcf*CFrame.new(0,9.4,-26.6),Color3.fromRGB(43,63,68))
for _,x in ipairs({-7.6,7.6})do for _,z in ipairs({-12,17})do wheel(truck,tcf*CFrame.new(x,2.3,z)*CFrame.Angles(0,0,math.rad(90)))end end
P(truck,"RearBumper",Vector3.new(18.5,1.2,1.5),tcf*CFrame.new(0,2.8,27.2),Color3.fromRGB(86,88,87),Enum.Material.Metal,true)

-- small retro cars near each house
local function car(name,cf,color)
	local m=M(root,name)
	P(m,"Body",Vector3.new(9,2.8,18),cf*CFrame.new(0,2.1,0),color,Enum.Material.Metal,true)
	W(m,"Hood",Vector3.new(8.5,3.5,6),cf*CFrame.new(0,3.7,-6.5)*CFrame.Angles(0,math.pi,0),color,Enum.Material.Metal,true)
	G(m,"Cab",Vector3.new(7.2,3.2,7.4),cf*CFrame.new(0,4.7,1),Color3.fromRGB(46,69,74))
	for _,x in ipairs({-4.2,4.2})do for _,z in ipairs({-5.5,5.5})do wheel(m,cf*CFrame.new(x,1.6,z)*CFrame.Angles(0,0,math.rad(90)))end end
end
car("BlueFutureCar",CFrame.new(27,0,-58)*CFrame.Angles(0,math.rad(-7),0),Color3.fromRGB(72,165,170))
car("RedFutureCar",CFrame.new(-27,0,58)*CFrame.Angles(0,math.rad(7),0),Color3.fromRGB(184,77,61))

-- iconic roadside sign
P(root,"SignPost",Vector3.new(1.6,16,1.6),CFrame.new(90,8,-132),Color3.fromRGB(71,67,61),Enum.Material.Metal,true)
local sign=P(root,"NuketownSign",Vector3.new(31,11,1),CFrame.new(90,18,-132),Color3.fromRGB(190,68,54),Enum.Material.Metal,false);TXT(sign,"NUKETOWN\n2025",Color3.fromRGB(246,230,191),Enum.NormalId.Front)
local pop=P(root,"Population",Vector3.new(25,4.3,1),CFrame.new(90,9,-132),Color3.fromRGB(48,53,55),Enum.Material.Metal,false);TXT(pop,"POPULATION  00",Color3.fromRGB(104,210,194),Enum.NormalId.Front)

-- test clock tower on opposite side
local tw=M(root,"DoomsdayClock")
for _,x in ipairs({-5,5})do P(tw,"Leg",Vector3.new(1.3,39,1.3),CFrame.new(-93+x,19.5,-7)*CFrame.Angles(0,0,math.rad(x>0 and -8 or 8)),Color3.fromRGB(86,89,88),Enum.Material.Metal,true)end
for y=7,35,7 do P(tw,"Brace",Vector3.new(13,.8,.8),CFrame.new(-93,y,-7),Color3.fromRGB(86,89,88),Enum.Material.Metal,true)end
local face=P(tw,"ClockFace",Vector3.new(14,14,1),CFrame.new(-93,42,-7),Color3.fromRGB(226,220,194),nil,false);TXT(face,"11:59",Color3.fromRGB(44,45,43),Enum.NormalId.Front)

-- utility poles and simple wires
for _,z in ipairs({-122,-55,55,122})do P(root,"PowerPole",Vector3.new(1.1,25,1.1),CFrame.new(-72,12.5,z),Color3.fromRGB(88,72,55),Enum.Material.Wood,true);P(root,"Crossarm",Vector3.new(10,.65,.65),CFrame.new(-72,22,z),Color3.fromRGB(88,72,55),Enum.Material.Wood,true)end
local function wire(a,b)local d=b-a;return P(root,"Wire",Vector3.new(.12,.12,d.Magnitude),CFrame.lookAt((a+b)/2,b),Color3.fromRGB(40,40,40),Enum.Material.Metal,false)end
wire(Vector3.new(-72,22,-122),Vector3.new(-72,22,-55));wire(Vector3.new(-72,22,-55),Vector3.new(-72,22,55));wire(Vector3.new(-72,22,55),Vector3.new(-72,22,122))

-- mannequins, intentionally simple but correctly scaled
local function mannequin(x,z,rot,shirt)
	local m=M(root,"Mannequin");local cf=CFrame.new(x,0,z)*CFrame.Angles(0,math.rad(rot),0)
	P(m,"Torso",Vector3.new(1.9,2.9,1),cf*CFrame.new(0,4.2,0),shirt,nil,false)
	local h=P(m,"Head",Vector3.new(1.45,1.45,1.45),cf*CFrame.new(0,6.3,0),Color3.fromRGB(219,194,164),nil,false);h.Shape=Enum.PartType.Ball
	for _,sx in ipairs({-.52,.52})do P(m,"Leg",Vector3.new(.64,2.8,.64),cf*CFrame.new(sx,1.4,0),Color3.fromRGB(65,69,73),nil,false)end
end
for _,d in ipairs({{-66,-123,20,Color3.fromRGB(91,140,166)},{67,-119,-25,Color3.fromRGB(187,100,73)},{-69,120,150,Color3.fromRGB(145,103,160)},{66,125,205,Color3.fromRGB(91,150,103)},{-44,-44,50,Color3.fromRGB(190,148,69)},{46,46,-65,Color3.fromRGB(76,128,165)}})do mannequin(table.unpack(d))end

-- low-profile desert perimeter instead of giant rectangular rocks.
for _,v in ipairs({{-168,-135,18},{165,-132,-16},{-170,137,-20},{168,135,15}})do
	W(root,"DistantHill",Vector3.new(70,24,55),CFrame.new(v[1],11,v[2])*CFrame.Angles(0,math.rad(v[3]),0),Color3.fromRGB(147,123,92),Enum.Material.Sandstone,true)
end

-- Dedicated zombie spawn lanes around the actual playable perimeter.
local spawnFolder=Instance.new("Folder");spawnFolder.Name="NuketownZombieSpawns";spawnFolder.Parent=workspace
local markerPositions={
	Vector3.new(-35,.7,-142),Vector3.new(0,.7,-145),Vector3.new(35,.7,-142),
	Vector3.new(-76,.7,-88),Vector3.new(76,.7,-88),Vector3.new(-78,.7,-42),Vector3.new(78,.7,-42),
	Vector3.new(-78,.7,42),Vector3.new(78,.7,42),Vector3.new(-76,.7,88),Vector3.new(76,.7,88),
	Vector3.new(-35,.7,142),Vector3.new(0,.7,145),Vector3.new(35,.7,142)
}
for i,pos in ipairs(markerPositions)do local m=P(spawnFolder,"Spawn"..i,Vector3.new(4,.2,4),CFrame.new(pos),Color3.new(1,0,0),Enum.Material.SmoothPlastic,false);m.Transparency=1;m.CanQuery=false end

local spawn=Instance.new("SpawnLocation");spawn.Name="NuketownSpawn";spawn.Size=Vector3.new(10,1,10);spawn.CFrame=CFrame.new(0,1,136);spawn.Transparency=1;spawn.CanCollide=false;spawn.Anchored=true;spawn.Neutral=true;spawn.Duration=0;spawn.Parent=root
local function movePlayer(p)local hrp=p.Character and p.Character:FindFirstChild("HumanoidRootPart");if hrp then hrp.CFrame=CFrame.new(0,4,133)*CFrame.Angles(0,math.rad(180),0)end end
Players.PlayerAdded:Connect(function(p)p.CharacterAdded:Connect(function()task.wait(.4);movePlayer(p)end)end)
for _,p in ipairs(Players:GetPlayers())do if p.Character then task.defer(movePlayer,p)end;p.CharacterAdded:Connect(function()task.wait(.4);movePlayer(p)end)end

print("[NUKETOWN 2025 V4] READY - tighter classic layout + rebuilt visual pass")