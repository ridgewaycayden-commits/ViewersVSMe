local WorldProbeGeometry = {}

local function horizontalDistance(fromPoint, toPoint)
    local offset = toPoint - fromPoint
    return Vector2.new(offset.X, offset.Z).Magnitude
end

function WorldProbeGeometry.getHorizontalSurfaceDistance(part, rootPosition)
    if part == nil or not part:IsA("BasePart") or typeof(rootPosition) ~= "Vector3" then
        return nil
    end

    local ok, closestPoint = pcall(part.GetClosestPointOnSurface, part, rootPosition)
    if ok and typeof(closestPoint) == "Vector3" then
        return horizontalDistance(rootPosition, closestPoint)
    end

    return horizontalDistance(rootPosition, part.Position)
end

function WorldProbeGeometry.isNearbyShellWall(part, rootPosition, radiusStuds)
    local nearestDistanceStuds = WorldProbeGeometry.getHorizontalSurfaceDistance(part, rootPosition)
    if nearestDistanceStuds == nil then
        return false, nil
    end

    return nearestDistanceStuds <= radiusStuds, nearestDistanceStuds
end

return WorldProbeGeometry
