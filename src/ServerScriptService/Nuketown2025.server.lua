-- Nuketown2025.server.lua
-- VIEWERS VS ME - Nuketown 2025 inspired gameplay map, built from original Roblox geometry.

local Players=game:GetService("Players")
local Lighting=game:GetService("Lighting")
local ROOT="Nuketown2025"

local function part(parent,name,size,cf,color,material,collide)
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic
	p.Anchored=true;p.CanCollide=collide~=false;p.CanTouch=false;p.CanQuery=collide~=false
	p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth;p.Parent=parent
	return p
end

local function model(parent,name)local m=Instance.new("Model");m.Name=name;m.Parent=parent;return m end
local function textFace(p,text,color,face)
	local g=Instance.new("SurfaceGui");g.Face=face or Enum.NormalId.Front;g.PixelsPerStud=50;g.Parent=p
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Text=text;t.TextColor3=color;t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.Parent=g
end
local function glass(parent,name,size,cf)
	local p=part(parent,name,size,cf,Color3.fromRGB(40,73,88),Enum.Material.Glass,false);p.Transparency=.22;return p
end

for _,name in ipairs({ROOT,"RealMidtown","ManhattanMidtownV10","NeonQuarantineV6","CityCinematicV7","CityProductionV8"}) do
	local old=workspace:FindFirstChild(name);if old then old:Destroy() end
end
local oldCity=workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")
if oldCity then
	for _,o in ipairs(oldCity:GetDescendants()) do
		if o:IsA("BasePart") then o.Transparency=1;o.CanCollide=false;o.CanQuery=false elseif o:IsA("Light") then o.Enabled=false end
	end
end

local root=Instance.new("Folder");root.Name=ROOT;root.Parent=workspace

Lighting.ClockTime=13.15;Lighting.Brightness=2.8;Lighting.ExposureCompensation=.05
Lighting.Ambient=Color3.fromRGB(125,135,145);Lighting.OutdoorAmbient=Color3.fromRGB(175,185,195)
local atm=Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere",Lighting)
atm.Density=.12;atm.Haze=.45;atm.Color=Color3.fromRGB(214,229,245);atm.Decay=Color3.fromRGB(183,202,223)

-- test-site desert and central neighborhood
part(root,"Desert",Vector3.new(520,1,440),CFrame.new(0,-.55,0),Color3.fromRGB(184,157,111),Enum.Material.Sand,true)
part(root,"Road",Vector3.new(112,.6,340),CFrame.new(0,.05,0),Color3.fromRGB(57,59,61),Enum.Material.Asphalt,true)
local circle=part(root,"CulDeSac",Vector3.new(142,.62,142),CFrame.new(0,.08,0),Color3.fromRGB(57,59,61),Enum.Material.Asphalt,true)
circle.Shape=Enum.PartType.Cylinder;circle.Orientation=Vector3.new(0,0,90)
for _,x in ipairs({-63,63}) do part(root,"Sidewalk",Vector3.new(14,.7,322),CFrame.new(x,.28,0),Color3.fromRGB(213,211,202),Enum.Material.Concrete,true) end
for _,z in ipairs({-103,103}) do part(root,"FrontLawn",Vector3.new(172,.45,78),CFrame.new(0,.18,z),Color3.fromRGB(78,143,66),Enum.Material.Grass,true) end

-- curb pieces around the central circle give the street the recognizable test-suburb look
for i=0,31 do
	local a=(i/32)*math.pi*2
	local x,z=math.cos(a)*74,math.sin(a)*74
	part(root,"CircleCurb",Vector3.new(11,.8,2),CFrame.new(x,.42,z)*CFrame.Angles(0,-a,0),Color3.fromRGB(213,211,202),Enum.Material.Concrete,true)
end

