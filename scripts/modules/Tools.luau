export type Tool = {
	Id: number,
	Name: string,
	Bind: KeyCode,
	Data: { [string]: any },
	Start: ((self: Tool) -> ())?,
	Stop: ((self: Tool) -> ())?,
	Update: ((self: Tool) -> ())?,
	LeftMouseDown: ((self: Tool) -> ())?,
	LeftMouseUp: ((self: Tool) -> ())?,
}

local Blocks = require(ScriptService.Blocks)

local networkSetPropertyOfUUID: NetworkEvent = ScriptService.SetPropertyOfUUID
local networkMakeConnection: NetworkEvent = ScriptService.MakeConnection
local networkDestroyBlock: NetworkEvent = ScriptService.DestroyBlock
local networkDestroyConnection: NetworkEvent = ScriptService.DestroyConnection
local networkPulseBlock: NetworkEvent = ScriptService.PulseBlock
local networkImport: NetworkEvent = ScriptService.Import
local networkMassDelete: NetworkEvent = ScriptService.MassDelete
local networkMassMove: NetworkEvent = ScriptService.MassMove

local networkGeneticEngineering: NetworkEvent = ScriptService.GeneticEngineering
local networkShortCircuit: NetworkEvent = ScriptService.ShortCircuit

local selectedBlocks = {}
local selectionMoveBase = Vector3.Zero

local selectionBox3D = Environment.Ignore.SelectionBox3D

local Tools = {}

function Tools.Init()
	Input.KeyDown:Connect(function(key: KeyCode, focused: boolean)
		if not focused then
			return
		end
		if key ~= Enums.KeyCode.MouseLeft then
			return
		end

		local inspectPanel: UIView = PlayerGUI.Main.InspectPanel
		if not inspectPanel.Visible then
			return
		end

		local mPos = Input.MousePosition
		local absPos = inspectPanel.AbsolutePosition
		local absSize = inspectPanel.AbsoluteSize

		if mPos.X < absPos.X or mPos.X > absPos.X + absSize.X then
			return
		end
		if mPos.Y < absPos.Y or mPos.Y > absPos.Y + absSize.Y then
			return
		end

		Tools.SinkMouseFor(0.05)
	end)
end

local Definitions: { [string]: Tool } = {}

function Tools.GetToolsSorted(): { Tool }
	local result = {}
	for _, tool in Tools.Definitions do
		result[tool.Id + 1] = tool
	end
	return result
end

local function SetProperty(uuid: number, property: string, varType: string, value: any, before: any)
	if varType == "number" then
		if not value then
			value = before
		end
		value = tostring(math.floor(tonumber(value) * 100) / 100)
		if not value then
			value = 0
		end
	end

	if property == "Label" then
		value = value:sub(1, 48)
	end

	local variant = Variant.New(value)

	local message = NetMessage.New()
	message:AddInt("UUID", uuid)
	message:AddString("Property", property)
	message:AddVariant("Value", variant)
	networkSetPropertyOfUUID:InvokeServer(message)

	return value
end

local function GetInstanceUUID(part: Part): number?
	local refData = part:FindChild("Data")
	if not refData then
		return nil
	end
	local data = json:parse(refData.Value)
	return data.UUID
end

local function GetInstanceProperties(part: Part): { [string]: number }?
	local data = json:parse(part.Data.Value)
	return data.Properties
end

local function GetInstanceOwner(part: Part): Player?
	if part.Parent == Environment.Blocks then
		local data = json:parse(part.Data.Value)
		return data.Owner and Players:GetPlayerByID(data.Owner) or nil
	elseif part.Parent == Environment.Connections then
		local ownerRef = part:FindChild("Owner")
		if ownerRef and ownerRef.Value and ownerRef.Value.Parent == Players then
			return ownerRef.Value
		end
	end

	return nil
end

local function SortKeys(dict: { [string]: any }): { [string]: any }
	local keys = {}
	for k, _ in dict do
		table.insert(keys, k)
	end
	table.sort(keys)
	local res = {}
	for i, k in keys do
		res[i] = k
	end
	return res
end

