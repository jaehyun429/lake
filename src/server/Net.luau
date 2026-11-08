-- RemoteEvent 래퍼. 클라이언트↔서버는 (kind: string, data: any) 형태로만 통신합니다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("DeadLake"):WaitForChild("Remotes")
local toServer = remotes:WaitForChild("ToServer") :: RemoteEvent
local toClient = remotes:WaitForChild("ToClient") :: RemoteEvent

local Net = {}
local handlers: { [string]: (Player, any) -> () } = {}

function Net.on(kind: string, fn: (Player, any) -> ())
	handlers[kind] = fn
end

toServer.OnServerEvent:Connect(function(player, kind, data)
	if type(kind) ~= "string" then
		return
	end
	local h = handlers[kind]
	if h then
		h(player, data)
	end
end)

function Net.send(player: Player, kind: string, data: any?)
	toClient:FireClient(player, kind, data)
end

function Net.broadcast(kind: string, data: any?)
	toClient:FireAllClients(kind, data)
end

function Net.notify(player: Player, text: string, seconds: number?)
	Net.send(player, "Notify", { Text = text, Time = seconds or 3 })
end

function Net.notifyAll(text: string, seconds: number?)
	Net.broadcast("Notify", { Text = text, Time = seconds or 3 })
end

return Net