local function buildHouse(name,z,main,accent,number,garageSide)
	local h=model(root,name)
	local towardCenter=z>0 and -1 or 1
	local front=z+towardCenter*34
	local back=z-towardCenter*34
	local left=-38;local right=38

	-- floors with a real stair opening instead of one solid slab
	part(h,"GroundFloor",Vector3.new(78,1,68),CFrame.new(0,.5,z),Color3.fromRGB(188,181,165),Enum.Material.WoodPlanks,true)
	part(h,"UpperFloorL",Vector3.new(31,1,68),CFrame.new(-23.5,20.5,z),Color3.fromRGB(178,171,158),Enum.Material.WoodPlanks,true)
	part(h,"UpperFloorR",Vector3.new(31,1,68),CFrame.new(23.5,20.5,z),Color3.fromRGB(178,171,158),Enum.Material.WoodPlanks,true)
	part(h,"UpperFloorBridge",Vector3.new(16,1,28),CFrame.new(0,20.5,z-towardCenter*20),Color3.fromRGB(178,171,158),Enum.Material.WoodPlanks,true)

	-- ground shell, intentionally split around front door and windows
	part(h,"BackWall",Vector3.new(78,20,2),CFrame.new(0,10,back),main,nil,true)
	part(h,"LeftWall",Vector3.new(2,20,68),CFrame.new(left,10,z),main,nil,true)
	part(h,"RightWall",Vector3.new(2,20,68),CFrame.new(right,10,z),main,nil,true)
	part(h,"FrontLeft",Vector3.new(27,20,2),CFrame.new(-25.5,10,front),main,nil,true)
	part(h,"FrontRight",Vector3.new(27,20,2),CFrame.new(25.5,10,front),main,nil,true)
	part(h,"DoorHeader",Vector3.new(24,5,2),CFrame.new(0,17.5,front),main,nil,true)
	part(h,"DoorL",Vector3.new(6,15,2),CFrame.new(-9,7.5,front),main,nil,true)
	part(h,"DoorR",Vector3.new(6,15,2),CFrame.new(9,7.5,front),main,nil,true)
	glass(h,"FrontDoorGlass",Vector3.new(11,11,.45),CFrame.new(0,8,front+towardCenter*1.1))

	-- upper shell and iconic wide bedroom window
	part(h,"UpperBack",Vector3.new(78,18,2),CFrame.new(0,29,back),main,nil,true)
	part(h,"UpperLeftSide",Vector3.new(2,18,68),CFrame.new(left,29,z),main,nil,true)
	part(h,"UpperRightSide",Vector3.new(2,18,68),CFrame.new(right,29,z),main,nil,true)
	part(h,"UpperFrontLeft",Vector3.new(23,18,2),CFrame.new(-27.5,29,front),main,nil,true)
	part(h,"UpperFrontRight",Vector3.new(23,18,2),CFrame.new(27.5,29,front),main,nil,true)
	part(h,"UpperWindowHeader",Vector3.new(32,4,2),CFrame.new(0,36,front),main,nil,true)
	part(h,"UpperWindowSill",Vector3.new(32,4,2),CFrame.new(0,22,front),main,nil,true)
	glass(h,"BedroomWindow",Vector3.new(31,10,.45),CFrame.new(0,29,front+towardCenter*1.15))
	for x=-12,12,8 do part(h,"WindowMullion",Vector3.new(.45,10,.7),CFrame.new(x,29,front+towardCenter*1.3),accent,Enum.Material.Metal,false) end

	-- mid-century roof slab and colored fins
	part(h,"Roof",Vector3.new(86,2.4,75),CFrame.new(0,39.2,z),Color3.fromRGB(48,55,65),Enum.Material.Slate,true)
	part(h,"RoofLip",Vector3.new(88,1,5),CFrame.new(0,38.2,front+towardCenter*2),accent,nil,false)
	for x=-33,33,11 do part(h,"FacadeFin",Vector3.new(2.1,17,3),CFrame.new(x,29,front+towardCenter*2.2),accent,nil,false) end

	-- interior stairs visible from center opening
	for i=0,10 do
		part(h,"InteriorStep",Vector3.new(14,1.25,3.2),CFrame.new(-15,i*1.72+1.1,z-towardCenter*(14-i*2.2)),Color3.fromRGB(127,112,94),Enum.Material.WoodPlanks,true)
	end

	-- garage as an actual room with center-facing opening
	local gx=garageSide*61
	local g=model(h,"Garage")
	part(g,"GarageFloor",Vector3.new(38,1,48),CFrame.new(gx,.5,z-towardCenter*2),Color3.fromRGB(177,177,169),Enum.Material.Concrete,true)
	part(g,"GarageBack",Vector3.new(38,15,2),CFrame.new(gx,7.5,z-towardCenter*26),Color3.fromRGB(222,218,203),nil,true)
	part(g,"GarageOuter",Vector3.new(2,15,48),CFrame.new(gx+garageSide*19,7.5,z-towardCenter*2),Color3.fromRGB(222,218,203),nil,true)
	part(g,"GarageInner",Vector3.new(2,15,48),CFrame.new(gx-garageSide*19,7.5,z-towardCenter*2),Color3.fromRGB(222,218,203),nil,true)
	part(g,"GarageHeader",Vector3.new(38,4,2),CFrame.new(gx,13,front+towardCenter*1),Color3.fromRGB(222,218,203),nil,true)
	part(g,"GarageRoof",Vector3.new(42,1.6,52),CFrame.new(gx,15.5,z-towardCenter*2),Color3.fromRGB(58,63,67),Enum.Material.Metal,true)

	-- rear patio/balcony and exterior stair
	part(h,"RearPatio",Vector3.new(74,.7,28),CFrame.new(0,.35,back-towardCenter*15),Color3.fromRGB(206,197,181),Enum.Material.Concrete,true)
	part(h,"RearBalcony",Vector3.new(31,1,15),CFrame.new(0,21,back-towardCenter*8),Color3.fromRGB(186,190,187),Enum.Material.Metal,true)
	for i=0,10 do part(h,"ExteriorStep",Vector3.new(13,1.15,3.1),CFrame.new(28,i*1.65+1,back-towardCenter*(9+i*2)),Color3.fromRGB(161,164,159),Enum.Material.Metal,true) end

	-- house number plate
	local plate=part(h,"HouseNumber",Vector3.new(8,5,.45),CFrame.new(25,13,front+towardCenter*1.15),Color3.fromRGB(241,239,221),nil,false)
	textFace(plate,tostring(number),Color3.fromRGB(43,47,49),towardCenter==1 and Enum.NormalId.Back or Enum.NormalId.Front)

	-- backyard fencing
	part(h,"RearFence",Vector3.new(188,7,1),CFrame.new(0,3.5,back-towardCenter*45),Color3.fromRGB(225,220,200),Enum.Material.Wood,true)
	for _,x in ipairs({-94,94}) do part(h,"SideFence",Vector3.new(1,7,86),CFrame.new(x,3.5,back-towardCenter*3),Color3.fromRGB(225,220,200),Enum.Material.Wood,true) end
