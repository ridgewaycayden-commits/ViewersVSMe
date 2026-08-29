local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local InstancePool = require(script.Parent.Parent.InstancePool)
local RoadProfile = require(script.Parent.Parent.RoadProfile)
local SpatialQuery = require(script.Parent.Parent.SpatialQuery)

local PropBuilder = {}

-- Telemetry counters for precomputed vs runtime prop rendering
local precomputedPropCount = 0
local runtimePropCount = 0

-- Known conifer genera/species: used to infer needleleaved canopy shape
-- when leafType is not explicitly set in the manifest.
local CONIFER_SPECIES_PATTERNS = {
    "pinus",
    "picea",
    "abies",
    "spruce",
    "fir",
    "cedar",
    "juniper",
    "cypress",
    "larch",
    "hemlock",
    "yew",
    "redwood",
    "sequoia",
    "conifer",
    "juniperus",
}

local pools = {}
local ROADSIDE_EXTRA_OFFSETS = {
    street_lamp = 0.75,
    bus_stop = 1.5,
    traffic_signal = 0.5,
    fire_hydrant = 1.0,
    waste_basket = 0.5,
}

local function getPrefabFolder()
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then
        return nil
    end

    return assetsFolder:FindFirstChild("Prefabs")
end

local function getPropDetailParent(parent)
    local detailFolder = parent:FindFirstChild("Detail")
    if detailFolder then
        return detailFolder
    end

    detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = parent
    return detailFolder
end

local function hashId(id)
    local h = 5381
    for i = 1, #id do
        h = ((h * 33) + string.byte(id, i)) % 2147483647
    end
    return h
end

local function deterministicUnitFloat(seed)
    local nextSeed = (seed * 48271) % 2147483647
    return nextSeed / 2147483647
end

local function resolveBaseY(_chunk, _worldX, fallbackY, _worldZ)
    return fallbackY
end

local function alignRoadsideProp(prop, chunk, originStuds, wx, wz)
    if not chunk or not chunk.roads then
        return wx, wz
    end

    local nearestRoad = SpatialQuery.findNearestRoadSegment(chunk.roads, originStuds, wx, wz)
    if not nearestRoad then
        return wx, wz
    end

    local snapThreshold = math.max(2, nearestRoad.width * 0.35)
    if nearestRoad.distance > snapThreshold then
        return wx, wz
    end

    local normalX = -nearestRoad.dirZ
    local normalZ = nearestRoad.dirX
    local side = (wx - nearestRoad.projX) * normalX + (wz - nearestRoad.projZ) * normalZ
    if math.abs(side) < 0.01 then
        side = (hashId(prop.id or prop.kind) % 2 == 0) and 1 or -1
    else
        side = side > 0 and 1 or -1
    end

    local sidewalk = RoadProfile.getSidewalkWidth(nearestRoad.road, nearestRoad.width)
    local edgeBuffer = RoadProfile.getEdgeBufferWidth(nearestRoad.road, nearestRoad.width)
    local extraOffset = ROADSIDE_EXTRA_OFFSETS[prop.kind] or 0.5
    local offset = nearestRoad.width * 0.5 + sidewalk + edgeBuffer + extraOffset

    return nearestRoad.projX + normalX * offset * side, nearestRoad.projZ + normalZ * offset * side
end

local METERS_TO_STUDS = 1 / 0.3 -- ~3.33 studs per meter