local function GridVector3(original: Vector3, grid: number?): Vector3
	if not grid then
		grid = 1
	end
	local x = math.round(original.X * grid) / grid
	local y = math.round(original.Y * grid) / grid
	local z = math.round(original.Z * grid) / grid

	return Vector3.New(x, y, z)
end

Tools.SinkMouseClicks = false
function Tools.SinkMouseFor(length: number)
	local smc = tick()
	Tools.SinkMouseClicks = smc
	spawn(function()
		wait(length)
		if Tools.SinkMouseClicks == smc then
			Tools.SinkMouseClicks = false
		end
	end)
end

Definitions.Connect = {
	Id = 0,
	Name = "Connect",
	Bind = Enums.KeyCode.C,
	Data = {},
	Start = function(self: Tool)
		selectionBox3D.Position = Vector3.Zero
		selectionBox3D.Size = Vector3.One
		selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
		selectionBox3D.Marker3D.AppearOnTop = false
		selectedBlocks = {}
		PlayerGUI.Main.TopbarText.Text = ""
	end,
	Stop = function(self: Tool)
		self.Data.FromUUID = nil
		self.Data.FromInstance = nil
		if self.Data.Connection then
			self.Data.Connection:Destroy()
			self.Data.Connection = nil
		end
	end,
	Update = function(self: Tool)
		if self.Data.Connection and self.Data.FromInstance then
			local mousePosition = Input:GetMouseWorldPosition({
				self.Data.IgnorePlayers and Players or Environment.Ignore,
				Environment.Connections,
				Environment.Ignore,
			})
			self.Data.Position = mousePosition

			local center = (mousePosition + self.Data.FromInstance.Position) / 2
			self.Data.Connection.Position = center
			self.Data.Connection:LookAt(mousePosition)

			local distance = (mousePosition - self.Data.FromInstance.Position).Magnitude
			self.Data.Connection.Size = Vector3.New(0.5, 0.5, distance)
		end
	end,
	LeftMouseDown = function(self: Tool)
		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result = Environment:Raycast(
			camera.Position,
			mousePosition - camera.Position,
			128,
			{ Players, Environment.Connections, Environment.Ignore }
		)
		if not result then
			return
		end

		local fromUUID = GetInstanceUUID(result.Instance)
		if not fromUUID then
			return
		end

		self.Data.FromInstance = result.Instance
		self.Data.FromUUID = fromUUID
		self.Data.Connection = Hidden.Connection:Clone(Environment.Ignore)
	end,
	LeftMouseUp = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end
		if not self.Data.Connection then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result = Environment:Raycast(camera.Position, mousePosition - camera.Position, 128, {
			self.Data.IgnorePlayers and Players or Environment.Ignore,
			Environment.Connections,
			Environment.Ignore,
		})
		if not result or not result.Instance then
			self.Data.FromUUID = nil
			self.Data.FromInstance = nil
			self.Data.Connection:Destroy()
			self.Data.Connection = nil
			return
		end

		if result.Instance:IsA("Player") then
			networkGeneticEngineering:InvokeServer()
			self.Data.FromUUID = nil
			self.Data.FromInstance = nil
			self.Data.Connection:Destroy()
			self.Data.Connection = nil
			self.Data.IgnorePlayers = true
			return
		end

		local toUUID = GetInstanceUUID(result.Instance)
		if not toUUID or toUUID == self.Data.FromUUID then
			if toUUID == self.Data.FromUUID then
				networkShortCircuit:InvokeServer()
			end
			self.Data.FromUUID = nil
			self.Data.FromInstance = nil
			self.Data.Connection:Destroy()
			self.Data.Connection = nil
			return
		end

		self.Data.Connection:Destroy()
		self.Data.Connection = nil

		local message = NetMessage.New()
		message:AddInt("From", self.Data.FromUUID)
		message:AddInt("To", toUUID)
		networkMakeConnection:InvokeServer(message)

		self.Data.FromUUID = nil
		self.Data.FromInstance = nil
	end,
}

