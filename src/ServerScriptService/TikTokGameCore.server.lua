-- TikTokGameCore.server.lua
-- SELF-CONTAINED V8
-- Put in ServerScriptService as ONE normal Script named TikTokGameCore.
-- Does NOT require ZombieFactory or GiftWeaponConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")

-- Remove/replace stale remotes only if wrong type
local function getRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA("RemoteEvent") then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local testRemote = getRemote("TikTokTestSpawn")
local streamRemote = getRemote("TikTokStreamEvent")
local attackRemote = getRemote("AutoCombatAttack")

local enemies = workspace:FindFirstChild("TikTokEnemies")
if not enemies then
	enemies = Instance.new("Folder")
	enemies.Name = "TikTokEnemies"
	enemies.Parent = workspace
end

local active = 0
local kills = 0

local function hostPlayer()
	return Players:GetPlayers()[1]
end

local function hostCharacter()
	local p = hostPlayer()
	return p and p.Character
end

local function stats()
	streamRemote:FireAllClients({
		kind = "stats",
		kills = kills,
		active = active,
		wave = math.floor(kills / 20) + 1
	})
end

local function randomSpawn()
	local char = hostCharacter()
	local root = char and char:FindFirstChild("HumanoidRootPart")

	if root then
		local angle = math.rad(math.random(0,359))
		local radius = math.random(28,42)
		return root.Position + Vector3.new(
			math.cos(angle) * radius,
			0,
			math.sin(angle) * radius
		)
	end

	return Vector3.new(math.random(-35,35), 3, math.random(-35,35))
end

local function style(model,boss)
	for _,obj in ipairs(model:GetDescendants()) do
		if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then
			obj:Destroy()
		elseif obj:IsA("BasePart") then
			obj.Anchored = false
			obj.Material = Enum.Material.SmoothPlastic

			if obj.Name == "Head" then
				obj.Color = boss and Color3.fromRGB(135,65,60) or Color3.fromRGB(110,145,100)
			elseif obj.Name:find("Torso") then
				obj.Color = boss and Color3.fromRGB(90,28,28) or Color3.fromRGB(45,68,49)
			elseif obj.Name:find("Arm") or obj.Name:find("Hand") then
				obj.Color = boss and Color3.fromRGB(115,52,48) or Color3.fromRGB(90,120,82)
			elseif obj.Name:find("Leg") or obj.Name:find("Foot") then
				obj.Color = Color3.fromRGB(34,40,38)
			end
		end
	end
end

local function addName(model,name,boss)
	local head = model:FindFirstChild("Head")
	if not head then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ViewerTag"
	gui.Size = UDim2.fromOffset(boss and 210 or 170,32)
	gui.StudsOffset = Vector3.new(0,3.1,0)
	gui.AlwaysOnTop = true
	gui.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1,1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = .2
	lbl.TextColor3 = boss and Color3.fromRGB(255,85,70) or Color3.new(1,1,1)
	lbl.Text = boss and ("BOSS • @"..name) or ("@"..name)
	lbl.Parent = gui
end

local function addWalk(hum)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://507777826"

	local ok,track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Movement

		hum.Running:Connect(function(speed)
			if hum.Health <= 0 then
				if track.IsPlaying then track:Stop(.05) end
			elseif speed > .5 then
				if not track.IsPlaying then track:Play(.1) end
				track:AdjustSpeed(math.clamp(speed / 9, .75, 1.4))
			elseif track.IsPlaying then
				track:Stop(.15)
			end
		end)
	end
end

