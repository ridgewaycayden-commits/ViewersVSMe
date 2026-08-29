-- ManhattanMidtownV10.server.lua
-- VIEWERS VS ME - MIDTOWN MANHATTAN V10
-- Movement-safe NYC rebuild inspired by real Midtown Manhattan / OSM street character.
-- Keeps the proven 100-stud road grid completely open and uses realistic NYC building archetypes.

local Lighting=game:GetService("Lighting")

local prior=workspace:FindFirstChild("ManhattanMidtownV10")
if prior then prior:Destroy() end
local stale=workspace:FindFirstChild("NYCReworkV9")
if stale then stale:Destroy() end

local world=Instance.new("Folder")
world.Name="ManhattanMidtownV10"
world.Parent=workspace

local rng=Random.new(8292026)
local blocks={-150,-50,50,150}

local function part(name,size,cf,color,material,collide,parent)
	local p=Instance.new("Part")
	p.Name=name;p.Size=size;p.CFrame=cf;p.Color=color;p.Material=material or Enum.Material.Concrete
	p.Anchored=true;p.CanCollide=collide==true;p.CanTouch=false;p.CanQuery=collide==true;p.CastShadow=true
	p.Parent=parent or world
	return p
end

local function mdl(name)
	local m=Instance.new("Model");m.Name=name;m.Parent=world;return m
end

local function textFace(p,text,color)
	local sg=Instance.new("SurfaceGui");sg.Face=Enum.NormalId.Front;sg.LightInfluence=0;sg.PixelsPerStud=48;sg.Parent=p
	local t=Instance.new("TextLabel");t.Size=UDim2.fromScale(1,1);t.BackgroundTransparency=1;t.Text=text;t.TextColor3=color;t.TextStrokeTransparency=.45;t.Font=Enum.Font.GothamBlack;t.TextScaled=true;t.Parent=sg
end