Definitions.Inspect = {
	Id = 1,
	Name = "Inspect",
	Bind = Enums.KeyCode.V,
	Data = {},
	Start = function(self: Tool)
		selectionBox3D.Position = Vector3.Zero
		selectionBox3D.Size = Vector3.One
		selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
		selectionBox3D.Marker3D.AppearOnTop = false
		selectedBlocks = {}
		PlayerGUI.Main.TopbarText.Text = ""

		local inspectPanel: UIView = PlayerGUI.Main.InspectPanel
		local items: UIVLayout = inspectPanel.UIVLayout
		for _, v in items:GetChildren() do
			if not v:IsA("UIView") then
				continue
			end
			v:Destroy()
		end
		inspectPanel.Visible = true
	end,
	Stop = function(self: Tool)
		local inspectPanel = PlayerGUI.Main.InspectPanel
		inspectPanel.Visible = false
	end,
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result =
			Environment:Raycast(camera.Position, mousePosition - camera.Position, 128, { Players, Environment.Ignore })
		if not result then
			return
		end

		if result.Instance.Parent == Environment.Blocks then
			local uuid = GetInstanceUUID(result.Instance)
			if not uuid then
				return
			end

			local inspectPanel = PlayerGUI.Main.InspectPanel
			local items: UIVLayout = inspectPanel.UIVLayout

			for _, v in items:GetChildren() do
				if not v:IsA("UIView") then
					continue
				end
				v:Destroy()
			end

			local properties = GetInstanceProperties(result.Instance)
			if not properties then
				return
			end

			local keys = SortKeys(properties)

			local owner = GetInstanceOwner(result.Instance)
			local ownerItem = Hidden.PropertyReadOnly:Clone(items)
			ownerItem.Left.Text = "Owner: "
			if owner then
				ownerItem.Right.Text = owner.Name
			else
				local data = json:parse(result.Instance.Data.Value)
				ownerItem.Right.Text = `{data.Owner} (User Left)`
			end

			local nameItem = Hidden.PropertyReadOnly:Clone(items)
			nameItem.Left.Text = "Type: "

			local blockId = result.Instance.Name:split("_")[1]
			nameItem.Right.Text = Blocks.GetDefNameById(tonumber(blockId))

			for _, k in keys do
				local v = properties[k]

				local item: UIView = Hidden.Property:Clone(items)
				item.UILabel.Text = `{k}: `
				local input: UITextInput = item.UITextInput
				input.Text = v
				local varType = "any" -- TODO
				input.Placeholder = varType

				local before = nil
				input.FocusEnter:Connect(function()
					before = input.Text
				end)
				input.Submitted:Connect(function(_: string)
					input.Text = SetProperty(uuid, k, varType, input.Text, before)
				end)
				input.FocusExit:Connect(function()
					input.Text = SetProperty(uuid, k, varType, input.Text, before)
				end)
			end
		elseif result.Instance.Parent == Environment.Connections then
			local inspectPanel = PlayerGUI.Main.InspectPanel
			local items: UIVLayout = inspectPanel.UIVLayout

			for _, v in items:GetChildren() do
				if not v:IsA("UIView") then
					continue
				end
				v:Destroy()
			end

			local owner = GetInstanceOwner(result.Instance)
			local ownerItem = Hidden.PropertyReadOnly:Clone(items)
			ownerItem.Left.Text = "Owner: "
			ownerItem.Right.Text = owner and owner.Name or "(User Left)"

			local nameItem = Hidden.PropertyReadOnly:Clone(items)
			nameItem.Left.Text = "Type: "
			nameItem.Right.Text = "Connection"
		end
	end,
}

Definitions.Delete = {
	Id = 2,
	Name = "Delete",
	Bind = Enums.KeyCode.X,
	Data = {},
	Start = function(self: Tool)
		selectionBox3D.Position = Vector3.Zero
		selectionBox3D.Size = Vector3.One
		selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
		selectionBox3D.Marker3D.AppearOnTop = false
		selectedBlocks = {}
		PlayerGUI.Main.TopbarText.Text = ""
	end,
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result =
			Environment:Raycast(camera.Position, mousePosition - camera.Position, 128, { Players, Environment.Ignore })
		if not result then
			return
		end

		if result.Instance.Parent == Environment.Connections then
			local message = NetMessage.New()
			message:AddInstance("Instance", result.Instance)
			networkDestroyConnection:InvokeServer(message)
			return
		end

		local uuid = GetInstanceUUID(result.Instance)
		if not uuid then
			return
		end

		local message = NetMessage.New()
		message:AddInt("UUID", uuid)

		networkDestroyBlock:InvokeServer(message)
	end,
}

