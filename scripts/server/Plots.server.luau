local serverSize = 8
local plotRadius = 192

local prefab: Folder = ServerHidden.Plot

local networkMassDeleteSS: BindableEvent = ScriptService.MassDeleteSS

-- Initialize Global Plot
do
	local plot = prefab:Clone(Environment)
	plot.Name = "PlotGlobal"

	local plotGround: Part = plot.PlotGround
	plotGround.Position = Vector3.Zero
	plotGround.Size = Vector3.New(128, 1, 128)

	local plotPath: Part = plot.Path1
	plotPath.Position = Vector3.Zero
	plotPath.Size = Vector3.New(144, 0.75, 144)
end

Environment.GlobalPath.Size = Vector3.New(plotRadius * 2 - 32, 0.25, plotRadius * 2 - 32)

-- Initialize Per-Player Plot
local plots: { { Owner: Player, Ref: Folder } } = {}
for i = 1, serverSize do
	local plot = prefab:Clone(Environment)
	plot.Name = `Plot{i}`

	local theta = math.pi * 2 * (i / serverSize)

	local plotGround: Part = plot.PlotGround
	plotGround.Size = Vector3.New(80, 1, 80)
	plotGround.Position =
		Vector3.New(math.round(math.cos(theta) * plotRadius), 0, math.round(math.sin(theta) * plotRadius))

	local plotPath: Part = plot.Path1
	plotPath.Position = plotGround.Position
	plotPath.Size = Vector3.New(144, 0.5, 144)

	plot.OwnerText.Position = plotGround.Position + Vector3.New(0, 64, 0)

	plots[i] = { Owner = nil, Ref = plot }
end

Players.PlayerAdded:Connect(function(player: Player)
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
