-- GiftWeaponBindings.server.lua
-- VIEWERS VS ME - maps TikTok gifts to the imported weapon models used by AutoCombat V2.8.
-- Existing GiftEvents still handles healing, bosses, hordes, shields, etc.; this script owns the weapon choice.

local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local ServerStorage=game:GetService("ServerStorage")

local function host()
	return Players:GetPlayers()[1]
end

local dispatch=ServerStorage:WaitForChild("ViewersVsMeGiftDispatch")
local debugRemote=ReplicatedStorage:WaitForChild("GiftDebug")

-- Logical weapon names map to these imported assets inside AutoCombat:
-- Pistol -> Handgun
-- Rifle -> AK47
-- SMG -> HyperlaserGun
-- Shotgun -> RocketLauncher
-- Minigun -> Minigun
-- Sword -> Knife (automatic close-range melee)
local GiftWeapons={
	["Rose"]={weapon="Pistol",duration=10},
	["Heart Me"]={weapon="Rifle",duration=16},
	["Hand Hearts"]={weapon="Shotgun",duration=20},
	["Galaxy"]={weapon="Minigun",duration=28},
	["Interstellar"]={weapon="SMG",duration=30},
	["Phoenix"]={weapon="Shotgun",duration=24},
}

local serial=0

local function applyGiftWeapon(giftName,sender,count)
	local cfg=GiftWeapons[tostring(giftName or "")]
	if not cfg then return end
	local p=host();if not p then return end
	count=math.max(1,tonumber(count) or 1)
	local duration=cfg.duration + math.min(count-1,5)*3

	-- Run just after GiftEvents so this mapping is the final weapon selection.
	task.delay(.05,function()
		if not p.Parent then return end
		serial+=1
		local mySerial=serial
		p:SetAttribute("GiftWeapon",cfg.weapon)
		p:SetAttribute("GiftWeaponUntil",workspace:GetServerTimeNow()+duration)
		print("TIKTOK GIFT WEAPON:",giftName,"from",sender,"->",cfg.weapon,"for",duration,"seconds")
		task.delay(duration+.25,function()
			if mySerial~=serial or not p.Parent then return end
			if (p:GetAttribute("GiftWeaponUntil") or 0)<=workspace:GetServerTimeNow()+.3 then
				p:SetAttribute("GiftWeapon",nil)
				p:SetAttribute("GiftWeaponUntil",nil)
			end
		end)
	end)
end

dispatch.Event:Connect(applyGiftWeapon)
debugRemote.OnServerEvent:Connect(function(player,giftName)
	if player==host() then applyGiftWeapon(giftName,"TEST_VIEWER",1) end
end)

print("GIFT WEAPON BINDINGS READY - TikTok gifts now select imported gun assets")