local function startChase(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	task.spawn(function()
		local lastHit = 0
		local lastPath = 0
		local waypoint = nil
		local lastPos = root.Position
		local stuckFor = 0

		while model.Parent and hum.Health > 0 and model:GetAttribute("Dead") ~= true do
			local char = hostCharacter()
			local targetHum = char and char:FindFirstChildOfClass("Humanoid")
			local targetRoot = char and char:FindFirstChild("HumanoidRootPart")

			if targetHum and targetRoot and targetHum.Health > 0 then
				local distance = (targetRoot.Position - root.Position).Magnitude

				-- Always direct chase first; this guarantees movement on open ground.
				hum:MoveTo(targetRoot.Position)

				-- Lightweight path assist.
				if distance > 12 and os.clock() - lastPath > .8 then
					lastPath = os.clock()

					task.spawn(function()
						local path = PathfindingService:CreatePath({
							AgentRadius = 2,
							AgentHeight = 5,
							AgentCanJump = true,
							WaypointSpacing = 6
						})

						local ok = pcall(function()
							path:ComputeAsync(root.Position,targetRoot.Position)
						end)

						if ok and path.Status == Enum.PathStatus.Success then
							local pts = path:GetWaypoints()
							if #pts >= 2 then
								waypoint = pts[2]
							end
						end
					end)
				end

				if waypoint then
					if (root.Position - waypoint.Position).Magnitude < 3 then
						waypoint = nil
					else
						if waypoint.Action == Enum.PathWaypointAction.Jump then
							hum.Jump = true
						end
						hum:MoveTo(waypoint.Position)
					end
				end

				-- Anti-stuck detection.
				local moved = (root.Position - lastPos).Magnitude
				if moved < .25 and distance > 7 then
					stuckFor += .12
				else
					stuckFor = 0
				end
				lastPos = root.Position

				if stuckFor > 1.2 then
					hum.Jump = true
					hum:MoveTo(targetRoot.Position + Vector3.new(math.random(-5,5),0,math.random(-5,5)))
					stuckFor = 0
				end

				if distance <= 4.7 and os.clock() - lastHit > 1.35 then
					if hum.Health > 0 and model:GetAttribute("Dead") ~= true then
						lastHit = os.clock()
						targetHum:TakeDamage(model:GetAttribute("Boss") and 5 or 1.5)
					end
				end
			end

			task.wait(.12)
		end
	end)
end

local function spawnZombie(sender,boss)
	local desc = Instance.new("HumanoidDescription")
	desc.BodyTypeScale = 0
	desc.ProportionScale = 0
	desc.HeightScale = boss and 1.18 or 1
	desc.WidthScale = boss and 1.12 or 1
	desc.DepthScale = boss and 1.08 or 1
	desc.HeadScale = 1

	local ok,model = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc,Enum.HumanoidRigType.R15)
	end)

	if not ok or not model then
		warn("V8 zombie rig failed:",model)
		return
	end

	model.Name = boss and ("Boss_"..sender) or ("Zombie_"..sender)
	model:SetAttribute("TikTokEnemy",true)
	model:SetAttribute("Boss",boss == true)
	model:SetAttribute("Dead",false)
	model.Parent = enemies

	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")

	if not hum or not root then
		model:Destroy()
		return
	end

	style(model,boss)
	addName(model,sender,boss)
	addWalk(hum)

	hum.MaxHealth = boss and 700 or 125
	hum.Health = hum.MaxHealth
	hum.WalkSpeed = boss and 8 or 9
	hum.JumpPower = 36
	hum.AutoRotate = true
	hum.PlatformStand = false
	hum.Sit = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	model:PivotTo(CFrame.new(randomSpawn()+Vector3.new(0,3,0)))

	for _,obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
		end
	end

	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	active += 1
	stats()

	hum.Died:Connect(function()
		if model:GetAttribute("Dead") then return end
		model:SetAttribute("Dead",true)
		hum.WalkSpeed = 0

		active = math.max(0,active-1)
		kills += 1
		stats()

		for _,obj in ipairs(model:GetDescendants()) do
			if obj:IsA("BasePart") then
				obj.CanTouch = false
				obj.CanCollide = false
			end
		end

		Debris:AddItem(model,1.2)
	end)

	startChase(model)
end

-- Test button
testRemote.OnServerEvent:Connect(function(player,amount)
	amount = math.clamp(tonumber(amount) or 10,1,20)
	print("V8 TEST SPAWN:",player.Name,amount)

	for i=1,amount do
		spawnZombie("TEST_VIEWER_"..i,false)
		task.wait(.05)
	end
end)

-- Auto combat server validation
local weapons = {
	Pistol = {damage=20,range=100},
	SMG = {damage=11,range=95},
	Shotgun = {damage=30,range=65},
	Rifle = {damage=31,range=145},
	Minigun = {damage=8,range=120},
}

attackRemote.OnServerEvent:Connect(function(player,target,weapon)
	if typeof(target) ~= "Instance" then return end
	if not target:IsDescendantOf(enemies) then return end

	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
	local enemyHum = target:FindFirstChildOfClass("Humanoid")
	local enemyRoot = target:FindFirstChild("HumanoidRootPart")

	if not playerRoot or not enemyHum or not enemyRoot then return end
	if enemyHum.Health <= 0 or target:GetAttribute("Dead") then return end

	local distance = (playerRoot.Position-enemyRoot.Position).Magnitude

	if weapon == "Sword" then
		if distance <= 10 then
			enemyHum:TakeDamage(40)
		end
		return
	end

	local cfg = weapons[weapon]
	if cfg and distance <= cfg.range + 10 then
		enemyHum:TakeDamage(cfg.damage)
	end
end)

print("V8 GAME CORE READY - no ZombieFactory/GiftWeaponConfig dependency.")