end

buildHouse("BlueHouse",-106,Color3.fromRGB(44,183,218),Color3.fromRGB(45,224,180),11,-1)
buildHouse("OrangeHouse",106,Color3.fromRGB(239,174,76),Color3.fromRGB(245,230,70),13,1)

local function wheel(parent,cf)
	local p=part(parent,"Wheel",Vector3.new(4.2,4.2,1.6),cf,Color3.fromRGB(23,24,26),Enum.Material.SmoothPlastic,true)
	p.Shape=Enum.PartType.Cylinder;return p
end

-- recognizable center bus
local bus=model(root,"SchoolBus")
local bcf=CFrame.new(-15,0,-5)*CFrame.Angles(0,math.rad(5),0)
part(bus,"BusLower",Vector3.new(18,6.5,62),bcf*CFrame.new(0,4.3,0),Color3.fromRGB(232,189,43),Enum.Material.Metal,true)
part(bus,"BusUpper",Vector3.new(17,7.5,58),bcf*CFrame.new(0,11.2,0),Color3.fromRGB(241,204,52),Enum.Material.Metal,true)
part(bus,"FrontCap",Vector3.new(17,11,4),bcf*CFrame.new(0,8,-31),Color3.fromRGB(221,174,34),Enum.Material.Metal,true)
part(bus,"RearCap",Vector3.new(17,11,4),bcf*CFrame.new(0,8,31),Color3.fromRGB(221,174,34),Enum.Material.Metal,true)
for z=-22,22,8.8 do for _,x in ipairs({-8.65,8.65}) do glass(bus,"BusWindow",Vector3.new(.35,4.4,6.7),bcf*CFrame.new(x,11.5,z)) end end
for _,x in ipairs({-7.7,7.7}) do for _,z in ipairs({-20,20}) do wheel(bus,bcf*CFrame.new(x,2.3,z)*CFrame.Angles(0,0,math.rad(90))) end end
local busSign=part(bus,"SchoolBusSign",Vector3.new(11,2.2,.4),bcf*CFrame.new(0,14.5,-33.05),Color3.fromRGB(255,219,70),nil,false);textFace(busSign,"SCHOOL BUS",Color3.fromRGB(40,40,35),Enum.NormalId.Front)

