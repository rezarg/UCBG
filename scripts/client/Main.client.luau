local Tools = require(ScriptService.Tools)
local Blocks = require(ScriptService.Blocks)

Tools.Init()

local player = Players.LocalPlayer
local camera: Camera = Environment.CurrentCamera

local selectedTool: Tools.Tool? = nil
local selectedBlockDef: Blocks.BlockDef? = nil
local insertPosition = Vector3.Zero
local toolButtons = {}

local selectionHighlight: UIStroke = script.UIStroke
local selectionFace: Model = Environment.Ignore.SelectionFace
local blockGhost: Part = Environment.Ignore.BlockGhost
blockGhost.Parent = Hidden

local sinkPlace = false
local placementsPerSecond = 0

local plotRef: InstanceValue = player:WaitChild("Plot")
repeat
	wait(0.5)
until plotRef.Value

local plot = plotRef.Value
local plotGround: Part = plot.PlotGround

local networkPlaceBlock: NetworkEvent = ScriptService.PlaceBlock

local gridOffset = Vector3.New(0.5, 0, 0.5)
local function GridVector3(original: Vector3, grid: number?): Vector3
	if not grid then
		grid = 1
	end

	original -= gridOffset
	local x = math.round(original.X * grid) / grid
	local y = math.round(original.Y * grid) / grid
	local z = math.round(original.Z * grid) / grid
	return Vector3.New(x, y, z) + gridOffset
end

Hooks.Updated:Connect(function(_: number)
	if selectedTool and selectedTool.Update then
		selectedTool:Update()
	end

	local mousePosition = Input:GetMouseWorldPosition()

	local exclude = { Players, Environment.Connections, Environment.Ignore }

	local result = Environment:Raycast(camera.Position, mousePosition - camera.Position, 96, exclude)
	if not result then
		selectionFace.Position = Vector3.Zero
		return
	end

	insertPosition = GridVector3(result.Position + result.Normal * 0.5)
	selectionFace.Position = insertPosition - result.Normal * 0.5
	selectionFace:LookAt(insertPosition + result.Normal)

	if blockGhost then
		blockGhost.Position = insertPosition
	end
end)

local function Vector3InRange(value: Vector3, range: { Min: Vector3, Max: Vector3 })
	if value.X < range.Min.X or value.X > range.Max.X then
		return false
	end

	if value.Y < range.Min.Y or value.Y > range.Max.Y then
		return false
	end

	if value.Z < range.Min.Z or value.Z > range.Max.Z then
		return false
	end

	return true
end

Input.KeyDown:Connect(function(key: KeyCode, focused: boolean)
	if not focused then
		return
	end

	for _, tool in Tools.Definitions do
		if key == tool.Bind then
			sinkPlace = tick()
			blockGhost.Parent = Hidden
			selectedBlockDef = nil
			if selectedTool and selectedTool.Stop then
				selectedTool:Stop()
			end
			if selectedTool == tool then
				selectedTool = nil
				selectionHighlight.Parent = script
				return
			end
			selectedTool = tool
			if selectedTool.Start then
				selectedTool:Start()
			end
			selectionHighlight.Parent = toolButtons[tool]
			break
		end
	end

	for _, blockDef in Blocks.Definitions do
		if key == blockDef.Bind and blockDef.BindShifted == Input:GetButton("Shift").IsPressed then
			local sp = tick()
			sinkPlace = sp
			Tools.SinkMouseFor(0.1)
			if selectedTool and selectedTool.Stop then
				selectedTool:Stop()
			end
			selectedTool = nil
			if selectedBlockDef == blockDef then
				selectedBlockDef = nil
				blockGhost.Parent = Hidden
				selectionHighlight.Parent = script
				return
			end
			selectedBlockDef = blockDef
			blockGhost.Parent = Environment.Ignore
			blockGhost.Color = Color.New(blockDef.Color.R, blockDef.Color.G, blockDef.Color.B, 0.5)
			local button = PlayerGUI.Main.Toolbars.Blocks[blockDef.Name:gsub("[%(%)]", "_")]
			selectionHighlight.Parent = button or Hidden
			wait(0.1)
			if sinkPlace == sp then
				sinkPlace = false
			end
		end
	end

	if key == Enums.KeyCode.MouseLeft and placementsPerSecond < 10 then
		wait(0.05)

		if selectedTool and selectedTool.LeftMouseDown then
			selectedTool:LeftMouseDown()
		end

		if selectedBlockDef and not sinkPlace then
			local plotPos = plotGround.Position
			local plotSize = plotGround.Size
			local plotRange = {
				Min = Vector3.New(plotPos.X - plotSize.X / 2, plotPos.Y, plotPos.Z - plotSize.Z / 2),
				Max = Vector3.New(plotPos.X + plotSize.X / 2, plotPos.Y + 128, plotPos.Z + plotSize.Z / 2),
			}

			local placementType: "invalid" | "plot" | "global" = "invalid"

			if Vector3InRange(insertPosition, plotRange) then
				placementType = "plot"
			elseif
				Vector3InRange(insertPosition, {
					Min = Vector3.New(-64, 0, -64),
					Max = Vector3.New(64, 64, 64),
				})
			then
				placementType = "global"
			end

			if placementType ~= "invalid" then
				local message = NetMessage.New()
				message:AddInt("BlockId", selectedBlockDef.Id)
				message:AddVector3("InsertPosition", insertPosition)
				message:AddString("PlacementType", placementType)
				networkPlaceBlock:InvokeServer(message)
				placementsPerSecond += 1
			else
				Chat:UnicastMessage("[ERROR]: You cannot place blocks there!", player)
			end
		end
	end
end)