-- Undo any hot-session damage caused by V9 hiding the old map.
local oldCity=workspace:FindFirstChild("TikTokAFKCity") or workspace:FindFirstChild("TikTokCity")
if oldCity then
	for _,obj in ipairs(oldCity:GetDescendants()) do
		if obj:IsA("BasePart") and obj:GetAttribute("NYC_V9_HIDDEN") then
			obj:SetAttribute("NYC_V9_HIDDEN",nil)
			obj.Transparency=0
			obj.CanCollide=true
			obj.CanQuery=true
		end
	end
	-- Hide only the original huge generic tower shells again, but do NOT let them affect nav.
	for _,obj in ipairs(oldCity:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Size.Y>=18 and obj.Size.X>=8 and obj.Size.Z>=8 then
			obj.Transparency=1;obj.CanCollide=false;obj.CanTouch=false;obj.CanQuery=false
		end
	end
end

-- More grounded NYC night lighting; previous city neon remains as atmosphere.
Lighting.ClockTime=21.35
Lighting.Brightness=3.1
Lighting.ExposureCompensation=.55
Lighting.Ambient=Color3.fromRGB(72,78,92)
Lighting.OutdoorAmbient=Color3.fromRGB(90,98,116)

local brick={Color3.fromRGB(105,60,48),Color3.fromRGB(88,49,43),Color3.fromRGB(122,76,58),Color3.fromRGB(92,69,59)}
local limestone={Color3.fromRGB(142,136,122),Color3.fromRGB(121,119,111),Color3.fromRGB(157,149,133)}
local darkGlass={Color3.fromRGB(24,34,43),Color3.fromRGB(31,42,51),Color3.fromRGB(20,29,37)}
local windowDark=Color3.fromRGB(25,29,34)
local windowWarm=Color3.fromRGB(226,194,128)

local function windowsFront(m,cf,w,d,h,spacing)
	spacing=spacing or 7
	for y=9,h-6,7 do
		for x=-w/2+4,w/2-3,spacing do
			local lit=rng:NextNumber()<.22
			local p=part("Window",Vector3.new(math.min(3.6,spacing-2),3.4,.12),cf*CFrame.new(x,-h/2+y,-d/2-.07),lit and windowWarm or windowDark,lit and Enum.Material.Neon or Enum.Material.Glass,false,m)
			p.Transparency=lit and .15 or .22
		end
	end
end

local function cornice(m,cf,w,d,h)
	part("Cornice",Vector3.new(w+1.5,1.1,d+1.5),cf*CFrame.new(0,h/2-.55,0),Color3.fromRGB(89,83,75),Enum.Material.Concrete,false,m)
end

local function roofStuff(m,cf,w,d,h,water)
	for i=1,2 do
		part("HVAC",Vector3.new(rng:NextNumber(3.5,6),2.3,rng:NextNumber(3.5,6)),cf*CFrame.new(rng:NextNumber(-w*.25,w*.25),h/2+1.15,rng:NextNumber(-d*.25,d*.25)),Color3.fromRGB(74,77,80),Enum.Material.Metal,false,m)
	end
	if water then
		for x=-1,1,2 do for z=-1,1,2 do part("TankLeg",Vector3.new(.22,5,.22),cf*CFrame.new(x*1.5,h/2+2.5,z*1.5),Color3.fromRGB(67,57,48),Enum.Material.Wood,false,m) end end
		local tank=part("WaterTower",Vector3.new(5.2,5.2,5.2),cf*CFrame.new(0,h/2+6,0),Color3.fromRGB(92,74,58),Enum.Material.Wood,false,m)
		tank.Shape=Enum.PartType.Cylinder;tank.CFrame=tank.CFrame*CFrame.Angles(0,0,math.rad(90))
	end
end

local function fireEscape(m,cf,w,d,h)
	local x=w/2+.38
	for y=-h/2+12,h/2-8,10 do
		part("FireEscapePlatform",Vector3.new(.22,.25,5.2),cf*CFrame.new(x,y,0),Color3.fromRGB(37,39,41),Enum.Material.Metal,false,m)
		part("FireEscapeRail",Vector3.new(.15,2.1,5.2),cf*CFrame.new(x+.45,y+1,0),Color3.fromRGB(37,39,41),Enum.Material.Metal,false,m)
	end
end

local function storefront(m,cf,w,d,label,color)
	local front=cf*CFrame.new(0,-cf.Position.Y+d*0,-d/2-.15)
	part("StoreGlass",Vector3.new(w-3,5,.25),cf*CFrame.new(0,-cf.Position.Y+3,-d/2-.15),Color3.fromRGB(18,28,34),Enum.Material.Glass,false,m).Transparency=.18
	local sign=part("StoreSign",Vector3.new(math.min(w-4,17),2.2,.35),cf*CFrame.new(0,-cf.Position.Y+7,-d/2-.28),Color3.fromRGB(20,22,25),Enum.Material.Metal,false,m)
	textFace(sign,label,color)
	part("Awning",Vector3.new(math.min(w-3,19),.35,2.2),cf*CFrame.new(0,-cf.Position.Y+5.8,-d/2-1),color,Enum.Material.Fabric,false,m)
end

local function prewar(pos,w,d,h,label)
	local m=mdl("NYC_Prewar")
	local cf=CFrame.new(pos+Vector3.new(0,h/2,0))
	part("Shell",Vector3.new(w,h,d),cf,brick[rng:NextInteger(1,#brick)],Enum.Material.Brick,true,m)
	windowsFront(m,cf,w,d,h,6.5);cornice(m,cf,w,d,h);fireEscape(m,cf,w,d,h);roofStuff(m,cf,w,d,h,h>42 and rng:NextNumber()<.65)
	storefront(m,cf,w,d,label or "DELI",Color3.fromRGB(40,115,65))
	return m
end

local function officeTower(pos,w,d,h)
	local m=mdl("NYC_OfficeTower")
	local cf=CFrame.new(pos+Vector3.new(0,h/2,0))
	part("GlassCore",Vector3.new(w,h,d),cf,darkGlass[rng:NextInteger(1,#darkGlass)],Enum.Material.Glass,true,m).Transparency=.12
	for x=-w/2+3,w/2-2,5 do part("VerticalMullion",Vector3.new(.16,h,.18),cf*CFrame.new(x,0,-d/2-.1),Color3.fromRGB(55,58,61),Enum.Material.Metal,false,m) end
	for y=-h/2+5,h/2-3,6 do part("FloorBand",Vector3.new(w+.15,.18,.22),cf*CFrame.new(0,y,-d/2-.12),Color3.fromRGB(48,50,54),Enum.Material.Metal,false,m) end
	part("Lobby",Vector3.new(w-4,8,d+.3),CFrame.new(pos+Vector3.new(0,4,0)),Color3.fromRGB(20,27,33),Enum.Material.Glass,false,m).Transparency=.12
	roofStuff(m,cf,w,d,h,false)
	return m
end

local function artDeco(pos,w,d,h)
	local m=mdl("NYC_ArtDeco")
	local stone=limestone[rng:NextInteger(1,#limestone)]
	local y=0
	local levels={{w,d,h*.58},{w*.80,d*.80,h*.21},{w*.58,d*.58,h*.13},{w*.36,d*.36,h*.08}}
	for _,v in ipairs(levels) do
		local lh=v[3];local cf=CFrame.new(pos+Vector3.new(0,y+lh/2,0))
		part("Setback",Vector3.new(v[1],lh,v[2]),cf,stone,Enum.Material.Concrete,true,m)
		windowsFront(m,cf,v[1],v[2],lh,6.5);y+=lh
	end
	part("Mast",Vector3.new(1.1,16,1.1),CFrame.new(pos+Vector3.new(0,h+8,0)),Color3.fromRGB(120,120,115),Enum.Material.Metal,false,m)
	return m
end

local function timesSquareTower(pos)
	local m=mdl("OneTimesSquareInspired")
	local h=118;local cf=CFrame.new(pos+Vector3.new(0,h/2,0))
	part("Main",Vector3.new(34,h,26),cf,Color3.fromRGB(69,66,61),Enum.Material.Concrete,true,m)
	for y=13,90,13 do
		local board=part("DigitalBillboard",Vector3.new(31,9,.32),CFrame.new(pos+Vector3.new(0,y,-13.18)),Color3.fromRGB(25,25,27),Enum.Material.SmoothPlastic,false,m)
		local colors={Color3.fromRGB(235,52,58),Color3.fromRGB(62,140,235),Color3.fromRGB(238,190,54),Color3.fromRGB(235,235,235)}
		textFace(board,({"TIMES SQ","BROADWAY","NYC","LIVE"})[((y/13-1)%4)+1],colors[((y/13-1)%4)+1])
	end
	part("RoofMast",Vector3.new(1.5,27,1.5),CFrame.new(pos+Vector3.new(0,h+13.5,0)),Color3.fromRGB(95,95,92),Enum.Material.Metal,false,m)
	return m
end

local function empireInspired(pos)
	local m=mdl("EmpireStateInspired")
	local stone=Color3.fromRGB(151,145,132)
	local y=0
	for _,v in ipairs({{48,44,80},{40,36,28},{31,28,22},{22,20,18},{14,13,15}}) do
		part("Setback",Vector3.new(v[1],v[3],v[2]),CFrame.new(pos+Vector3.new(0,y+v[3]/2,0)),stone,Enum.Material.Concrete,true,m);y+=v[3]
	end
	part("SpireBase",Vector3.new(8,14,8),CFrame.new(pos+Vector3.new(0,y+7,0)),Color3.fromRGB(126,126,119),Enum.Material.Metal,false,m)
	part("Spire",Vector3.new(1.2,34,1.2),CFrame.new(pos+Vector3.new(0,y+31,0)),Color3.fromRGB(145,145,138),Enum.Material.Metal,false,m)
	return m
end

local function subway(pos,rot,lineText)
	local m=mdl("MTA_SubwayEntrance")
	local cf=CFrame.new(pos)*CFrame.Angles(0,math.rad(rot),0)
	part("StairVoid",Vector3.new(8,.12,12),cf*CFrame.new(0,.1,0),Color3.fromRGB(15,16,18),Enum.Material.Asphalt,false,m)
	for x=-4,4,8 do part("Rail",Vector3.new(.22,3,12),cf*CFrame.new(x,1.5,0),Color3.fromRGB(52,55,58),Enum.Material.Metal,false,m) end
	local s=part("MTA Sign",Vector3.new(7.5,2,.3),cf*CFrame.new(0,3,-5.4),Color3.fromRGB(18,20,23),Enum.Material.Metal,false,m);textFace(s,lineText,Color3.fromRGB(240,240,240))
end

local function streetSign(pos,a,b)
	local m=mdl("NYC_StreetSign")
	part("Pole",Vector3.new(.22,7,.22),CFrame.new(pos+Vector3.new(0,3.5,0)),Color3.fromRGB(63,67,65),Enum.Material.Metal,false,m)
	local s1=part("StreetBlade",Vector3.new(7,1.25,.16),CFrame.new(pos+Vector3.new(0,6.7,0)),Color3.fromRGB(25,103,59),Enum.Material.Metal,false,m);textFace(s1,a,Color3.new(1,1,1))
	local s2=part("StreetBlade",Vector3.new(7,1.25,.16),CFrame.new(pos+Vector3.new(0,7.9,0))*CFrame.Angles(0,math.rad(90),0),Color3.fromRGB(25,103,59),Enum.Material.Metal,false,m);textFace(s2,b,Color3.new(1,1,1))
end

-- Block footprints are deliberately max ~54x54 inside each 70x70 block.
-- That leaves ~8 studs of sidewalk between buildings and every road edge, preserving navigation.
local labels={"DELI & GROCERY","PIZZA","DINER","PHARMACY","BAGELS","MARKET","CAFE","LAUNDROMAT"}
for _,bx in ipairs(blocks) do
	for _,bz in ipairs(blocks) do
		local nearCenter=math.abs(bx)==50 and math.abs(bz)==50
		if nearCenter then
			-- Small corner buildings only; keep central plaza approach wide open.
			local sx=bx>0 and 18 or -18;local sz=bz>0 and 18 or -18
			prewar(Vector3.new(bx+sx,0,bz+sz),27,27,38,labels[rng:NextInteger(1,#labels)])
		else
			local roll=rng:NextNumber()
			if roll<.42 then
				-- NYC row of attached pre-war facades, all contained within the block.
				for i=-1,1 do prewar(Vector3.new(bx+i*17,0,bz),16,50,rng:NextInteger(36,58),labels[rng:NextInteger(1,#labels)]) end
			elseif roll<.72 then
				officeTower(Vector3.new(bx,0,bz),50,50,rng:NextInteger(72,118))
			else
				artDeco(Vector3.new(bx,0,bz),52,52,rng:NextInteger(78,124))
			end
		end
	end
end

-- Recognizable Midtown-style anchors placed on outer blocks so combat lanes remain open.
timesSquareTower(Vector3.new(150,0,-50))
empireInspired(Vector3.new(-150,0,150))
artDeco(Vector3.new(-150,0,-150),52,52,142)
officeTower(Vector3.new(150,0,150),52,52,136)

-- NYC street furniture sits on sidewalks, never in the 30-stud road lanes.
subway(Vector3.new(24,0,-96),0,"SUBWAY  A C E")
subway(Vector3.new(-96,0,24),90,"SUBWAY  1 2 3")
subway(Vector3.new(96,0,-24),-90,"SUBWAY  N Q R W")
subway(Vector3.new(-24,0,96),180,"SUBWAY  B D F M")

streetSign(Vector3.new(18,0,-82),"W 42 ST","7 AV")
streetSign(Vector3.new(-82,0,18),"W 34 ST","6 AV")
streetSign(Vector3.new(118,0,82),"W 47 ST","BROADWAY")
streetSign(Vector3.new(-118,0,-82),"W 38 ST","8 AV")

-- Yellow taxis parked near curbs, non-collidable so AI never gets snagged.
for _,d in ipairs({{42,-12,8},{-58,12,-6},{108,-12,-9},{-112,12,7},{12,108,88},{-12,-108,-92}}) do
	local x,z,rot=d[1],d[2],d[3]
	local m=mdl("NYC_Taxi")
	local cf=CFrame.new(x,1,z)*CFrame.Angles(0,math.rad(rot),0)
	part("Body",Vector3.new(5.7,1.4,9.2),cf,Color3.fromRGB(224,170,28),Enum.Material.Metal,false,m)
	part("Cab",Vector3.new(4.8,1.7,4.2),cf*CFrame.new(0,1.45,.2),Color3.fromRGB(35,44,49),Enum.Material.Glass,false,m).Transparency=.18
	part("RoofAd",Vector3.new(2.8,.8,.5),cf*CFrame.new(0,2.8,0),Color3.fromRGB(238,238,226),Enum.Material.SmoothPlastic,false,m)
end

-- Hide tall decorative neon strips from V6 so architecture reads as NYC rather than cyberpunk.
local oldV6=workspace:FindFirstChild("NeonQuarantineV6")
if oldV6 then
	for _,p in ipairs(oldV6:GetDescendants()) do
		if p:IsA("BasePart") and p.Name=="NeonStrip" and p.Position.Y>15 then p.Transparency=.85 end
	end
end

print("MIDTOWN MANHATTAN V10 READY - real NYC-style prewar rows, office towers, art-deco setbacks, Times Square/Empire-inspired anchors, subway entrances; navigation lanes preserved.")
