local Tools = require(ScriptService.Tools)
local Blocks = require(ScriptService.Blocks)

Tools.Init()

local camera: Camera = Environment.CurrentCamera

local selectedTool: Tools.Tool? = nil
local selectedBlockDef: Blocks.BlockDef? = nil
local insertPosition = Vector3.Zero

local blockGhost: Part = Environment.Ignore.BlockGhost
local selectionHighlight: UIStroke = script.UIStroke
local selectionFace: Model = Environment.Ignore.SelectionFace

local sinkPlace = false
local placementsPerSecond = 0

local networkPlaceBlock: NetworkEvent = ScriptService.PlaceBlock

local function GridVector3(original: Vector3, grid: number?): Vector3
	if not grid then
		grid = 1
	end
	local x = math.round(original.X * grid) / grid
	local y = math.round(original.Y * grid) / grid
	local z = math.round(original.Z * grid) / grid

	return Vector3.New(x, y, z)
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

local toolButtons = {}

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
			wait(0.1) -- Previously 0.3
			if sinkPlace == sp then
				sinkPlace = false
			end
		end
	end

	if key == Enums.KeyCode.MouseLeft and placementsPerSecond < 4 then
		wait(0.05)
		if selectedTool and selectedTool.LeftMouseDown then
			selectedTool:LeftMouseDown()
		end

		if selectedBlockDef and not sinkPlace then
			local distanceFromSpawn = Vector3.Distance(Vector3.Zero, insertPosition)
			if distanceFromSpawn < 16 then
				Chat:UnicastMessage("[Server]: Too close to spawn!", Players.LocalPlayer)
				return
			end

			local message = NetMessage.New()
			message:AddInt("BlockId", selectedBlockDef.Id)
			message:AddVector3("InsertPosition", insertPosition)
			networkPlaceBlock:InvokeServer(message)

			placementsPerSecond += 1
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
		wait(0.1) -- Previously 0.3
		if sinkPlace == sp then
			sinkPlace = false
		end
	end)
end

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

spawn(function()
	while wait(1) do
		placementsPerSecond = 0
	end
end)


-- Account datastore save manager
local networkSaveManager: NetworkEvent = ScriptService.SaveManager
local savePanel: UIView = PlayerGUI.Main.SaveManagerPanel
local saveNameInput: UITextInput = savePanel.SaveNameInput
local saveList: UIVLayout = savePanel.SaveList.SaveListContent
local saveRowTemplate: UIButton = savePanel.SaveRowTemplate
local adminBuildList: UIVLayout = savePanel.AdminBuildList.AdminBuildListContent
local adminBuildRowTemplate: UIButton = savePanel.AdminBuildRowTemplate
local saveStatus: UILabel = savePanel.SaveManagerStatus
local adminUserIdInput: UITextInput = savePanel.AdminUserIdInput
local admins = require(ScriptService.Admins)

local selectedSaveId = nil
local selectedAdminBuildId = nil
local selectedOwnerId = tostring(Players.LocalPlayer.UserID)
local viewingOtherAccount = false
local saveRows = {}
local adminBuildRows = {}
local currentAdminBuilds = {}
local copyChunks = {}
local expectedCopyChunks = 0

local function SendSaveRequest(operation: string, fileId: string?, name: string?, targetUserId: string?)
	local message = NetMessage.New()
	message:AddString("Operation", operation)
	message:AddString("FileID", fileId or "")
	message:AddString("Name", name or "")
	message:AddString("TargetUserID", targetUserId or "")
	networkSaveManager:InvokeServer(message)
end

local function ClearList(list: UIVLayout, template: UIButton)
	for _, child in list:GetChildren() do
		if child ~= template then
			child:Destroy()
		end
	end
end

local function ClearSaveRows()
	ClearList(saveList, saveRowTemplate)
	ClearList(adminBuildList, adminBuildRowTemplate)
	saveRows = {}
	adminBuildRows = {}
	selectedSaveId = nil
	selectedAdminBuildId = nil
end

local function SelectPersonalRow(fileId: string, fileName: string)
	selectedSaveId = fileId
	selectedAdminBuildId = nil
	saveStatus.Text = `Selected personal save: {fileName}`
	for id, otherRow in saveRows do
		otherRow.Color = id == selectedSaveId and Color.New(0.15, 0.35, 0.55, 1) or Color.New(0.13, 0.13, 0.13, 0.9)
	end
	for _, otherRow in adminBuildRows do
		otherRow.Color = Color.New(0.13, 0.13, 0.13, 0.9)
	end
end

local function SelectAdminBuildRow(fileId: string, fileName: string)
	selectedSaveId = nil
	selectedAdminBuildId = fileId
	saveStatus.Text = `Selected Admin Build: {fileName} (permanent)`
	for _, otherRow in saveRows do
		otherRow.Color = Color.New(0.13, 0.13, 0.13, 0.9)
	end
	for id, otherRow in adminBuildRows do
		otherRow.Color = id == selectedAdminBuildId and Color.New(0.15, 0.35, 0.55, 1) or Color.New(0.13, 0.13, 0.13, 0.9)
	end