-- moving truck opposite the bus
local truck=model(root,"MovingTruck")
local tcf=CFrame.new(19,0,10)*CFrame.Angles(0,math.rad(-8),0)
part(truck,"Cargo",Vector3.new(19,15,42),tcf*CFrame.new(0,8.2,8),Color3.fromRGB(221,221,211),Enum.Material.Metal,true)
part(truck,"CargoStripe",Vector3.new(19.2,2.3,42.2),tcf*CFrame.new(0,8.3,8),Color3.fromRGB(62,157,171),Enum.Material.Metal,false)
part(truck,"Cab",Vector3.new(18,11.5,17),tcf*CFrame.new(0,6,-21),Color3.fromRGB(190,66,51),Enum.Material.Metal,true)
glass(truck,"Windshield",Vector3.new(14,.4,5.5),tcf*CFrame.new(0,9.5,-29.55)*CFrame.Angles(math.rad(90),0,0))
for _,x in ipairs({-8.1,8.1}) do for _,z in ipairs({-13,18}) do wheel(truck,tcf*CFrame.new(x,2.3,z)*CFrame.Angles(0,0,math.rad(90))) end end

-- retro cars
local function car(name,cf,color)
	local m=model(root,name);part(m,"Body",Vector3.new(10,3,20),cf*CFrame.new(0,2,0),color,Enum.Material.Metal,true)
	glass(m,"Cabin",Vector3.new(8,3.2,10),cf*CFrame.new(0,4.4,0));
	for _,x in ipairs({-4.8,4.8}) do for _,z in ipairs({-6,6}) do wheel(m,cf*CFrame.new(x,1.6,z)*CFrame.Angles(0,0,math.rad(90))) end end
end
car("BlueFutureCar",CFrame.new(29,0,-65)*CFrame.Angles(0,math.rad(-8),0),Color3.fromRGB(72,194,197))
car("RedFutureCar",CFrame.new(-31,0,66)*CFrame.Angles(0,math.rad(8),0),Color3.fromRGB(211,88,63))

-- Nuketown sign and population counter
part(root,"SignPost",Vector3.new(2,19,2),CFrame.new(92,9.5,-136),Color3.fromRGB(79,72,61),Enum.Material.Metal,true)
local sign=part(root,"NuketownSign",Vector3.new(34,13,1.2),CFrame.new(92,20,-136),Color3.fromRGB(207,72,55),Enum.Material.Metal,false)
textFace(sign,"NUKETOWN\n2025",Color3.fromRGB(255,238,196),Enum.NormalId.Front)
local pop=part(root,"Population",Vector3.new(28,5.2,1.25),CFrame.new(92,10.2,-136),Color3.fromRGB(47,54,57),Enum.Material.Metal,false)
textFace(pop,"POPULATION  00",Color3.fromRGB(100,232,213),Enum.NormalId.Front)

-- doomsday clock tower
local tower=model(root,"DoomsdayClock")
for _,x in ipairs({-6,6}) do part(tower,"Leg",Vector3.new(1.5,48,1.5),CFrame.new(-110+x,24,-16)*CFrame.Angles(0,0,math.rad(x>0 and -8 or 8)),Color3.fromRGB(92,96,95),Enum.Material.Metal,true) end
for y=8,44,8 do part(tower,"Brace",Vector3.new(15,.9,.9),CFrame.new(-110,y,-16),Color3.fromRGB(92,96,95),Enum.Material.Metal,true) end
local clock=part(tower,"ClockFace",Vector3.new(17,17,1.4),CFrame.new(-110,52,-16),Color3.fromRGB(235,228,201),nil,false);textFace(clock,"11:59",Color3.fromRGB(45,47,45),Enum.NormalId.Front)

-- poles + wires
local polePositions={{-84,-124},{-84,-52},{-84,52},{-84,124},{84,-124},{84,124}}
for _,v in ipairs(polePositions) do
	part(root,"PowerPole",Vector3.new(1.3,28,1.3),CFrame.new(v[1],14,v[2]),Color3.fromRGB(92,75,56),Enum.Material.Wood,true)
	part(root,"Crossarm",Vector3.new(12,.8,.8),CFrame.new(v[1],25,v[2]),Color3.fromRGB(92,75,56),Enum.Material.Wood,true)
