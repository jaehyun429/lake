-- 서버용 공통 유틸: 파트 생성, 세그먼트, 트윈, 사운드
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Util = {}

function Util.part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	if props.Parent then
		p.Parent = props.Parent
	end
	return p
end

-- a 에서 b 까지 이어지는 막대 파트
function Util.segment(a: Vector3, b: Vector3, thickness: number, props: { [string]: any }): Part
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local up = if math.abs(dir.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local p = Util.part(props)
	p.Size = Vector3.new(thickness, thickness, math.max(len, 0.1))
	p.CFrame = CFrame.lookAt((a + b) / 2, b, up)
	return p
end

function Util.tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

function Util.sound(parent: Instance, id: string, props: { [string]: any }?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.6
	s.RollOffMaxDistance = 80
	s.RollOffMinDistance = 8
	if props then
		for k, v in props do
			(s :: any)[k] = v
		end
	end
	s.Parent = parent
	return s
end

-- 위치에서 일회성 효과음 재생
function Util.playAt(position: Vector3, id: string, volume: number?, pitch: number?)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	local s = Util.sound(holder, id, { Volume = volume or 0.8, PlaybackSpeed = pitch or 1 })
	s:Play()
	Debris:AddItem(holder, 6)
end

function Util.pointLight(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

function Util.billboard(parent: Instance, text: string, offsetY: number, size: UDim2?): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Size = size or UDim2.fromOffset(200, 40)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(220, 220, 210)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamMedium
	label.Parent = bb
	return label
end

return Util