end

local function DisplayAdminBuilds(builds)
	ClearList(adminBuildList, adminBuildRowTemplate)
	adminBuildRows = {}
	currentAdminBuilds = builds or {}
	selectedAdminBuildId = nil
	for _, file in currentAdminBuilds do
		local fileId = tostring(file.Id)
		local row: UIButton = adminBuildRowTemplate:Clone(adminBuildList)
		row.Name = `AdminBuild_{fileId}`
		row.Visible = true
		row.Text = `{file.Name}  |  {file.Bytes} bytes  |  {file.Chunks} keys`
		adminBuildRows[fileId] = row
		row.MouseDown:Connect(function()
			SelectAdminBuildRow(fileId, file.Name)
		end)
	end
	adminBuildList.SizeOffset = Vector2.New(294, math.max(190, #currentAdminBuilds * 30))
end

local function DisplaySaveFiles(files, ownerId: string, adminBuilds)
	adminBuilds = adminBuilds or currentAdminBuilds or {}
	ClearSaveRows()
	selectedOwnerId = ownerId
	for _, file in files do
		local fileId = tostring(file.Id)
		local row: UIButton = saveRowTemplate:Clone(saveList)
		row.Name = `Save_{fileId}`
		row.Visible = true
		row.Text = `{file.Name}  |  {file.Bytes} bytes  |  {file.Chunks} keys`
		saveRows[fileId] = row
		row.MouseDown:Connect(function()
			SelectPersonalRow(fileId, file.Name)
		end)
	end
	saveList.SizeOffset = Vector2.New(294, math.max(190, #files * 30))
	DisplayAdminBuilds(adminBuilds or currentAdminBuilds)

	if #files == 0 and #(adminBuilds or {}) == 0 then
		saveStatus.Text = "No personal saves or Admin Builds were found."
	elseif #files == 0 then
		saveStatus.Text = `No personal saves. Found {#adminBuilds} permanent Admin Builds.`
	elseif #(adminBuilds or {}) == 0 then
		saveStatus.Text = `Found {#files} personal saves. No Admin Builds are published yet.`
	else
		saveStatus.Text = `Found {#files} personal saves and {#adminBuilds} permanent Admin Builds.`
	end
end

local function OpenSaveManager()
	savePanel.Visible = true
	local isAdmin = admins[Players.LocalPlayer.UserID] == true
	adminUserIdInput.Visible = isAdmin
	savePanel.AdminToolsLabel.Visible = isAdmin
	savePanel.AdminSearchSaves.Visible = isAdmin
	savePanel.AdminBackToOwnSaves.Visible = isAdmin
	savePanel.PublishAdminBuild.Visible = isAdmin
	viewingOtherAccount = false
	selectedOwnerId = tostring(Players.LocalPlayer.UserID)
	SendSaveRequest("List")
end

PlayerGUI.Main.LoadFromDatastore.MouseDown:Connect(function()
	OpenSaveManager()
end)

savePanel.CloseSaveManager.MouseDown:Connect(function()
	savePanel.Visible = false
end)

savePanel.SaveFileButton.MouseDown:Connect(function()
	if viewingOtherAccount then
		saveStatus.Text = "Switch back to My Saves before saving."
		return
	end
	SendSaveRequest("Save", nil, saveNameInput.Text)
	saveStatus.Text = "Saving the current world to your account..."
end)

savePanel.PublishAdminBuild.MouseDown:Connect(function()
	if admins[Players.LocalPlayer.UserID] ~= true then
		return
	end
	SendSaveRequest("GlobalSave", nil, saveNameInput.Text)
	saveStatus.Text = "Publishing a permanent global Admin Build..."
end)

savePanel.RefreshSavesButton.MouseDown:Connect(function()
	if viewingOtherAccount and admins[Players.LocalPlayer.UserID] then
		SendSaveRequest("AdminList", nil, nil, selectedOwnerId)
	else
		SendSaveRequest("List")
	end
	saveStatus.Text = "Refreshing personal saves and Admin Builds..."
end)

savePanel.LoadSelectedSave.MouseDown:Connect(function()
	if selectedAdminBuildId then
		SendSaveRequest("GlobalLoad", selectedAdminBuildId)
		saveStatus.Text = "Loading the selected Admin Build..."
		return
	end
	if not selectedSaveId then
		saveStatus.Text = "Select a personal save or Admin Build first."
		return
	end
	if viewingOtherAccount then
		saveStatus.Text = "You can inspect or copy another account's saves, but cannot load them directly."
		return
	end
	SendSaveRequest("Load", selectedSaveId)
	saveStatus.Text = "Loading the selected save into the world..."
end)

savePanel.RenameSelectedSave.MouseDown:Connect(function()
	if selectedAdminBuildId then
		saveStatus.Text = "Admin Builds are published as permanent global files and cannot be renamed here."
		return
	end
	if viewingOtherAccount then
		saveStatus.Text = "Admins cannot rename another account's saves."
		return
	end
	if not selectedSaveId then
		saveStatus.Text = "Select a personal save first."
		return
	end
	SendSaveRequest("Rename", selectedSaveId, saveNameInput.Text)
	saveStatus.Text = "Renaming saved file..."
end)

savePanel.DeleteSelectedSave.MouseDown:Connect(function()
	if selectedAdminBuildId then
		saveStatus.Text = "Admin Builds are permanent and cannot be deleted."
		return
	end
	if not selectedSaveId then
		saveStatus.Text = "Select a personal save first."
		return
	end
	if viewingOtherAccount then
		SendSaveRequest("AdminDelete", selectedSaveId, nil, selectedOwnerId)
	else
		SendSaveRequest("Delete", selectedSaveId)
	end
	saveStatus.Text = "Deleting saved file..."
end)

savePanel.CopySelectedSave.MouseDown:Connect(function()
	if selectedAdminBuildId then
		SendSaveRequest("GlobalCopy", selectedAdminBuildId)
	elseif selectedSaveId then
		if viewingOtherAccount then
			SendSaveRequest("AdminCopy", selectedSaveId, nil, selectedOwnerId)
		else
			SendSaveRequest("Copy", selectedSaveId)
		end
	else
		saveStatus.Text = "Select a personal save or Admin Build first."
		return
	end
	saveStatus.Text = "Retrieving the original import data for copying..."
end)

savePanel.AdminSearchSaves.MouseDown:Connect(function()
	if not admins[Players.LocalPlayer.UserID] then
		return
	end
	local targetId = adminUserIdInput.Text:gsub("%s", "")
	if targetId == "" then
		saveStatus.Text = "Enter the account UserID to inspect."
		return
	end
	viewingOtherAccount = targetId ~= tostring(Players.LocalPlayer.UserID)
	selectedOwnerId = targetId
	SendSaveRequest("AdminList", nil, nil, targetId)
	saveStatus.Text = `Loading personal saves for UserID {targetId}...`
end)

savePanel.AdminBackToOwnSaves.MouseDown:Connect(function()
	viewingOtherAccount = false
	selectedOwnerId = tostring(Players.LocalPlayer.UserID)
	SendSaveRequest("List")
	saveStatus.Text = "Loading your saved files..."
end)

networkSaveManager.InvokedClient:Connect(function(message: NetMessage)
	local operation = message:GetString("Operation")
	local status = message:GetString("Status")
	local messageText = message:GetString("Message")
	saveStatus.Text = messageText

	if status ~= "Success" then
		return
	end

	if operation == "List" or operation == "AdminList" or operation == "Save" or operation == "Rename" or operation == "Delete" or operation == "AdminDelete" then
		local success, files = pcall(function()
			return json:parse(message:GetString("Files"))
		end)
		local adminBuildSuccess, adminBuilds = pcall(function()
			local value = message:GetString("AdminBuilds")
			if value == "" then
				return nil
			end
			return json:parse(value)
		end)
		if success and type(files) == "table" then
			local ownerId = message:GetString("OwnerID")
			if ownerId == "" then
				ownerId = tostring(Players.LocalPlayer.UserID)
			end
			DisplaySaveFiles(files, ownerId, adminBuildSuccess and type(adminBuilds) == "table" and adminBuilds or currentAdminBuilds)
		end
	elseif operation == "GlobalSave" then
		local success, adminBuilds = pcall(function()
			return json:parse(message:GetString("AdminBuilds"))
		end)
		if success and type(adminBuilds) == "table" then
			DisplayAdminBuilds(adminBuilds)
		end
	elseif operation == "CopyStart" then
		copyChunks = {}
		expectedCopyChunks = message:GetInt("ChunkCount")
		saveStatus.Text = message:GetString("Message")
	elseif operation == "CopyChunk" then
		local chunkIndex = message:GetInt("ChunkIndex")
		copyChunks[chunkIndex] = message:GetString("Data")
	elseif operation == "CopyEnd" then
		for chunkIndex = 1, expectedCopyChunks do
			if not copyChunks[chunkIndex] then
				saveStatus.Text = "Copy failed because a data chunk was missing."
				return
			end
		end
		PlayerGUI.Main.ExportBox.Text = table.concat(copyChunks)
		PlayerGUI.Main.ExportBox.Visible = true
		savePanel.Visible = false
		PlayerGUI.Main.TopbarText.Text = "Original import data is ready. Click the text box, press Ctrl+A, then Ctrl+C."
		copyChunks = {}
		expectedCopyChunks = 0
	end
end)