local SPECIES_COLOR = {
    -- Conifers (dark green)
    conifer = BrickColor.new("Dark green"),
    pinus = BrickColor.new("Dark green"),
    picea = BrickColor.new("Dark green"),
    abies = BrickColor.new("Dark green"),
    juniperus = BrickColor.new("Dark green"),
    needleleaved = BrickColor.new("Dark green"),
    -- Palms (tropical)
    palm = BrickColor.new("Bright yellow"),
    phoenix = BrickColor.new("Bright yellow"),
    washingtonia = BrickColor.new("Bright yellow"),
    sabal = BrickColor.new("Bright yellow"),
    -- Oaks (medium green, common in Austin)
    quercus = BrickColor.new("Bright green"),
    oak = BrickColor.new("Bright green"),
    ["live oak"] = BrickColor.new("Olive green"),
    ["quercus virginiana"] = BrickColor.new("Olive green"),
    -- Deciduous broadleaf (medium)
    broadleaved_deciduous = BrickColor.new("Bright green"),
    maple = BrickColor.new("Bright orange"),
    acer = BrickColor.new("Bright orange"),
    elm = BrickColor.new("Lime green"),
    ulmus = BrickColor.new("Lime green"),
    -- Evergreen broadleaf
    broadleaved_evergreen = BrickColor.new("Olive green"),
    -- Fruit/flowering trees
    prunus = BrickColor.new("Pink"),
    magnolia = BrickColor.new("Dark green"),
    -- Austin-specific species
    pecan = BrickColor.new("Olive"),
    cypress = BrickColor.new("Forest green"),
    mesquite = BrickColor.new("Sage green"),
    crepe_myrtle = BrickColor.new("Lavender"),
    cedar = BrickColor.new("Dark green"),
    ash = BrickColor.new("Lime green"),
    birch = BrickColor.new("Lime green"),
    willow = BrickColor.new("Olive"),
    cottonwood = BrickColor.new("Bright green"),
    hackberry = BrickColor.new("Olive"),
    sycamore = BrickColor.new("Lime green"),
    -- Default (Austin's mix of live oak + cedar)
    default = BrickColor.new("Bright green"),
}

local SPECIES_SCALE = {
    conifer = 0.7,
    palm = 0.5,
    oak = 1.2,
    quercus = 1.2,
    -- Austin-specific species
    magnolia = 1.1,
    pecan = 1.3,
    cypress = 0.8,
    mesquite = 0.7,
    crepe_myrtle = 0.6,
    cedar = 0.9,
    elm = 1.2,
    ash = 1.0,
    birch = 0.8,
    willow = 1.4,
    cottonwood = 1.3,
    hackberry = 1.0,
    sycamore = 1.3,
    default = 1.0,
}

local function getCanopyColor(species)
    if not species then
        return SPECIES_COLOR.default
    end
    local s = species:lower()
    -- Try exact match first
    if SPECIES_COLOR[s] then
        return SPECIES_COLOR[s]
    end
    -- Try prefix match
    for key, color in pairs(SPECIES_COLOR) do
        if s:find(key, 1, true) then
            return color
        end
    end
    return SPECIES_COLOR.default
end

-- Per-tree hash-driven hue/saturation/value jitter applied on top of the
-- species canopy color. Rotates hue within a bounded green-centric window so
-- no two neighbouring trees read the same, without sliding off-palette.
-- The jitter is deterministic from the prop id so re-imports are stable.
local function jitterCanopyColor(color, propId)
    local seed = hashId(propId or "tree")
    local h, s, v = Color3.toHSV(color)
    local hueDelta = (deterministicUnitFloat(seed) - 0.5) * 0.10 -- +/- 5% (~18 deg)
    local satDelta = (deterministicUnitFloat(seed + 17) - 0.5) * 0.18
    local valDelta = (deterministicUnitFloat(seed + 31) - 0.5) * 0.16
    h = (h + hueDelta) % 1
    if h < 0 then
        h += 1
    end
    s = math.clamp(s + satDelta, 0.15, 1)
    v = math.clamp(v + valDelta, 0.18, 1)
    return Color3.fromHSV(h, s, v)
end

local function getCanopyScale(species)
    if not species then
        return 1.0
    end
    local s = species:lower()
    -- Try exact match first
    if SPECIES_SCALE[s] then
        return SPECIES_SCALE[s]
    end
    -- Try prefix match
    for key, scale in pairs(SPECIES_SCALE) do
        if s:find(key, 1, true) then
            return scale
        end
    end
    return 1.0
end

local function getTreeScale(prop)
    if prop.height and prop.height > 0 then
        -- Convert real-world meters to studs, then scale relative to default 20-stud tree
        local heightStuds = prop.height * METERS_TO_STUDS
        return math.clamp(heightStuds / 20, 0.5, 3.0)
    end
    return getCanopyScale(prop.species)
end

local function getOrCreatePool(kind)
    if pools[kind] then
        return pools[kind]
    end

    -- Strategy: Use prefabs from ReplicatedStorage if they exist, otherwise use generic placeholders
    local prefabFolder = getPrefabFolder()
    local prefab = if prefabFolder then prefabFolder:FindFirstChild(kind) else nil
    if prefab then
        pools[kind] = InstancePool.new(prefab)
    else
        -- Placeholder models
        pools[kind] = InstancePool.new("Model")
    end

    return pools[kind]
end

local function buildStreetLamp(x, y, z, parent)
    local model = Instance.new("Model")
    model.Name = "StreetLamp"
    model.Parent = parent

    -- Main pole (cylinder standing upright)
    local pole = Instance.new("Part")
    pole.Name = "Pole"
    pole.Shape = Enum.PartType.Cylinder
    pole.Anchored = true
    pole.Size = Vector3.new(12, 0.4, 0.4)
    pole.CFrame = CFrame.new(x, y + 6, z) * CFrame.Angles(0, 0, math.pi / 2)
    pole.Material = Enum.Material.Metal
    pole.Color = Color3.fromRGB(70, 70, 75)
    pole.CastShadow = false
    pole.Parent = model

    -- Arm (angled bracket extending from top)
    local arm = Instance.new("Part")
    arm.Name = "Arm"
    arm.Anchored = true
    arm.Size = Vector3.new(0.2, 0.2, 3)
    arm.CFrame = CFrame.new(x + 1, y + 12, z) * CFrame.Angles(0, 0, math.rad(-20))
    arm.Material = Enum.Material.Metal
    arm.Color = Color3.fromRGB(70, 70, 75)
    arm.CastShadow = false
    arm.Parent = model

    -- Lamp housing (flattened ball for lantern silhouette)
    local head = Instance.new("Part")
    head.Name = "LightHead"
    head.Shape = Enum.PartType.Ball
    head.Anchored = true
    head.Size = Vector3.new(1.5, 0.8, 1.5)
    head.CFrame = CFrame.new(x + 2, y + 11.8, z)
    head.Material = Enum.Material.Neon
    head.Color = Color3.fromRGB(255, 244, 214)
    head.CastShadow = false
    head.Parent = model

    -- Point light
    local light = Instance.new("PointLight")
    light.Brightness = 1.5
    light.Range = 40
    light.Color = Color3.fromRGB(255, 240, 210)
    light.Shadows = true
    light.Parent = head

    CollectionService:AddTag(head, "StreetLight")
    CollectionService:AddTag(head, "LOD_Detail")

    return model
end

-- Builds a multi-lobe canopy cluster for organic broadleaved silhouette.
-- Uses a seed-driven Y/X ratio so trees are not all perfect spheres:
-- some are wide & flat (live oaks), others taller & rounder.
local function buildRealisticCanopy(parent, trunkTop, canopyRadius, canopyColor, species)
    local seed = hashId(species or "tree")
    -- Derive a per-species aspect ratio: Y/X from 0.55 (wide flat) to 1.1 (tall round)
    local aspectY = 0.55 + deterministicUnitFloat(seed) * 0.55

    -- Main canopy body
    local mainLobe = Instance.new("Part")
    mainLobe.Name = "CanopyMain"
    mainLobe.Shape = Enum.PartType.Ball
    mainLobe.Size = Vector3.new(canopyRadius * 2, canopyRadius * 2 * aspectY, canopyRadius * 2)
    mainLobe.Material = Enum.Material.LeafyGrass
    mainLobe.Color = canopyColor
    mainLobe.Anchored = true
    mainLobe.CanCollide = false
    mainLobe.CastShadow = true
    mainLobe.CFrame = CFrame.new(trunkTop + Vector3.new(0, canopyRadius * aspectY * 0.5, 0))
    mainLobe.Parent = parent

    -- 3-4 secondary lobes offset from center for organic shape
    local lobeCount = 3 + (seed % 2) -- 3 or 4 lobes
    for i = 1, lobeCount do
        local angle = (i / lobeCount) * math.pi * 2 + seed * 0.7
        local offsetX = math.cos(angle) * canopyRadius * 0.45
        local offsetZ = math.sin(angle) * canopyRadius * 0.45
        local offsetY = (i % 2 == 0) and canopyRadius * 0.25 or -canopyRadius * 0.12
        local lobeFrac = 0.55 + deterministicUnitFloat(seed + i * 137) * 0.25
        local lobeSize = canopyRadius * lobeFrac

        local lobe = Instance.new("Part")
        lobe.Name = "CanopyLobe" .. i
        lobe.Shape = Enum.PartType.Ball
        -- Each lobe gets its own aspect variation
        local lobeAspect = aspectY * (0.85 + (i % 3) * 0.1)
        lobe.Size = Vector3.new(lobeSize * 2, lobeSize * 2 * lobeAspect, lobeSize * 2)
        lobe.Material = Enum.Material.LeafyGrass
        -- Slight colour variation per lobe
        lobe.Color = Color3.new(
            math.clamp(canopyColor.R + (i * 0.03 - 0.05), 0, 1),
            math.clamp(canopyColor.G + (i * 0.02 - 0.03), 0, 1),
            math.clamp(canopyColor.B + (i * 0.01 - 0.02), 0, 1)
        )
        lobe.Anchored = true
        lobe.CanCollide = false
        lobe.CastShadow = true
        lobe.CFrame = CFrame.new(trunkTop.X + offsetX, trunkTop.Y + canopyRadius * aspectY * 0.5 + offsetY, trunkTop.Z + offsetZ)
        lobe.Parent = parent
    end
end

--- EditableMesh vertex-normal support probe (same pattern as BuildingBuilder).
local editableMeshSetVertexNormalSupported = nil

local function trySetVertexNormal(mesh, vertexId, normal)
    if editableMeshSetVertexNormalSupported == false then
        return
    end
    if editableMeshSetVertexNormalSupported == nil then
        local ok = pcall(function()
            mesh:SetVertexNormal(vertexId, normal)
        end)
        editableMeshSetVertexNormalSupported = ok
        return
    end
    pcall(function()
        mesh:SetVertexNormal(vertexId, normal)
    end)
end

--- Load a Rust pre-computed prop mesh (flat arrays identical to shellMesh/roadMesh format)
--- into a standalone MeshPart.
--- meshData = { vertices = {x,y,z,...}, triangles = {v0,v1,v2,...}, normals = {nx,ny,nz,...} }
--- Vertices are in chunk-local coordinates; originStuds offsets to world space.
--- Triangle indices are 0-based (Rust convention).
function PropBuilder.loadPrecomputedPropMesh(meshData, position, yawDegrees, scale, originStuds)
    local verts = meshData.vertices
    local tris = meshData.triangles
    local norms = meshData.normals
    if not verts or not tris or #verts < 3 or #tris < 3 then
        return nil
    end

    local meshOk, mesh = pcall(function()
        return AssetService:CreateEditableMesh()
    end)
    if not meshOk or not mesh then
        warn("[PropBuilder] CreateEditableMesh failed: " .. tostring(mesh))
        return nil
    end

    -- Add vertices in tree-local space (origin is applied at part.CFrame below).
    -- Rust build_tree_mesh emits vertices with tree base at (0,0,0); adding
    -- originStuds here would double-offset since CreateMeshPartAsync derives
    -- its own part pivot from the mesh AABB.
    local vertexIds = {}
    for i = 1, #verts, 3 do
        local idx = (i - 1) / 3 + 1
        local pos = Vector3.new(verts[i], verts[i + 1], verts[i + 2])
        vertexIds[idx] = mesh:AddVertex(pos)
        local normal = if norms and #norms >= i + 2
            then Vector3.new(norms[i], norms[i + 1], norms[i + 2])
            else Vector3.new(0, 1, 0)
        trySetVertexNormal(mesh, vertexIds[idx], normal)
    end

    -- Add triangles (convert 0-based Rust indices to 1-based vertex ID refs)
    for i = 1, #tris, 3 do
        local v0 = vertexIds[tris[i] + 1]
        local v1 = vertexIds[tris[i + 1] + 1]
        local v2 = vertexIds[tris[i + 2] + 1]
        if v0 and v1 and v2 then
            mesh:AddTriangle(v0, v1, v2)
        end
    end

    -- Create MeshPart from the EditableMesh
    local partOk, part = pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
    end)
    if not partOk or not part then
        warn("[PropBuilder] CreateMeshPartAsync failed: " .. tostring(part))
        return nil
    end

    -- Position, rotate, and scale the part. Accept both JSON-decoded
    -- manifest origins (lowercase {x,y,z}) and Roblox Vector3 origins
    -- (uppercase {X,Y,Z}) so the external_url lazy fetcher works.
    local ox = originStuds.X or originStuds.x or 0
    local oy = originStuds.Y or originStuds.y or 0
    local oz = originStuds.Z or originStuds.z or 0
    local worldPos = Vector3.new(
        (position.x or 0) + ox,
        (position.y or 0) + oy,
        (position.z or 0) + oz
    )
    local yaw = math.rad(yawDegrees or 0)
    part.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, yaw, 0)
    -- NOTE: Rust build_tree_mesh already bakes scale into the geometry
    -- (height_studs / 20 clamp applied to trunk/canopy dimensions), so we
    -- do NOT multiply part.Size here — doing so would double-scale the tree.
    part.Anchored = true
    part.CanCollide = false
    part.CastShadow = true
    part.Material = Enum.Material.LeafyGrass
    part.Color = Color3.fromRGB(34, 120, 50)

    return part
