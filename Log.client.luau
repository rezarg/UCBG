local networkLog: NetworkEvent = ScriptService.Log

networkLog.InvokedClient:Connect(function(message: NetMessage)
	local content = message:GetString("Content")
	print(`[LOG]: {content}`)
end)
