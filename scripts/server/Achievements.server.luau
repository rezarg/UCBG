local networkGeneticEngineering: NetworkEvent = ScriptService.GeneticEngineering
local networkShortCircuit: NetworkEvent = ScriptService.ShortCircuit

networkGeneticEngineering.InvokedServer:Connect(function(player: Player, _: NetMessage)
	Achievements:AwardAsync(player.UserID, 242031) -- Genetic Engineering
end)

networkShortCircuit.InvokedServer:Connect(function(player: Player, _: NetMessage)
	Achievements:AwardAsync(player.UserID, 247356)
end)

local ignoreLifetimeAch = {}
local ignorePlaytimeAch = {}
local ignoreVoidAch = {}

Players.PlayerAdded:Connect(function(player: Player)
	player.Shared.JoinTime = os.time()

	player.PropertyChanged:Connect(function(property: string)
		if property ~= "Position" then
			return
		end

		if player.Position.Y < -50 and not ignoreVoidAch[player.UserID] then
			Achievements:AwardAsync(player.UserID, 241563) -- You can't park there, sir!
			ignoreVoidAch[player.UserID] = true
		end
	end)

	if player.UserID == 125312 then
		for _, v in Players:GetPlayers() do
			Achievements:AwardAsync(v.UserID, 242032) -- Oh, hello...
			wait(1)
		end
	else
		for _, v in Players:GetPlayers() do
			if v.UserID == 125312 then
				Achievements:AwardAsync(player.UserID, 242032) -- Oh, hello...
			end
			wait(1)
		end
	end
end)

while wait(10) do
	local lifetime = os.time() - Environment.Shared.InitTime
	if lifetime > 28800 then
		for _, player in Players:GetPlayers() do
			if ignoreLifetimeAch[player.UserID] then
				continue
			end
			Achievements:AwardAsync(player.UserID, 241562) -- Unc Server
			ignoreLifetimeAch[player.UserID] = true
		end
	end
	for _, player in Players:GetPlayers() do
		if ignorePlaytimeAch[player.UserID] then
			continue
		end
		local playtime = os.time() - player.Shared.JoinTime
		if playtime > 900 then
			Achievements:AwardAsync(player.UserID, 241561) -- Tick Tock
			ignorePlaytimeAch[player.UserID] = true
		end
	end
end