end

-- Builds a simple procedural tree model (trunk + canopy)
local function buildTree(parent, prop, originStuds, baseYOverride)
    local worldPos = Vector3.new(
        prop.position.x + originStuds.x,
        baseYOverride or (prop.position.y + originStuds.y),
        prop.position.z + originStuds.z
    )
    local yaw = math.rad(prop.yawDegrees or 0)
    -- prop.scale defaults to 1.0 from exporter; use getTreeScale for real height-based scaling
    local scale = getTreeScale(prop)
    local canopySeed = hashId(prop.id or tostring(prop.position.x) .. ":" .. tostring(prop.position.z))

    local model = Instance.new("Model")
    model.Name = prop.id or "Tree"

    local trunkVariation = 0.8 + deterministicUnitFloat(canopySeed + 1) * 0.4 -- 0.8..1.2
    local trunkH = 7 * scale * trunkVariation
    local trunkR = 0.5 * scale
    local canopyR = (3.5 + deterministicUnitFloat(canopySeed) * 4.5) * scale -- wider range: 3.5..8

    -- Scale trunk radius from real-world circumference when available.
    if prop.circumference and prop.circumference > 0 then
        local diameterStuds = (prop.circumference / math.pi) * METERS_TO_STUDS
        trunkR = math.max(0.5, diameterStuds * 0.5)
    end

    -- Palm special case: thin trunk + frond cluster instead of sphere canopy
    local species = prop.species and prop.species:lower() or ""
    local leafType = prop.leafType or ""

    -- Infer needleleaved leafType from known conifer species when not explicit
    if leafType == "" then
        for _, pattern in ipairs(CONIFER_SPECIES_PATTERNS) do
            if species:find(pattern, 1, true) then
                leafType = "needleleaved"
                break
            end
        end
    end

    if species:find("palm") or leafType == "tropical" then
        local trunk = Instance.new("Part")
        trunk.Name = "Trunk"
        trunk.Anchored = true
        trunk.Size = Vector3.new(trunkR * 0.6 * 2, trunkH, trunkR * 0.6 * 2)
        trunk.Shape = Enum.PartType.Cylinder
        trunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.5, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
        trunk.Material = Enum.Material.Wood
        trunk.Color = Color3.fromRGB(139, 109, 75)
        trunk.CastShadow = false
        trunk.Parent = model

        local trunkTop = worldPos + Vector3.new(0, trunkH, 0)
        for i = 1, 4 do
            local frond = Instance.new("Part")
            frond.Name = "Frond" .. i
            frond.Size = Vector3.new(1, 0.5, canopyR * 1.5)
            frond.Color = Color3.fromRGB(34, 120, 50)
            frond.Material = Enum.Material.Grass
            frond.Anchored = true
            frond.CanCollide = false
            frond.CastShadow = false
            local angle = (i - 1) * 90
            frond.CFrame = CFrame.new(trunkTop)
                * CFrame.Angles(0, math.rad(angle), 0)
                * CFrame.Angles(math.rad(-30), 0, 0)
                * CFrame.new(0, 0, -canopyR * 0.5)
            frond.Parent = model
        end

        model.Parent = parent
        return model
    end

    -- Standard tree: tapered trunk + shaped canopy
    local trunkColor = Color3.fromRGB(101, 79, 55)

    -- Base trunk section (wider for taper effect)
    local baseTrunk = Instance.new("Part")
    baseTrunk.Name = "TrunkBase"
    baseTrunk.Anchored = true
    baseTrunk.Shape = Enum.PartType.Cylinder
    baseTrunk.Size = Vector3.new(trunkH * 0.3, trunkR * 1.4, trunkR * 1.4)
    baseTrunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.15, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
    baseTrunk.Material = Enum.Material.WoodPlanks
    baseTrunk.Color = trunkColor
    baseTrunk.CastShadow = false
    baseTrunk.Parent = model

    -- Upper trunk section (narrower)
    local upperTrunk = Instance.new("Part")
    upperTrunk.Name = "TrunkUpper"
    upperTrunk.Anchored = true
    upperTrunk.Shape = Enum.PartType.Cylinder
    upperTrunk.Size = Vector3.new(trunkH * 0.7, trunkR, trunkR)
    upperTrunk.CFrame = CFrame.new(worldPos + Vector3.new(0, trunkH * 0.65, 0)) * CFrame.Angles(0, yaw, math.pi * 0.5)
    upperTrunk.Material = Enum.Material.WoodPlanks
    upperTrunk.Color = trunkColor
    upperTrunk.CastShadow = false
    upperTrunk.Parent = model

    -- Canopy: shape depends on leafType
    local trunkTop = worldPos + Vector3.new(0, trunkH, 0)
    local canopyBrickColor = getCanopyColor(prop.species)
    local canopyColor3 = jitterCanopyColor(canopyBrickColor.Color, prop.id or prop.species or "tree")

    if leafType == "needleleaved" then
        -- Stacked tapered tiers for a visually distinct conifer silhouette.
        -- Ball parts render as spheres, so we stack 3 progressively smaller
        -- tiers to approximate a cone / Christmas-tree shape.
        local tiers = 3
        local totalConeH = canopyR * 2.8
        local tierH = totalConeH / tiers
        local darkGreen = Color3.new(
            math.clamp(canopyColor3.R - 0.05, 0, 1),
            math.clamp(canopyColor3.G - 0.08, 0, 1),
            math.clamp(canopyColor3.B - 0.02, 0, 1)
        )
        for tier = 1, tiers do
            -- Bottom tier is widest, top is narrowest
            local t = (tier - 1) / (tiers - 1) -- 0 = bottom, 1 = top
            local tierRadius = canopyR * (1.0 - t * 0.55)
            local yOff = (tier - 1) * tierH * 0.75 -- slight overlap between tiers

            local part = Instance.new("Part")
            part.Name = "ConiferTier" .. tier
            part.Anchored = true
            part.Shape = Enum.PartType.Ball
            part.Size = Vector3.new(tierRadius * 2, tierH * 1.1, tierRadius * 2)
            part.Material = Enum.Material.LeafyGrass
            -- Darken upper tiers slightly for depth
            part.Color = Color3.new(
                math.clamp(darkGreen.R - t * 0.03, 0, 1),
                math.clamp(darkGreen.G + t * 0.02, 0, 1),
                math.clamp(darkGreen.B - t * 0.01, 0, 1)
            )
            part.CastShadow = true
            part.CanCollide = false
            part.CFrame = CFrame.new(trunkTop + Vector3.new(0, yOff + tierH * 0.4, 0))
            part.Parent = model
        end
    else
        -- Broadleaved default: multi-lobe organic canopy
        buildRealisticCanopy(model, trunkTop, canopyR, canopyColor3, prop.species or "tree")
    end

    model.Parent = parent
    return model
