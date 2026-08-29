-- HUDCleanup.client.lua
-- VIEWERS VS ME - targeted UI cleanup.
-- Removes accidental default Roblox TextLabels whose visible text is literally "Label".
-- Does not touch named game HUD text.

local Players=game:GetService("Players")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")

local function clean(obj)
	if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and tostring(obj.Text):match("^%s*Label%s*$") then
		warn("HUD CLEANUP removed stray default label:",obj:GetFullName())
		obj:Destroy()
	end
end

for _,obj in ipairs(playerGui:GetDescendants()) do clean(obj) end
playerGui.DescendantAdded:Connect(function(obj)
	task.defer(function()
		if obj and obj.Parent then clean(obj) end
	end)
end)

print("HUD CLEANUP READY - stray default Label UI removed.")