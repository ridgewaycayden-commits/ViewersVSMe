-- CharacterNoGlow.server.lua
-- VIEWERS VS ME - CHARACTER MATERIAL CLEANUP V1
-- Keeps city neon intact while removing permanent glow from zombies/Titans.

local enemies=workspace:WaitForChild("TikTokEnemies")

local function cleanupObject(obj)
	if obj:IsA("BasePart") then
		if obj.Material==Enum.Material.Neon then
			-- Armor/detail parts read better as solid surfaces under the city lighting.
			if obj.Name:lower():find("armor") or obj.Name:lower():find("plate") or obj.Name:lower():find("gauntlet") or obj.Name:lower():find("core") then
				obj.Material=Enum.Material.Metal
			else
				obj.Material=Enum.Material.SmoothPlastic
			end
		end
		-- Keep colors, just stop emissive-looking transparency tricks on permanent details.
		if obj.Name~="SpawnDirt" and obj.Transparency>0 and obj.Transparency<0.5 then
			obj.Transparency=0
		end
	elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
		obj:Destroy()
	elseif obj:IsA("Highlight") then
		-- Hit flashes are created temporarily by combat physics; persistent boss glow is removed.
		if obj.Name~="HitFlash" then obj:Destroy() end
	elseif obj:IsA("ParticleEmitter") then
		local n=obj.Name:lower()
		-- Preserve short spawn/hit dirt effects, remove persistent aura/smoke tied to character glow.
		if n:find("aura") or n:find("corrupt") or n:find("energy") then obj:Destroy() end
	end
end

local function cleanModel(model)
	if not model:IsA("Model") then return end
	for _,obj in ipairs(model:GetDescendants()) do cleanupObject(obj) end
	model.DescendantAdded:Connect(function(obj)
		task.defer(function()
			if obj.Parent then cleanupObject(obj) end
		end)
	end)
end

for _,m in ipairs(enemies:GetChildren()) do cleanModel(m) end
enemies.ChildAdded:Connect(function(m)
	task.defer(function() if m.Parent then cleanModel(m) end end)
end)

print("CHARACTER NO-GLOW V1 READY - zombies/Titan are matte, city neon untouched.")