Definitions.Pulse = {
	Id = 3,
	Name = "Pulse",
	Bind = Enums.KeyCode.F,
	Data = {},
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result = Environment:Raycast(
			camera.Position,
			mousePosition - camera.Position,
			128,
			{ Players, Environment.Connections, Environment.Ignore }
		)
		if not result then
			return
		end

		local uuid = GetInstanceUUID(result.Instance)
		if not uuid then
			return
		end

		local message = NetMessage.New()
		message:AddInt("UUID", uuid)

		networkPulseBlock:InvokeServer(message)
	end,
}

Definitions.Select = {
	Id = 4,
	Name = "Select",
	Bind = Enums.KeyCode.E,
	Data = {},
	Start = function(self: Tool)
		PlayerGUI.Main.ExportSelection.Visible = #selectedBlocks > 0
		PlayerGUI.Main.DeleteSelection.Visible = #selectedBlocks > 0

		if self.Data.DidInit then
			return
		end
		self.Data.DidInit = true

		local exportButton: UIButton = PlayerGUI.Main.ExportSelection
		exportButton.MouseDown:Connect(function()
			Tools.SinkMouseFor(0.05)

			local result = {}

			result[1] = self.Data.MaxPoint.X - self.Data.MinPoint.X + 1
			result[2] = self.Data.MaxPoint.Y - self.Data.MinPoint.Y + 1
			result[3] = self.Data.MaxPoint.Z - self.Data.MinPoint.Z + 1

			result[4] = 0

			local objects = {}

			for _, v: Part in selectedBlocks do
				local object = {}

				local blockId = v.Name:split("_")[1]
				local offset = v.Position - self.Data.MinPoint

				local data = json:parse(v.Data.Value)
				object[1] = tonumber(blockId)
				object[2] = offset.X
				object[3] = offset.Y
				object[4] = offset.Z
				object[5] = data.UUID
				object[6] = GetInstanceProperties(v)
				object[7] = data.InputUUIDs
				object[8] = data.State

				table.insert(objects, object)
			end

			result[5] = objects

			local output = json:serialize(result)
			PlayerGUI.Main.ExportBox.Text = output
			PlayerGUI.Main.ExportBox.Visible = true
		end)

		local deleteButton: UIButton = PlayerGUI.Main.DeleteSelection
		deleteButton.MouseDown:Connect(function()
			Tools.SinkMouseFor(0.05)

			if deleteButton.Text == "u sure?" then
				self:Stop()
				local uuids = {}
				for _, v: Part in selectedBlocks do
					table.insert(uuids, GetInstanceUUID(v))
				end
				local message = NetMessage.New()
				message:AddString("Data", json:serialize(uuids))
				networkMassDelete:InvokeServer(message)
				selectionBox3D.Size = Vector3.One
				selectionBox3D.Position = Vector3.Zero
				selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
				selectionBox3D.Marker3D.AppearOnTop = false
				selectedBlocks = {}
				PlayerGUI.Main.TopbarText.Text = ""
			else
				deleteButton.Text = "u sure?"
				wait(3)
				deleteButton.Text = "Delete Selection"
			end
		end)
	end,
	Stop = function(self: Tool)
		PlayerGUI.Main.SelectionBox.Visible = false
		PlayerGUI.Main.ExportSelection.Visible = false
		PlayerGUI.Main.DeleteSelection.Visible = false
		PlayerGUI.Main.DeleteSelection.Text = "Delete Selection"
		PlayerGUI.Main.ExportBox.Visible = false
	end,
	Update = function(self: Tool)
		if not self.Data.CornerA then
			return
		end
		self.Data.CornerB = Input.MousePosition

		local x1 = math.min(self.Data.CornerA.X, self.Data.CornerB.X)
		local x2 = math.max(self.Data.CornerA.X, self.Data.CornerB.X)
		local y1 = math.min(self.Data.CornerA.Y, self.Data.CornerB.Y)
		local y2 = math.max(self.Data.CornerA.Y, self.Data.CornerB.Y)

		PlayerGUI.Main.SelectionBox.PositionOffset = Vector2.New(x1, y1)
		PlayerGUI.Main.SelectionBox.SizeOffset = Vector2.New(x2 - x1, y2 - y1)
	end,
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		self.Data.CornerA = Input.MousePosition
		PlayerGUI.Main.SelectionBox.SizeOffset = Vector2.Zero
		PlayerGUI.Main.SelectionBox.Visible = true

		self.Data.Selecting = true
	end,
	LeftMouseUp = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end
		if not self.Data.Selecting then
			return
		end
		if not self.Data.CornerA then
			self:Stop()
			return
		end
		self.Data.Selecting = false

		PlayerGUI.Main.SelectionBox.Visible = false
		self.Data.CornerB = Input.MousePosition

		local camera = Environment.CurrentCamera

		local x1 = math.min(self.Data.CornerA.X, self.Data.CornerB.X)
		local x2 = math.max(self.Data.CornerA.X, self.Data.CornerB.X)
		local y1 = math.min(self.Data.CornerA.Y, self.Data.CornerB.Y)
		local y2 = math.max(self.Data.CornerA.Y, self.Data.CornerB.Y)

		local function UpdateSelectionBox3D(selection: { Part })
			local minX = math.huge
			local maxX = -math.huge
			local minY = math.huge
			local maxY = -math.huge
			local minZ = math.huge
			local maxZ = -math.huge

			for i, block: Part in selection do
				if not block then
					continue -- Block deleted when looping selection (?)
				end
				minX = math.min(minX, block.Position.X)
				minY = math.min(minY, block.Position.Y)
				minZ = math.min(minZ, block.Position.Z)
				maxX = math.max(maxX, block.Position.X)
				maxY = math.max(maxY, block.Position.Y)
				maxZ = math.max(maxZ, block.Position.Z)
				if i % 200 == 0 and i ~= 0 then
					wait(1 / 40)
				end
			end

			selectedBlocks = selection
			selectionMoveBase = Vector3.New(minX, minY, minZ)
			self.Data.MinPoint = Vector3.New(minX, minY, minZ)
			self.Data.MaxPoint = Vector3.New(maxX, maxY, maxZ)

			if #selectedBlocks == 0 then
				selectionBox3D.Position = Vector3.Zero
				selectionBox3D.Size = Vector3.One
				selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
				selectionBox3D.Marker3D.AppearOnTop = false
				PlayerGUI.Main.TopbarText.Text = ""
			else
				selectionBox3D.Position = Vector3.New((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
				selectionBox3D.Size = Vector3.New(maxX - minX + 1.1, maxY - minY + 1.1, maxZ - minZ + 1.1)
				selectionBox3D.Marker3D.Size = Vector3.One
				selectionBox3D.Marker3D.Position = selectionBox3D.Position
					- (selectionBox3D.Size - Vector3.One * 1.1) / 2
				selectionBox3D.Marker3D.AppearOnTop = true
				local connectionCount = 0
				local connBuffer = {}
				for i, v in selectedBlocks do
					local data = json:parse(v.Data.Value)
					for _, v in data.InputUUIDs do
						if table.find(connBuffer, v) then
							continue
						end
						table.insert(connBuffer, v)
						connectionCount += 1
					end
					if i % 100 == 0 and i ~= 0 then
						wait(1 / 40)
					end
				end
				PlayerGUI.Main.TopbarText.Text =
					`Size: {maxX - minX + 1}, {maxY - minY + 1}, {maxZ - minZ + 1} | Blocks: {#selectedBlocks} | Connections: {connectionCount}`
			end
		end

		local sizeOfSelectionOnScreen = Vector2.Distance(Vector2.New(x1, y1), Vector2.New(x2, y2))
		if sizeOfSelectionOnScreen < 40 then
			local mousePosition = Input:GetMouseWorldPosition()
			local result = Environment:Raycast(
				camera.Position,
				mousePosition - camera.Position,
				128,
				{ Players, Environment.Connections, Environment.Ignore }
			)
			if not result or not result.Instance or result.Instance.Parent ~= Environment.Blocks then
				self:Stop()
				UpdateSelectionBox3D({})
				return
			end
			if not Input:GetButton("Shift").IsPressed then
				selectedBlocks = {}
			end
			if not table.find(selectedBlocks, result.Instance) then
				table.insert(selectedBlocks, result.Instance)
				UpdateSelectionBox3D(selectedBlocks)
				PlayerGUI.Main.ExportSelection.Visible = true
				PlayerGUI.Main.DeleteSelection.Visible = true
			end
			return
		end

		local selection = {}

		for i, block: Part in Environment.Blocks:GetChildren() do
			local viewportPoint
			local success, _ = pcall(function()
				viewportPoint = camera:WorldToViewportPoint(block.Position)
			end)
			if not success then
				continue
			end
			if viewportPoint.X < 0 or viewportPoint.X > 1 or viewportPoint.Y < 0 or viewportPoint.Y > 1 then
				continue -- Offscreen
			end
			local dir = (block.Position - camera.Position).Normalized
			local dot = dir:Dot(camera.Forward)
			if dot < 0 then
				continue -- Behind Camera
			end
			local screenPoint = camera:ViewportToScreenPoint(viewportPoint)
			local sX = screenPoint.X
			local sY = screenPoint.Y
			if sX > x1 and sX < x2 and sY > y1 and sY < y2 then
				table.insert(selection, block)
			end
			if i % 500 == 0 and i ~= 0 then
				wait()
			end
		end

		UpdateSelectionBox3D(selection)
		selectedBlocks = selection

		PlayerGUI.Main.ExportSelection.Visible = #selection > 0
		PlayerGUI.Main.DeleteSelection.Visible = #selection > 0
	end,
}

Definitions.Move = {
	Id = 5,
	Name = "Move",
	Bind = Enums.KeyCode.R,
	Data = {},
	Start = function(self: Tool)
		if self.Data.DidInit then
			return
		end
		self.Data.DidInit = true
		self.Data.CanMove = true
		self.Data.MoveOffset = Vector3.Zero

		local acceptMoveButton: UIButton = PlayerGUI.Main.AcceptMove
		acceptMoveButton.MouseDown:Connect(function()
			Tools.SinkMouseFor(0.05)

			acceptMoveButton.Visible = false
			self.Data.CanMove = false
			selectionMoveBase += self.Data.MoveOffset
			local _, _ = pcall(function()
				local selectedUUIDs = {}
				for i, v in selectedBlocks do
					local data = json:parse(v.Data.Value)
					table.insert(selectedUUIDs, data.UUID)
					if i % 100 == 0 and i ~= 0 then
						wait(1 / 30)
					end
				end
				local message = NetMessage.New()
				message:AddString("Data", json:serialize(selectedUUIDs))
				message:AddVector3("Offset", self.Data.MoveOffset)
				networkMassMove:InvokeServer(message)
			end)
			self.Data.MoveOffset = Vector3.Zero
			self.Data.CanMove = true
		end)
	end,
	Stop = function(self: Tool)
		PlayerGUI.Main.AcceptMove.Visible = false
		self.Data.MoveOffset = Vector3.Zero
		self.Data.CanMove = true
		if #selectedBlocks == 0 then
			return
		end
		selectionBox3D.Position = selectionMoveBase + (selectionBox3D.Size - Vector3.One * 1.1) / 2
	end,
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		if not self.Data.CanMove then
			return
		end
		if #selectedBlocks == 0 then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result = Environment:Raycast(
			camera.Position,
			mousePosition - camera.Position,
			128,
			{ Players, Environment.Connections, Environment.Ignore }
		)
		if not result then
			return
		end

		local gridPosition = GridVector3(result.Position + result.Normal * 0.5)
		self.Data.MoveOffset = gridPosition - selectionMoveBase

		PlayerGUI.Main.AcceptMove.Visible = true

		selectionBox3D.Position = gridPosition + (selectionBox3D.Size - Vector3.One * 1.1) / 2
	end,
}

Definitions.Import = {
	Id = 6,
	Name = "Import",
	Bind = Enums.KeyCode.P,
	Data = {},
	Start = function(self: Tool)
		PlayerGUI.Main.ImportBox.Visible = true

		if self.Data.DidInit then
			return
		end
		self.Data.DidInit = true

		local importButton: UIButton = PlayerGUI.Main.ImportBox.ImportButton
		importButton.MouseDown:Connect(function()
			local success, data = pcall(function(...)
				return json:parse(PlayerGUI.Main.ImportBox.Text)
			end)
			if not success or not data then
				PlayerGUI.Main.ImportBox.Text = "Invalid Import Data"
				return
			end

			self.Data.ChoosePosition = true
			self.Data.Size = Vector3.New(data[1], data[2], data[3]) + Vector3.One * 0.1
			self.Data.Position = GridVector3(Players.LocalPlayer.Position)

			selectionBox3D.Size = self.Data.Size
			selectionBox3D.Position = self.Data.Position + (self.Data.Size - Vector3.One * 1.1) / 2
			selectionBox3D.Marker3D.Size = Vector3.One
			selectionBox3D.Marker3D.Position = selectionBox3D.Position - (selectionBox3D.Size - Vector3.One * 1.1) / 2
			selectionBox3D.Marker3D.AppearOnTop = true

			PlayerGUI.Main.ImportBox.Visible = false
			PlayerGUI.Main.AcceptImport.Visible = true
		end)

		local acceptButton: UIButton = PlayerGUI.Main.AcceptImport
		acceptButton.MouseDown:Connect(function()
			self.Data.ChoosePosition = nil
			PlayerGUI.Main.AcceptImport.Visible = false
			PlayerGUI.Main.ImportBox.Visible = false
			selectionBox3D.Size = Vector3.One
			selectionBox3D.Position = Vector3.Zero
			selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
			selectionBox3D.Marker3D.AppearOnTop = false
			PlayerGUI.Main.TopbarText.Text = ""

			local message = NetMessage.New()
			message:AddString("Data", PlayerGUI.Main.ImportBox.Text)
			message:AddVector3("Position", self.Data.Position)
			networkImport:InvokeServer(message)
		end)
	end,
	Stop = function(self: Tool)
		PlayerGUI.Main.AcceptImport.Visible = false
		PlayerGUI.Main.ImportBox.Visible = false
		self.Data.ChoosePosition = nil
		selectionBox3D.Size = Vector3.One
		selectionBox3D.Position = Vector3.Zero
		selectionBox3D.Marker3D.LocalPosition = Vector3.Zero
		selectionBox3D.Marker3D.AppearOnTop = false
		PlayerGUI.Main.TopbarText.Text = ""
	end,
	LeftMouseDown = function(self: Tool)
		if Tools.SinkMouseClicks then
			return
		end

		if not self.Data.ChoosePosition then
			return
		end
		if not self.Data.Size then
			return
		end

		local mousePosition = Input:GetMouseWorldPosition()
		local camera = Environment.CurrentCamera

		local result = Environment:Raycast(
			camera.Position,
			mousePosition - camera.Position,
			128,
			{ Players, Environment.Connections, Environment.Ignore }
		)
		if not result then
			return
		end

		local gridPosition = GridVector3(result.Position + result.Normal * 0.5)
		self.Data.Position = gridPosition

		selectionBox3D.Size = self.Data.Size
		selectionBox3D.Position = gridPosition + (self.Data.Size - Vector3.One * 1.1) / 2
		selectionBox3D.Marker3D.Size = Vector3.One
		selectionBox3D.Marker3D.Position = selectionBox3D.Position - (selectionBox3D.Size - Vector3.One * 1.1) / 2
		selectionBox3D.Marker3D.AppearOnTop = true
	end,
}

Tools.Definitions = Definitions

return Tools
