local Workspace = game:GetService("Workspace")

local WorldProbeSupport = {}

local function isDecorativeRoadDetailDescendant(hitInstance, worldRoot)
    local node = hitInstance
    while node and node.Parent and node ~= worldRoot do
        if node.Name == "Detail" and node.Parent and node.Parent.Name == "Roads" then
            return true
        end
        node = node.Parent
    end

    return false
end

function WorldProbeSupport.classifySupportSurfaceRole(hitInstance)
    if hitInstance == nil then
        return "unknown"
    end
    if hitInstance:IsA("Terrain") then
        return "terrain"
    end

    local node = hitInstance
    while node do
        local surfaceRole = node:GetAttribute("ArnisRoadSurfaceRole")
        if type(surfaceRole) == "string" and surfaceRole ~= "" then
            return string.lower(surfaceRole)
        end
        node = node.Parent
    end

    local nameLower = string.lower(hitInstance.Name)
    if string.find(nameLower, "sidewalk", 1, true) then
        return "sidewalk"
    end
    if string.find(nameLower, "crosswalk", 1, true) or string.find(nameLower, "crossing", 1, true) then
        return "crossing"
    end
    if string.find(nameLower, "curb", 1, true) then
        return "curb"
    end
    if string.find(nameLower, "roof", 1, true) then
        return "roof"
    end

    node = hitInstance
    while node and node.Parent do
        if node.Name == "Roads" then
            return "road"
        end
        if node.Name == "Water" then
            return "water"
        end
        if node.Name == "Buildings" or node.Name == "Rooms" then
            return "building_shell"
        end
        node = node.Parent
    end

    return "unknown"
end

function WorldProbeSupport.shouldIgnoreGroundHit(hitInstance, worldRoot, ignoredRoots)
    if not hitInstance then
        return true
    end

    if ignoredRoots then
        for _, ignored in ipairs(ignoredRoots) do
            if ignored and hitInstance:IsDescendantOf(ignored) then
                return true
            end
        end
    end

    if hitInstance == Workspace.Terrain then
        return false
    end

    if hitInstance:IsA("SpawnLocation") then
        return true
    end

    if isDecorativeRoadDetailDescendant(hitInstance, worldRoot) then
        return true
    end

    if worldRoot and hitInstance:IsDescendantOf(worldRoot) then
        return false
    end

    return true
end

return WorldProbeSupport
