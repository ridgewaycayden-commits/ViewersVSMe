-- WeaponNoGlow.client.lua
-- VIEWERS VS ME - WEAPON MATERIAL CLEANUP V1
-- Removes permanent emissive/glow parts from the FPS viewmodel while preserving shot FX.

local RunService=game:GetService("RunService")

local currentModel=nil
local connections={}

local function disconnectAll()
	for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	table.clear(connections)
end

local function isTransient(part)
	local n=part.Name:lower()
	return n=="muzzle" or n:find("flash") or n:find("spark") or n:find("tracer")
end

local function cleanupObject(obj)
	if obj:IsA("BasePart") then
		if obj.Material==Enum.Material.Neon and not isTransient(obj) then
			local n=obj.Name:lower()
			if n:find("blade") or n:find("barrel") or n:find("receiver") or n:find("slide") or n:find("rail") or n:find("stock") or n:find("core") then
				obj.Material=Enum.Material.Metal
			else
				obj.Material=Enum.Material.SmoothPlastic
			end
		end
	elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
		local p=obj.Parent
		if not (p and p:IsA("BasePart") and isTransient(p)) then obj:Destroy() end
	elseif obj:IsA("Highlight") then
		obj:Destroy()
	end
end

local function attach(model)
	if model==currentModel then return end
	disconnectAll();currentModel=model
	if not model then return end
	for _,obj in ipairs(model:GetDescendants()) do cleanupObject(obj) end
	table.insert(connections,model.DescendantAdded:Connect(function(obj)
		task.defer(function() if obj.Parent then cleanupObject(obj) end end)
	end))
end

RunService.RenderStepped:Connect(function()
	local cam=workspace.CurrentCamera
	local vm=cam and cam:FindFirstChild("FPSViewModel")
	if vm~=currentModel then attach(vm) end
end)

print("WEAPON NO-GLOW V1 READY - solid materials, muzzle/impact FX preserved.")