end
local function wire(a,b)
	local d=b-a;local p=part(root,"PowerLine",Vector3.new(.18,.18,d.Magnitude),CFrame.lookAt((a+b)/2,b),Color3.fromRGB(38,38,38),Enum.Material.Metal,false);return p
end
wire(Vector3.new(-84,25,-124),Vector3.new(-84,25,-52));wire(Vector3.new(-84,25,-52),Vector3.new(-84,25,52));wire(Vector3.new(-84,25,52),Vector3.new(-84,25,124))

-- mannequins
local function mannequin(x,z,rot,shirt)
	local m=model(root,"Mannequin");local cf=CFrame.new(x,0,z)*CFrame.Angles(0,math.rad(rot),0)
	part(m,"Torso",Vector3.new(2.2,3.2,1.2),cf*CFrame.new(0,4.6,0),shirt,nil,false)
	local head=part(m,"Head",Vector3.new(1.7,1.7,1.7),cf*CFrame.new(0,7,0),Color3.fromRGB(223,195,162),nil,false);head.Shape=Enum.PartType.Ball
	for _,sx in ipairs({-.62,.62}) do part(m,"Leg",Vector3.new(.76,3.1,.76),cf*CFrame.new(sx,1.55,0),Color3.fromRGB(59,64,71),nil,false) end
end
for _,d in ipairs({{-74,-131,20,Color3.fromRGB(82,153,189)},{73,-122,-25,Color3.fromRGB(214,108,75)},{-77,128,150,Color3.fromRGB(163,101,177)},{72,132,205,Color3.fromRGB(91,168,111)},{-44,-48,50,Color3.fromRGB(222,168,72)},{48,51,-65,Color3.fromRGB(77,145,189)}}) do mannequin(table.unpack(d)) end

-- distant test-site walls/mountains so the map does not fall off into empty baseplate
for _,v in ipairs({{-210,0,-150},{205,0,-145},{-205,0,155},{210,0,150}}) do
	part(root,"DistantRock",Vector3.new(95,38,44),CFrame.new(v[1],18,v[3])*CFrame.Angles(0,math.rad(v[1]>0 and 18 or -18),math.rad(8)),Color3.fromRGB(152,128,97),Enum.Material.Sandstone,true)
end

-- Dedicated spawn markers. Zombie core V3.3 reads these and chooses a marker 30-105 studs from the host.
local spawnFolder=Instance.new("Folder");spawnFolder.Name="NuketownZombieSpawns";spawnFolder.Parent=workspace
local markerPositions={
	Vector3.new(-42,.7,-145),Vector3.new(0,.7,-150),Vector3.new(42,.7,-145),
	Vector3.new(-76,.7,-82),Vector3.new(76,.7,-82),Vector3.new(-78,.7,-38),Vector3.new(78,.7,-38),
	Vector3.new(-78,.7,38),Vector3.new(78,.7,38),Vector3.new(-76,.7,82),Vector3.new(76,.7,82),
	Vector3.new(-42,.7,145),Vector3.new(0,.7,150),Vector3.new(42,.7,145)
}
for i,pos in ipairs(markerPositions) do
	local m=part(spawnFolder,"Spawn"..i,Vector3.new(5,.25,5),CFrame.new(pos),Color3.new(1,0,0),Enum.Material.SmoothPlastic,false)
	m.Transparency=1;m.CanQuery=false
end

local spawn=Instance.new("SpawnLocation");spawn.Name="NuketownSpawn";spawn.Size=Vector3.new(12,1,12);spawn.CFrame=CFrame.new(0,1,146);spawn.Transparency=1;spawn.CanCollide=false;spawn.Anchored=true;spawn.Neutral=true;spawn.Duration=0;spawn.Parent=root
local function movePlayer(p)
	local hrp=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame=CFrame.new(0,4,143)*CFrame.Angles(0,math.rad(180),0) end
end
Players.PlayerAdded:Connect(function(p)p.CharacterAdded:Connect(function()task.wait(.45);movePlayer(p)end)end)
for _,p in ipairs(Players:GetPlayers()) do if p.Character then task.defer(movePlayer,p) end;p.CharacterAdded:Connect(function()task.wait(.45);movePlayer(p)end) end

print("[NUKETOWN 2025 V3] READY - rebuilt houses, center vehicles, landmarks, spawn lanes")