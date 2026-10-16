local Achievements = require(ScriptService.Achievements)

local networkGeneticEngineering: NetworkEvent = ScriptService.GeneticEngineering
local networkShortCircuit: NetworkEvent = ScriptService.ShortCircuit

networkGeneticEngineering.InvokedServer:Connect(function(player: Player, _: NetMessage)
	Achievements.Award(player, 140234, 242031) -- Genetic Engineering
end)

networkShortCircuit.InvokedServer:Connect(function(player: Player, _: NetMessage)
	Achievements.Award(player, 140234, 247356) -- Short Circuit
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.Shared.JoinTime = os.time()

	player.PropertyChanged:Connect(function(property: string)
		if property ~= "Position" then
			return
		end

		if player.Position.Y < -50 then
			Achievements.Award(player, 140234, 241563) -- You can't park there, sir!
		end
	end)

	if player.UserID == 125312 then
		for _, v in Players:GetPlayers() do
			Achievements.Award(v, 140234, 242032) -- Oh, hello...
			wait(1)
		end
	else
		for _, v in Players:GetPlayers() do
			if v.UserID == 125312 then
				Achievements.Award(player, 140234, 242032) -- Oh, hello...
			end
			wait(1)
		end
	end
end)

while wait(10) do
	local lifetime = os.time() - Environment.Shared.InitTime
	if lifetime > 28800 then
		for _, player in Players:GetPlayers() do
			Achievements.Award(player, 140234, 241562) -- Unc Server
		end
	end
	for _, player in Players:GetPlayers() do
		local playtime = os.time() - player.Shared.JoinTime
		if playtime > 900 then
			Achievements.Award(player, 140234, 241561) -- Tick Tock
		end
	end
end