end

local function annotatePropRoot(instance, prop)
    if instance == nil or prop == nil then
        return instance
    end
    if type(prop.id) == "string" and prop.id ~= "" then
        instance:SetAttribute("ArnisPropSourceId", prop.id)
    end
    instance:SetAttribute("ArnisPropKind", tostring(prop.kind or "unknown"))
    if type(prop.species) == "string" and prop.species ~= "" then
        instance:SetAttribute("ArnisPropSpecies", string.lower(prop.species))
    end
    return instance
end

function PropBuilder.Build(parent, prop, originStuds, chunk)
    local detailParent = getPropDetailParent(parent)
    if prop.kind == "tree" then
        -- Fast path: use Rust pre-computed prop mesh when available
        if prop.propMesh and prop.propMesh.vertices and #prop.propMesh.vertices >= 3 then
            local scale = getTreeScale(prop)
            local meshPart = PropBuilder.loadPrecomputedPropMesh(
                prop.propMesh,
                prop.position,
                prop.yawDegrees,
                scale,
                originStuds
            )
            if meshPart then
                -- Apply species-specific canopy color
                local canopyBrickColor = getCanopyColor(prop.species)
                meshPart.Color = jitterCanopyColor(canopyBrickColor.Color, prop.id or prop.species or "tree")
                meshPart.Name = prop.id or "Tree"
                meshPart.Parent = detailParent
                precomputedPropCount += 1
                return annotatePropRoot(meshPart, prop)
            end
            -- Fall through to runtime path on mesh creation failure
        end
        -- Runtime path: procedural tree geometry
        runtimePropCount += 1
        -- Use manifest Y directly; DEM elevation is authoritative
        return annotatePropRoot(buildTree(detailParent, prop, originStuds, prop.position.y + originStuds.y), prop)
    end

    if prop.kind == "street_lamp" or prop.kind == "amenity_street_lamp" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        return annotatePropRoot(buildStreetLamp(wx, wy, wz, detailParent), prop)
    end

    if prop.kind == "bench" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local yaw = math.rad(prop.yawDegrees or 0)

        local model = Instance.new("Model")
        model.Name = "Bench"

        -- Seat plank
        local seat = Instance.new("Part")
        seat.Name = "Seat"
        seat.Size = Vector3.new(5, 0.3, 1.5)
        seat.Material = Enum.Material.WoodPlanks
        seat.Color = Color3.fromRGB(120, 80, 45)
        seat.CFrame = CFrame.new(wx, wy + 1.5, wz) * CFrame.Angles(0, yaw, 0)
        seat.Anchored = true
        seat.CanCollide = false
        seat.CastShadow = false
        seat.Parent = model

        -- Backrest
        local back = Instance.new("Part")
        back.Name = "Backrest"
        back.Size = Vector3.new(5, 1.2, 0.2)
        back.Material = Enum.Material.WoodPlanks
        back.Color = Color3.fromRGB(110, 72, 40)
        back.CFrame = CFrame.new(wx, wy + 2.3, wz) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -0.65)
        back.Anchored = true
        back.CanCollide = false
        back.CastShadow = false
        back.Parent = model

        -- Two metal legs
        for _, legOffset in ipairs({ -2, 2 }) do
            local leg = Instance.new("Part")
            leg.Name = "Leg"
            leg.Size = Vector3.new(0.3, 1.5, 1.5)
            leg.Material = Enum.Material.Metal
            leg.Color = Color3.fromRGB(60, 60, 65)
            leg.CFrame = CFrame.new(wx, wy + 0.75, wz) * CFrame.Angles(0, yaw, 0) * CFrame.new(legOffset, 0, 0)
            leg.Anchored = true
            leg.CanCollide = false
            leg.CastShadow = false
            leg.Parent = model
        end

        model.Parent = detailParent
        return annotatePropRoot(model, prop)
    end

    if prop.kind == "bus_stop" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local model = Instance.new("Model")
        model.Name = "BusStop"
        local pole = Instance.new("Part")
        pole.Anchored = true
        pole.CastShadow = false
        pole.CanCollide = false
        pole.Size = Vector3.new(0.2, 5, 0.2)
        pole.CFrame = CFrame.new(wx, wy + 2.5, wz)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(180, 180, 190)
        pole.Parent = model
        local sign = Instance.new("Part")
        sign.Anchored = true
        sign.CastShadow = false
        sign.CanCollide = false
        sign.Size = Vector3.new(0.8, 0.5, 0.1)
        sign.CFrame = CFrame.new(wx, wy + 5.2, wz)
        sign.Material = Enum.Material.SmoothPlastic
        sign.Color = Color3.fromRGB(0, 80, 180)
        sign.Parent = model
        model.Parent = detailParent
        return annotatePropRoot(model, prop)
    end

    if prop.kind == "traffic_signal" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local model = Instance.new("Model")
        model.Name = "TrafficSignal"

        -- Pole
        local pole = Instance.new("Part")
        pole.Name = "Pole"
        pole.Anchored = true
        pole.CastShadow = false
        pole.CanCollide = false
        pole.Size = Vector3.new(0.4, 15, 0.4)
        pole.CFrame = CFrame.new(wx, wy + 7.5, wz)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(60, 60, 65)
        pole.Parent = model

        -- Signal housing
        local housing = Instance.new("Part")
        housing.Name = "Housing"
        housing.Anchored = true
        housing.CastShadow = false
        housing.CanCollide = false
        housing.Size = Vector3.new(1.5, 4, 1)
        housing.CFrame = CFrame.new(wx, wy + 13, wz)
        housing.Material = Enum.Material.Metal
        housing.Color = Color3.fromRGB(40, 40, 45)
        housing.Parent = model

        -- Three lights: red (top), yellow (middle), green (bottom)
        local lightDefs = {
            { r = 255, g = 50, b = 50 },
            { r = 255, g = 200, b = 50 },
            { r = 50, g = 200, b = 80 },
        }
        for li, lc in ipairs(lightDefs) do
            local light = Instance.new("Part")
            light.Name = "Light" .. li
            light.Shape = Enum.PartType.Ball
            light.Size = Vector3.new(0.8, 0.8, 0.8)
            light.Material = Enum.Material.Neon
            light.Color = Color3.fromRGB(lc.r, lc.g, lc.b)
            light.CFrame = CFrame.new(wx, wy + 14.2 - (li - 1) * 1.2, wz + 0.5)
            light.Anchored = true
            light.CastShadow = false
            light.CanCollide = false
            light.Parent = model
        end

        model.Parent = detailParent
        return annotatePropRoot(model, prop)
    end

    if prop.kind == "waste_basket" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local bin = Instance.new("Part")
        bin.Name = "WasteBasket"
        bin.Anchored = true
        bin.CastShadow = false
        bin.CanCollide = false
        bin.Size = Vector3.new(0.8, 1.2, 0.8)
        bin.CFrame = CFrame.new(wx, wy + 0.6, wz)
        bin.Material = Enum.Material.Metal
        bin.Color = Color3.fromRGB(70, 70, 70)
        bin.Parent = detailParent
        return annotatePropRoot(bin, prop)
    end

    if prop.kind == "fire_hydrant" then
        local wx = prop.position.x + originStuds.x
        local wz = prop.position.z + originStuds.z
        wx, wz = alignRoadsideProp(prop, chunk, originStuds, wx, wz)
        local wy = resolveBaseY(chunk, wx, prop.position.y + originStuds.y, wz)
        local hydrant = Instance.new("Part")
        hydrant.Name = "FireHydrant"
        hydrant.Anchored = true
        hydrant.CastShadow = false
        hydrant.CanCollide = false
        hydrant.Size = Vector3.new(0.6, 1.0, 0.6)
        hydrant.CFrame = CFrame.new(wx, wy + 0.5, wz)
        hydrant.Material = Enum.Material.SmoothPlastic
        hydrant.Color = Color3.fromRGB(220, 30, 30)
        hydrant.Parent = detailParent
        return annotatePropRoot(hydrant, prop)
    end

    if prop.kind == "crossing" then
        -- Render a zebra crosswalk: 6-8 white stripes perpendicular to nearby road
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z

        -- Place striped crosswalk markings (simple: assume N-S direction,
        -- could be improved by finding nearest road direction)
        local stripeCount = 6
        local stripeWidth = 1.5
        local stripeLen = 12 -- studs across the road
        local gap = 1.2

        local crosswalkModel = Instance.new("Model")
        crosswalkModel.Name = prop.id

        for s = 1, stripeCount do
            local offset = (s - stripeCount / 2 - 0.5) * (stripeWidth + gap)
            local stripe = Instance.new("Part")
            stripe.Name = "CrosswalkStripe"
            stripe.Size = Vector3.new(stripeLen, 0.05, stripeWidth)
            stripe.Material = Enum.Material.SmoothPlastic
            stripe.Color = Color3.fromRGB(255, 255, 255)
            stripe.Anchored = true
            stripe.CanCollide = false
            stripe.CastShadow = false
            stripe.CFrame = CFrame.new(wx, wy + 0.15, wz + offset)
            stripe.Parent = crosswalkModel
        end

        crosswalkModel.Parent = detailParent
        return annotatePropRoot(crosswalkModel, prop)
    end

    if prop.kind == "fountain" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        -- Circular basin + water center
        local basin = Instance.new("Part")
        basin.Shape = Enum.PartType.Cylinder
        basin.Size = Vector3.new(1, 10, 10) -- cylinder: height, diameter, diameter
        basin.Material = Enum.Material.Marble
        basin.Color = Color3.fromRGB(200, 195, 185)
        basin.CFrame = CFrame.new(wx, wy + 0.5, wz) * CFrame.Angles(0, 0, math.pi / 2)
        basin.Anchored = true
        basin.Parent = detailParent
        -- Water inside
        local water = Instance.new("Part")
        water.Shape = Enum.PartType.Cylinder
        water.Size = Vector3.new(0.3, 8, 8)
        water.Material = Enum.Material.Glass
        water.Color = Color3.fromRGB(100, 150, 200)
        water.Transparency = 0.3
        water.CFrame = CFrame.new(wx, wy + 0.8, wz) * CFrame.Angles(0, 0, math.pi / 2)
        water.Anchored = true
        water.Parent = detailParent
        return annotatePropRoot(basin, prop)
    end

    if prop.kind == "post_box" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local box = Instance.new("Part")
        box.Size = Vector3.new(2, 4, 2)
        box.Material = Enum.Material.Metal
        box.Color = Color3.fromRGB(30, 60, 180) -- blue USPS style
        box.CFrame = CFrame.new(wx, wy + 2, wz)
        box.Anchored = true
        box.Parent = detailParent
        return annotatePropRoot(box, prop)
    end

    if prop.kind == "drinking_water" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local fountain = Instance.new("Part")
        fountain.Size = Vector3.new(1.5, 3, 1.5)
        fountain.Material = Enum.Material.Metal
        fountain.Color = Color3.fromRGB(140, 140, 150)
        fountain.CFrame = CFrame.new(wx, wy + 1.5, wz)
        fountain.Anchored = true
        fountain.Parent = detailParent
        return annotatePropRoot(fountain, prop)
    end

    if prop.kind == "bollard" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local bollard = Instance.new("Part")
        bollard.Shape = Enum.PartType.Cylinder
        bollard.Size = Vector3.new(3, 1.5, 1.5)
        bollard.Material = Enum.Material.Metal
        bollard.Color = Color3.fromRGB(80, 80, 85)
        bollard.CFrame = CFrame.new(wx, wy + 1.5, wz) * CFrame.Angles(0, 0, math.pi / 2)
        bollard.Anchored = true
        bollard.Parent = detailParent
        return annotatePropRoot(bollard, prop)
    end

    if prop.kind == "vending_machine" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local machine = Instance.new("Part")
        machine.Size = Vector3.new(3, 6, 2.5)
        machine.Material = Enum.Material.Metal
        machine.Color = Color3.fromRGB(180, 30, 30)
        machine.CFrame = CFrame.new(wx, wy + 3, wz)
        machine.Anchored = true
        machine.Parent = detailParent
        return annotatePropRoot(machine, prop)
    end

    if prop.kind == "telephone" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local booth = Instance.new("Part")
        booth.Size = Vector3.new(3, 7, 3)
        booth.Material = Enum.Material.Glass
        booth.Color = Color3.fromRGB(180, 180, 190)
        booth.Transparency = 0.3
        booth.CFrame = CFrame.new(wx, wy + 3.5, wz)
        booth.Anchored = true
        booth.Parent = detailParent
        return annotatePropRoot(booth, prop)
    end

    if prop.kind == "parking_meter" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        -- Thin pole + head
        local model = Instance.new("Model")
        model.Name = "ParkingMeter"
        local pole = Instance.new("Part")
        pole.Size = Vector3.new(0.3, 4, 0.3)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(80, 80, 85)
        pole.CFrame = CFrame.new(wx, wy + 2, wz)
        pole.Anchored = true
        pole.Parent = model
        local head = Instance.new("Part")
        head.Size = Vector3.new(1, 1.5, 0.8)
        head.Material = Enum.Material.Metal
        head.Color = Color3.fromRGB(60, 60, 65)
        head.CFrame = CFrame.new(wx, wy + 4.5, wz)
        head.Anchored = true
        head.Parent = model
        model.Parent = detailParent
        return annotatePropRoot(model, prop)
    end

    if prop.kind == "bicycle_parking" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        -- U-rack shape
        local rack = Instance.new("Part")
        rack.Shape = Enum.PartType.Cylinder
        rack.Size = Vector3.new(3, 0.3, 0.3)
        rack.Material = Enum.Material.Metal
        rack.Color = Color3.fromRGB(120, 120, 125)
        rack.CFrame = CFrame.new(wx, wy + 1.5, wz) * CFrame.Angles(0, 0, math.pi / 2)
        rack.Anchored = true
        rack.Parent = detailParent
        return annotatePropRoot(rack, prop)
    end

    if prop.kind == "power_tower" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        -- Lattice tower approximation: large semi-transparent box
        local towerHeight = (prop.height or 25) * METERS_TO_STUDS
        local base = Instance.new("Part")
        base.Size = Vector3.new(6, towerHeight, 6)
        base.Material = Enum.Material.Metal
        base.Color = Color3.fromRGB(140, 140, 145)
        base.Transparency = 0.4
        base.CFrame = CFrame.new(wx, wy + towerHeight / 2, wz)
        base.Anchored = true
        base.Parent = detailParent
        return annotatePropRoot(base, prop)
    end

    if prop.kind == "power_pole" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local poleHeight = (prop.height or 10) * METERS_TO_STUDS
        local pole = Instance.new("Part")
        pole.Shape = Enum.PartType.Cylinder
        pole.Size = Vector3.new(poleHeight, 1, 1)
        pole.Material = Enum.Material.WoodPlanks
        pole.Color = Color3.fromRGB(100, 75, 50)
        pole.CFrame = CFrame.new(wx, wy + poleHeight / 2, wz) * CFrame.Angles(0, 0, math.pi / 2)
        pole.Anchored = true
        pole.Parent = detailParent
        return annotatePropRoot(pole, prop)
    end

    if prop.kind == "flagpole" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        local fpHeight = (prop.height or 8) * METERS_TO_STUDS
        local pole = Instance.new("Part")
        pole.Shape = Enum.PartType.Cylinder
        pole.Size = Vector3.new(fpHeight, 0.3, 0.3)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(180, 180, 185)
        pole.CFrame = CFrame.new(wx, wy + fpHeight / 2, wz) * CFrame.Angles(0, 0, math.pi / 2)
        pole.Anchored = true
        pole.Parent = detailParent
        return annotatePropRoot(pole, prop)
    end

    if prop.kind == "surveillance" then
        local wx = prop.position.x + originStuds.x
        local wy = prop.position.y + originStuds.y
        local wz = prop.position.z + originStuds.z
        -- Small box on pole
        local model = Instance.new("Model")
        model.Name = "Surveillance"
        local pole = Instance.new("Part")
        pole.Size = Vector3.new(0.3, 5, 0.3)
        pole.Material = Enum.Material.Metal
        pole.Color = Color3.fromRGB(80, 80, 85)
        pole.CFrame = CFrame.new(wx, wy + 2.5, wz)
        pole.Anchored = true
        pole.Parent = model
        local cam = Instance.new("Part")
        cam.Size = Vector3.new(0.8, 0.5, 1.2)
        cam.Material = Enum.Material.SmoothPlastic
        cam.Color = Color3.fromRGB(40, 40, 45)
        cam.CFrame = CFrame.new(wx + 0.5, wy + 5.2, wz)
        cam.Anchored = true
        cam.Parent = model
        model.Parent = detailParent
        return annotatePropRoot(model, prop)
    end

    local pool = getOrCreatePool(prop.kind)
    local instance = pool:Acquire()

    instance.Name = prop.id or prop.kind
    instance:SetAttribute("PoolKind", prop.kind)
    annotatePropRoot(instance, prop)

    local worldPos = Vector3.new(
        prop.position.x + originStuds.x,
        resolveBaseY(
            chunk,
            prop.position.x + originStuds.x,
            prop.position.y + originStuds.y,
            prop.position.z + originStuds.z
        ),
        prop.position.z + originStuds.z
    )

    instance:PivotTo(CFrame.new(worldPos) * CFrame.Angles(0, math.rad(prop.yawDegrees or 0), 0))
    instance.Parent = detailParent

    if prop.scale then
        -- Apply scale if the instance supports it (Models do via Scale property)
        if instance:IsA("Model") then
            instance:ScaleTo(prop.scale)
        end
    end

    return instance
end

function PropBuilder.Clear(kind)
    if pools[kind] then
        pools[kind]:Drain()
    end
end

function PropBuilder.ReleaseAll(parent)
    for _, child in ipairs(parent:GetChildren()) do
        local poolKind = child:GetAttribute("PoolKind")
        if poolKind and pools[poolKind] then
            pools[poolKind]:Release(child)
        else
            child:Destroy()
        end
    end
end

function PropBuilder.GetBuildStats()
    return {
        precomputedProps = precomputedPropCount,
        runtimeProps = runtimePropCount,
    }
end

function PropBuilder.ResetBuildStats()
    precomputedPropCount = 0
    runtimePropCount = 0
end

return PropBuilder
