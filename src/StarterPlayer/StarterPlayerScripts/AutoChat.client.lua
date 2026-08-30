-- AutoChat.client.lua
-- VIEWERS VS ME - occasional playful trash talk in Roblox chat.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local rng = Random.new()

local lines = {
	"chat yall gotta do better than that",
	"who sent that weak stuff 😂",
	"im still standing chat",
	"nahhh yall thought that was enough?",
	"chat wake up im cooking",
	"keep em coming this is light work",
	"yall really trying to get me killed huh",
	"chat that horde was embarrassing",
	"somebody send something actually dangerous",
	"im farming these zombies rn",
	"chat stop selling 😭",
	"that was supposed to scare me?",
	"yall are getting cooked by the host",
	"send the boss then",
	"chat im not losing to that",
}

local function sendLine(text)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChildWhichIsA("TextChannel"))
	if general then
		pcall(function()
			general:SendAsync(text)
		end)
		return
	end

	-- Legacy chat fallback if the experience still uses it.
	local events = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
	local say = events and events:FindFirstChild("SayMessageRequest")
	if say then
		pcall(function()
			say:FireServer(text, "All")
		end)
	end
end

local function shouldTalk()
	-- Don't spam while the player is dead/not spawned.
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

task.spawn(function()
	task.wait(rng:NextNumber(18, 30))
	while true do
		if shouldTalk() then
			sendLine(lines[rng:NextInteger(1, #lines)])
		end
		task.wait(rng:NextNumber(28, 52))
	end
end)

print("AUTO CHAT READY - occasional playful trash talk")