Input.KeyUp:Connect(function(key: KeyCode, focused: boolean)
	if not focused then
		return
	end

	if key == Enums.KeyCode.MouseLeft and selectedTool and selectedTool.LeftMouseUp then
		wait(0.05)
		selectedTool:LeftMouseUp()
	end
end)

-- Load Blocks
for _, blockDef in Blocks.GetDefinitionsSorted() do
	local button: UIButton = script.UIButton:Clone(PlayerGUI.Main.Toolbars.Blocks)
	button.Name = blockDef.Name:gsub("[%(%)]", "_")
	button.Text = blockDef.Name
	button.UILabel.Text =
		`{blockDef.BindShifted and "^" or ""}{tostring(blockDef.Bind):split("")[#tostring(blockDef.Bind):split("")]}`
	button.UILabel.Visible = true
	button.MouseDown:Connect(function()
		local sp = tick()
		sinkPlace = sp
		Tools.SinkMouseFor(0.1)
		if selectedTool and selectedTool.Stop then
			selectedTool:Stop()
		end
		selectedTool = nil
		if selectedBlockDef == blockDef then
			selectedBlockDef = nil
			blockGhost.Parent = Hidden
			selectionHighlight.Parent = script
			return
		end
		selectedBlockDef = blockDef
		blockGhost.Parent = Environment.Ignore
		blockGhost.Color = Color.New(blockDef.Color.R, blockDef.Color.G, blockDef.Color.B, 0.5)
		selectionHighlight.Parent = button
		wait(0.1)
		if sinkPlace == sp then
			sinkPlace = false
		end
	end)
end

-- Load Tools
for _, tool in Tools.GetToolsSorted() do
	local button: UIButton = script.UIButton:Clone(PlayerGUI.Main.Toolbars.Tools)
	toolButtons[tool] = button
	button.Text = tool.Name
	local keycode: KeyCode = tool.Bind
	button.UILabel.Text = `{tostring(keycode):split(".")[2]}`
	button.UILabel.Visible = true
	button.MouseDown:Connect(function()
		Tools.SinkMouseFor(0.1)
		sinkPlace = tick()
		blockGhost.Parent = Hidden
		selectedBlockDef = nil
		if selectedTool and selectedTool.Stop then
			selectedTool:Stop()
		end
		if selectedTool == tool then
			selectedTool = nil
			selectionHighlight.Parent = script
			return
		end
		selectedTool = tool
		if selectedTool.Start then
			selectedTool:Start()
		end
		selectionHighlight.Parent = button
	end)
end

-- Placement rate limiting
while wait(1) do
	placementsPerSecond = 0
end
