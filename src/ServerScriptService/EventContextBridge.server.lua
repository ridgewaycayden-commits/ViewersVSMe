-- EventContextBridge.server.lua
-- VIEWERS VS ME - EVENT CONTEXT BRIDGE V2.1
-- One authoritative popup per gift, matched to the effects in GiftEvents / final weapon bindings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local function getRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then r:Destroy(); r = nil end
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local function getBindable(name)
	local b = ServerStorage:FindFirstChild(name)
	if b and not b:IsA("BindableEvent") then b:Destroy(); b = nil end
	if not b then
		b = Instance.new("BindableEvent")
		b.Name = name
		b.Parent = ServerStorage
	end
	return b
end

local remote = getRemote("EventContextFX")
local dispatch = getBindable("ViewersVsMeGiftDispatch")
local debug = getRemote("GiftDebug")

local MAP = {
	["Rose"]={side="HELP",title="ROSE • HEAL",subtitle="+10 HP restored",color=Color3.fromRGB(90,255,150)},
	["Chilli"]={side="AGAINST",title="CHILLI • HORDE",subtitle="3 infected spawned",color=Color3.fromRGB(255,95,65)},
	["Love You"]={side="HELP",title="LOVE YOU • HANDGUN",subtitle="+25 HP and handgun for 90s",color=Color3.fromRGB(80,220,255)},
	["Night Star"]={side="AGAINST",title="NIGHT STAR • BLACKOUT",subtitle="8 second blackout + 6 infected",color=Color3.fromRGB(180,90,255)},
	["Galaxy"]={side="HELP",title="GALAXY • MINIGUN",subtitle="Minigun for 90s + 8 second shield",color=Color3.fromRGB(120,180,255)},
	["Giraffe"]={side="AGAINST",title="GIRAFFE • TITAN",subtitle="Titan + 8 infected spawned",color=Color3.fromRGB(255,70,55)},
	["Perfume"]={side="HELP",title="PERFUME • MEDKIT",subtitle="+20 HP restored",color=Color3.fromRGB(90,255,150)},
	["G.O.A.T Busker"]={side="AGAINST",title="G.O.A.T BUSKER • PRESSURE",subtitle="12 damage + 2 infected",color=Color3.fromRGB(255,95,65)},
	["Manifesting"]={side="HELP",title="MANIFESTING • AK47",subtitle="+45 HP, zombies frozen 8s, AK47 for 90s",color=Color3.fromRGB(80,220,255)},
	["Star Map Polaris"]={side="AGAINST",title="STAR MAP POLARIS • BLACKOUT",subtitle="10 second blackout + 10 infected",color=Color3.fromRGB(180,90,255)},
	["Travel The US"]={side="HELP",title="TRAVEL THE US • AIRSTRIKE",subtitle="Normal infected wiped, +75 HP, shield 12s",color=Color3.fromRGB(255,205,80)},
	["Bunny DJ"]={side="AGAINST",title="BUNNY DJ • TITAN DROP",subtitle="Titan + 12 infected + meteor",color=Color3.fromRGB(255,70,55)},

	-- Legacy gifts still supported by the server.
	["Heart Me"]={side="HELP",title="HEART ME • AK47",subtitle="AK47 activated for 90s",color=Color3.fromRGB(80,220,255)},
	["Hand Hearts"]={side="HELP",title="HAND HEARTS • HANDGUN",subtitle="+30 HP and handgun activated",color=Color3.fromRGB(255,155,90)},
	["Interstellar"]={side="HELP",title="INTERSTELLAR • AK47",subtitle="Zombies frozen + AK47 activated",color=Color3.fromRGB(120,230,255)},
	["Phoenix"]={side="HELP",title="PHOENIX • AIRSTRIKE",subtitle="Normal infected wiped + 60 HP restored",color=Color3.fromRGB(255,205,80)},
	["Sports Car"]={side="AGAINST",title="SPORTS CAR • HORDE",subtitle="8 infected spawned",color=Color3.fromRGB(255,95,65)},
	["Lion"]={side="AGAINST",title="LION • TITAN",subtitle="Titan + 6 infected spawned",color=Color3.fromRGB(255,70,55)},
	["TikTok Universe"]={side="AGAINST",title="UNIVERSE • BLACKOUT",subtitle="12 second blackout + 16 infected",color=Color3.fromRGB(190,80,255)},
	["Universe"]={side="AGAINST",title="UNIVERSE • BLACKOUT",subtitle="12 second blackout + 16 infected",color=Color3.fromRGB(190,80,255)},
	["Meteor Shower"]={side="AGAINST",title="METEOR SHOWER • INBOUND",subtitle="Meteor impact near your position",color=Color3.fromRGB(255,110,45)},
	["Private Jet"]={side="HELP",title="PRIVATE JET • ORBITAL STRIKE",subtitle="Orbital support targeting infected",color=Color3.fromRGB(80,220,255)},
	["Castle Fantasy"]={side="HELP",title="CASTLE FANTASY • OVERDRIVE",subtitle="Minigun + full heal + temporary shield",color=Color3.fromRGB(255,90,90)},
	["Dragon Flame"]={side="AGAINST",title="DRAGON FLAME • HELLSTORM",subtitle="Meteor barrage attacking your area",color=Color3.fromRGB(255,75,30)},
	["Leon and Lion"]={side="AGAINST",title="LEON & LION • TITAN RAGE",subtitle="Titans enraged or a Titan is spawned",color=Color3.fromRGB(255,35,40)},
	["Thunder Falcon"]={side="AGAINST",title="THUNDER FALCON • EMP",subtitle="Support weapon disabled + city darkened",color=Color3.fromRGB(155,85,255)},
}

local function host()
	return Players:GetPlayers()[1]
end

local function send(name, sender, count)
	local cfg = MAP[tostring(name or "")]
	if not cfg then
		remote:FireAllClients({
			side="EVENT",
			title=tostring(name or "VIEWER GIFT"):upper(),
			subtitle="Gift received",
			sender=tostring(sender or "VIEWER"),
			color=Color3.fromRGB(90,220,255),
		})
		return
	end
	local subtitle = cfg.subtitle
	if count and count > 1 then subtitle = subtitle .. "  x" .. tostring(count) end
	remote:FireAllClients({
		side=cfg.side,
		title=cfg.title,
		subtitle=subtitle,
		sender=tostring(sender or "VIEWER"),
		color=cfg.color,
	})
end

dispatch.Event:Connect(function(name, sender, count)
	send(name, sender, tonumber(count) or 1)
end)

debug.OnServerEvent:Connect(function(p, giftName)
	if p == host() then send(giftName, "TEST_VIEWER", 1) end
end)

print("EVENT CONTEXT BRIDGE V2.1 READY - Heart Me = AK47")
