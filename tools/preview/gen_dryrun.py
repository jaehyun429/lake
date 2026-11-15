"""서버 빌더 모듈을 모킹 환경에서 실행해 파트 목록(JSON)을 뽑는다.
사용: python3 gen_dryrun.py <project_dir> <out.json>
"""
import json, pathlib, re, subprocess, sys
proj = pathlib.Path(sys.argv[1]); out = pathlib.Path(sys.argv[2])
here = pathlib.Path(__file__).parent

def module(path, replacements):
    src = (proj / path).read_text()
    src = re.sub(r"^--!strict\s*$", "", src, flags=re.M)
    for pat, rep in replacements:
        src, n = re.subn(pat, rep, src)
        assert n >= 1, (path, pat)
    return "(function()\n" + src + "\nend)()"

prelude = (here / "mock_roblox.luau").read_text()
config = module("src/shared/Config.luau", [])
util = module("src/server/Util.luau", [])
shrine = module("src/server/ShrineBuilder.luau", [
    (r'require\(ReplicatedStorage\.DeadLake\.Shared\.Config\)', "__Config"),
    (r'require\(script\.Parent\.Util\)', "__Util"),
])
runner = r'''
local Config = __Config
local out = {}
local function dumpModel(model, tag)
	for _, inst in __ALL_INSTANCES do
		if inst:IsA("BasePart") then
			-- 모델 소속인지 확인
			local p = inst.Parent
			local inside = false
			while p do
				if p == model then inside = true break end
				p = p.Parent
			end
			if inside then
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = inst.CFrame:GetComponents()
				local col = inst.Color
				local shape = tostring(inst.Shape or "Enum.PartType.Block")
				table.insert(out, string.format(
					'{"tag":"%s","class":"%s","name":"%s","shape":"%s","size":[%.4f,%.4f,%.4f],"cf":[%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f],"color":[%.4f,%.4f,%.4f],"transparency":%.3f,"material":"%s"}',
					tag, inst.ClassName, inst.Name, shape, inst.Size.X, inst.Size.Y, inst.Size.Z,
					x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22,
					col.R, col.G, col.B, inst.Transparency or 0, tostring(inst.Material)))
			end
		end
	end
end
for i, def in Config.Map.Shrines do
	local model = Instance.new("Model")
	model.Name = "Shrine" .. i
	local c = def.Position
	local top = 0.25
	-- MapBuilder.buildShrine 이 만드는 바닥·수반을 흉내냄
	if def.Kind == "Cairn" then
		local g = Instance.new("Part"); g.Shape = Enum.PartType.Cylinder; g.Size = Vector3.new(0.25, 26, 26)
		g.CFrame = CFrame.new(c + Vector3.new(0, top - 0.125, 0)) * CFrame.Angles(0, 0, math.rad(90)); g.Color = Color3.fromRGB(62,60,58); g.Parent = model
	elseif def.Kind == "Ruin" then
		local g = Instance.new("Part"); g.Size = Vector3.new(16, 0.25, 15); g.CFrame = CFrame.new(c + Vector3.new(0, top - 0.125, 0)); g.Color = Color3.fromRGB(50,48,50); g.Parent = model
	else
		local g = Instance.new("Part"); g.Size = Vector3.new(22, 0.25, 22); g.CFrame = CFrame.new(c + Vector3.new(0, top - 0.125, 0)); g.Color = Color3.fromRGB(48,48,52); g.Parent = model
		local g2 = Instance.new("Part"); g2.Size = Vector3.new(14, 0.25, 14); g2.CFrame = CFrame.new(c + Vector3.new(0, top - 0.105, 0)); g2.Color = Color3.fromRGB(42,42,46); g2.Parent = model
	end
	local basin = Instance.new("Part"); basin.Shape = Enum.PartType.Cylinder; basin.Size = Vector3.new(3, 7, 7)
	basin.CFrame = CFrame.new(c + Vector3.new(0, top + 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)); basin.Color = Color3.fromRGB(30,30,34); basin.Parent = model
	-- 땅 (렌더용)
	local ground = Instance.new("Part"); ground.Size = Vector3.new(60, 0.2, 60); ground.CFrame = CFrame.new(c + Vector3.new(0, -0.1, 0)); ground.Color = Color3.fromRGB(30, 38, 28); ground.Parent = model
	local approach = {}
	local M = Config.Map
	for _, st in M.Stations do
		local shore = M.LakeCenter + st.Direction.Unit * (M.LakeRadius + M.BeachWidth + 1)
		local d = (shore - c) * Vector3.new(1, 0, 1)
		table.insert(approach, d.Unit)
	end
	for j, other in M.Shrines do
		if j ~= i then
			local d = (other.Position - c) * Vector3.new(1, 0, 1)
			table.insert(approach, d.Unit)
		end
	end
	local lights = __ShrineBuilder.decorate(def.Kind, model, c, top, approach, 7000 + i)
	table.insert(out, string.format('{"tag":"meta","name":"%s","lights":%d}', def.Name, #lights))
	dumpModel(model, def.Kind)
end
print("[" .. table.concat(out, ",\n") .. "]")
'''
full = prelude + "\nlocal __Config = " + config + "\nlocal __Util = " + util + "\nlocal __ShrineBuilder = " + shrine + "\n" + runner
(here / "dryrun_full.luau").write_text(full)
res = subprocess.run(["luau", str(here / "dryrun_full.luau")], capture_output=True, text=True)
sys.stderr.write(res.stderr)
if res.returncode != 0:
    sys.stderr.write(res.stdout[-3000:])
    sys.exit(res.returncode)
parts = json.loads(res.stdout)
out.write_text(json.dumps(parts))
from collections import Counter
print("parts:", len(parts), Counter(p["tag"] for p in parts))
