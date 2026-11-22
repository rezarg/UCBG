local success, res
repeat
	success, res = pcall(function()
		return json.parse(Http:GetAsync(`https://api.polytoria.com/v1/places/{world.WorldID}`))
	end)
	if not success then
		wait(1)
	end
until success

if res.errors then -- Creator playtest, WorldID doesn't exist
	res.maxPlayers = 8
end

world.Shared.Singleplayer = res.maxPlayers == 1

local serverSize = res.maxPlayers
local plotRadius = 192

local prefab: Folder = ServerHidden.Plot

local networkMassDeleteSS: BindableEvent = ScriptService.MassDeleteSS

local manualPlotPlacements = {}
manualPlotPlacements[8] = {
	Distance = 144,
	Size = 128,
	Positions = {
		Vector3.New(-1, 0, -1),
		Vector3.New(0, 0, -1),
		Vector3.New(1, 0, -1),
		Vector3.New(1, 0, 0),
		Vector3.New(1, 0, 1),
		Vector3.New(0, 0, 1),
		Vector3.New(-1, 0, 1),
		Vector3.New(-1, 0, 0),
	},
}

-- Initialize Global Plot
do
	local plot = prefab:Clone(Environment)
	plot.Name = "PlotGlobal"

	local plotGround: Part = plot.PlotGround
	plotGround.Position = Vector3.Zero

	if world.Shared.Singleplayer then
		plotGround.Size = Vector3.New(512, 1, 512)
	else
		plotGround.Size = Vector3.New(128, 1, 128)
	end

	local plotPath: Part = plot.Path1
	plotPath.Position = Vector3.Zero
	plotPath.Size = Vector3.New(144, 0.75, 144)
	plotPath.Color = Color.New(plotPath.Color.R * 0.95, plotPath.Color.G * 0.95, plotPath.Color.B * 0.95, 1)
end

Environment.GlobalPath.Size = Vector3.New(plotRadius * 2 - 32, 0.25, plotRadius * 2 - 32)

-- Initialize Per-Player Plot
local plots: { { Owner: Player, Ref: Folder } } = {}
if serverSize > 1 then
	for i = 1, serverSize do
		local plot = prefab:Clone(Environment)
		plot.Name = `Plot{i}`

		local plotGround: Part = plot.PlotGround
		local plotPath: Part = plot.Path1
		plotPath.Size = Vector3.New(144, 0.5, 144)

		if not manualPlotPlacements[serverSize] then -- Procedural Placement, saving for later just in case
			local theta = math.pi * 2 * (i / serverSize)

			plotGround.Size = Vector3.New(80, 1, 80)
			plotGround.Position =
				Vector3.New(math.round(math.cos(theta) * plotRadius), 0, math.round(math.sin(theta) * plotRadius))
		else
			plotGround.Size =
				Vector3.New(manualPlotPlacements[serverSize].Size, 1, manualPlotPlacements[serverSize].Size)
			plotGround.Position = manualPlotPlacements[serverSize].Positions[i]
				* manualPlotPlacements[serverSize].Distance
		end

		plotPath.Position = plotGround.Position
		plot.OwnerText.Position = plotGround.Position + Vector3.New(0, 64, 0)

		plots[i] = { Owner = nil, Ref = plot }
	end
else
	local plot = prefab:Clone(Environment)
	plot.Name = "PlotDummy"

	local plotGround: Part = plot.PlotGround
	plotGround.Size = Vector3.Zero
	plotGround.Position = Vector3.Zero

	plot.Path1:Destroy()

	plots[1] = { Owner = nil, Ref = plot }
end

Players.PlayerAdded:Connect(function(player: Player)
	if serverSize == 1 then
		player.Plot.Value = plots[1].Ref
	else
		local foundPlot = false
		while not foundPlot do
			for _, plot in plots do
				if plot.Owner then
					continue
				end

				plot.Owner = player
				plot.Ref.OwnerText.Text = player.Name

				player.Plot.Value = plot.Ref
				player.Position = plot.Ref.PlotGround.Position + Vector3.New(0, 5, 0)
				-- player.Position = plot.Ref.PlotGround.Position * 0.5 + Vector3.New(0, 5, 0)

				foundPlot = true
				break
			end
			wait(1)
		end
	end
end)

Players.PlayerRemoved:Connect(function(player: Player)
	for _, plot in plots do
		if plot.Owner ~= player then
			continue
		end

		local uuids = {}
		for _, v: Part in Environment.Blocks:GetChildren() do
			local data = json:parse(v.Data.Value)
			if data.Owner == player.UserID then
				table.insert(uuids, data.UUID)
			end
		end
		networkMassDeleteSS:Invoke(uuids)

		plot.Owner = nil
		plot.Ref.OwnerText.Text = ""
	end
end)
