package game

import "core:math"
import "core:fmt"

// Raylib specific functions, in case we decide to change the library
import rl "vendor:raylib"
v3len :: rl.Vector3Length
v3dist :: rl.Vector3Distance
v3normal :: rl.Vector3Normalize
v2dot :: rl.Vector2DotProduct
v3dot :: rl.Vector3DotProduct
v3cross :: rl.Vector3CrossProduct
v3rotate :: rl.Vector3RotateByAxisAngle
v3angle :: rl.Vector3Angle
PI :: rl.PI

// p0: start point, p1: center point for arc, end point for a line, a: angle, is line if 0
ArcSegment :: struct
{
    p0, p1 : [3]f32,
    a : f32,
}

// returns the 3d coordinates on the arc segment, t = [0, 1]
Arc_ReturnPoint :: proc(arc : ArcSegment, t : f32) -> [3]f32
{
    if(abs(arc.a) < 0.01)
    {
        // When angle is 0, the it is a line
        return arc.p0 * (1 - t) + arc.p1 * t
    }
    else
    {
        // When angle is not 0, it is a circular arc
        r := v3dist(arc.p0, arc.p1)
        angle0 := math.atan2((arc.p0 - arc.p1).z, (arc.p0 - arc.p1).x)

        // interpolation
        anglet := - arc.a * t + angle0
        yt := arc.p0.y * (1 - t) + arc.p1.y * t

        return arc.p1 + {math.cos(anglet) * r, yt, math.sin(anglet) * r}
    }
}

// returns the length of the arc segment
Arc_ReturnLength :: proc(arc : ArcSegment) -> f32
{
    if(abs(arc.a) < 0.01)
    {
        return v3dist(arc.p0, arc.p1)
    }
    else
    {
        r := v3dist(arc.p0, arc.p1)
        return abs(r * arc.a)
    }
}

// returns the 3d normal coordinates of the arc segment, t = [0, 1]
Arc_ReturnNormal :: proc(arc : ArcSegment, t : f32) -> [3]f32
{
    if(abs(arc.a) < 0.01)
    {
        return -v3normal(arc.p1 - arc.p0).zyx * {-1, 1, 1}
    }
    else
    {
        return v3normal(v3rotate((arc.p1 - arc.p0) * math.sign(arc.a), {0, 1, 0}, arc.a * t))
    }
}

// calculates an arc given start point, end point, start tangent
Arc_FromTwoPoints :: proc(p0, p1, t : [3]f32) -> ArcSegment
{
    v := p1 - p0
    t0 := v3normal(t)
    a:= 2 * v3angle(v, t0) //math.acos(v3dot(v3normal(v), t0))

    if math.is_nan(a) do a = 0
    if abs(a) < 0.01 do return{p0, p1, 0}

    r := math.sqrt(1 / (2 - 2 * math.cos(a))) * v3len(v)
    origin := r * t0.zyx * {-1, 1, 1}

    if v3cross(v, t0).y < 0 do origin *= -1
    else do a *= -1
    origin += p0

    return {p0, origin, a}
} 

// is given 3d point on the arc
Arc_PointOnArc :: proc(arc : ArcSegment, point : [3]f32) -> bool
{
    if abs(arc.a) < 0.01
    {
        // check line
        if DistanceToLine(arc.p0, arc.p1, point) <= 0.5 do return true
    }
    else
    {
        //check arc
        // first check the distance is appropriate
        if abs(v3dist(arc.p0, arc.p1) - v3dist(arc.p1, point)) < 0.5
        {
            // then check the angle
            if abs(v3angle(v3rotate(arc.p0 - arc.p1, {0, 1, 0}, arc.a * 0.5), point - arc.p1)) <= abs(arc.a * 0.5) do return true
        }
    }

    return false
}

DistanceToLine :: proc(p0, p1, point: [3]f32) -> f32
{
    t := v3dot(point - p0, p1 - p0) / v3dot(p1 - p0, p1 - p0)
    if t > 1 do return v3dist(point, p1) // distance to point 1
    else if t < 0 do return v3dist(point, p0) // distance to point 0
    else do return v3len(v3cross(point - p0, p1 - p0)) / v3len(p1 - p0)
}

// a switch is a point where multiple rail lines connect
Switch :: struct
{
    pos : [3]f32,   // world coordinates of the switch
    closest_train : i32,    // index of the closest train to the switch
    closest_train_distance : f32,   // how far is this train
    group_directions : [dynamic][2]f32, // directions of the groups
}

// a rail line is a collection of arcs
RailLine :: struct
{
    start_switch, end_switch : i32, // index of the switches at head and tail
    start_group, end_group : u8,   // rail lines are grouped, passing through is only allowed between the same groups
    rails : [dynamic]ArcSegment,
    trains_on : [dynamic]i32,   //index of trains on this rail line
}

RailLines : [dynamic]RailLine
Switches : [dynamic]Switch

DraftNode :: struct
{
    pos : [3]f32,
    dir : [2]f32,
    connectedRailIds : [dynamic]int,
}

DraftRail :: struct
{
    arc : ArcSegment,
    headNodeId, tailNodeId : int,
}

DraftTempRail :: struct
{
    arcs : [2]ArcSegment,
    shape : u8,
    headNodeId : int,
    tailNodeId : int,
    isSet : bool
}

Draft_Nodes : [dynamic]DraftNode
Draft_Rails : [dynamic]DraftRail
temp_rail : DraftTempRail 

// creates a new node and returns its index
Draft_NewNode :: proc(pos : [3]f32, dir : [2]f32) -> int
{
    append(&Draft_Nodes, DraftNode {pos, dir, make([dynamic]int)})
    return len(Draft_Nodes) - 1
}

Draft_RemoveNode :: proc(nodeId : int)
{
    delete_dynamic_array(Draft_Nodes[nodeId].connectedRailIds)
    defer unordered_remove(&Draft_Nodes, nodeId)

    // update the changed index values
    switchedIndex := len(Draft_Nodes)
    for id in Draft_Nodes[nodeId].connectedRailIds
    {
        connectedRail := Draft_Rails[id]

        if connectedRail.headNodeId == switchedIndex do connectedRail.headNodeId = nodeId
        if connectedRail.tailNodeId == switchedIndex do connectedRail.tailNodeId = nodeId
    }
}

Draft_NewRail :: proc(rail : DraftRail)
{
    newIndex := len(Draft_Rails)
    append(&Draft_Rails, rail)
    append(&Draft_Nodes[rail.headNodeId].connectedRailIds, newIndex)
    append(&Draft_Nodes[rail.tailNodeId].connectedRailIds, newIndex)
}

Draft_RemoveRail :: proc(railId : int)
{
    unordered_remove(&Draft_Rails, railId)
    
    //update the changed index values
    switchedIndex := len(Draft_Rails)
    for &n in Draft_Nodes
    {
        railids_to_delete := make([dynamic]int)
        for &i, p in n.connectedRailIds
        {
            if i == railId do append(&railids_to_delete, p)
            if i == switchedIndex do i = railId
        }
        for len(railids_to_delete) > 0
        {
            unordered_remove(&n.connectedRailIds, railids_to_delete[0])
            unordered_remove(&railids_to_delete, 0)
        }
        delete_dynamic_array(railids_to_delete)
    }

    // delete empty nodes
    nodes_to_delete := make([dynamic]int)
    for n, i in Draft_Nodes
    {
        if len(n.connectedRailIds) == 0
        {
            append(&nodes_to_delete, i)
        }
    }
    for len(nodes_to_delete) > 0
    {
        Draft_RemoveNode(nodes_to_delete[len(nodes_to_delete) - 1])
        unordered_remove(&nodes_to_delete, len(nodes_to_delete) - 1)
    }
    delete_dynamic_array(nodes_to_delete)

}

GetBiarcConnection :: proc(p1, p2, t1, t2 : [3]f32) -> [3]f32
{
    v := p2 - p1

    _vt := v3dot(v, t1 + t2);
    _tt := 2 * (1 - v3dot(t1, t2));

    d : f32
    if (_tt == 0) do d = v3dot(v, v) / v3dot(v, t2) * 0.25;
    else do d = (math.sqrt(_vt * _vt + _tt * v3dot(v, v)) - _vt) / _tt;

    pm := 0.5 * (p1 + p2 + d * t1 - d * t2)
    return pm
}

// sets the values of temp rail; 
Draft_SetTempRail :: proc(endPos : [3]f32, headNodeId : int, headDirection : i8 = 1, tailNodeId : int = -1, tailDirection : i8 = 1)
{
    temp_rail.headNodeId = headNodeId
    temp_rail.tailNodeId = tailNodeId

    p1 := Draft_Nodes[headNodeId].pos
    t1 := v3normal(Draft_Nodes[headNodeId].dir.xxy * {1, 0, 1}) * f32(headDirection)

    p2, t2 : [3]f32
    if(tailNodeId == -1)
    {
        // tail node not valid, create just one arc
        p2 = endPos
        t2 = v3normal(2 * (endPos - p1) - t1)

        temp_rail.arcs[0] = Arc_FromTwoPoints(p1, endPos, t1)
        temp_rail.shape = 0
        temp_rail.isSet = true

        return
    }
    
    // valid tail node
    p2 = Draft_Nodes[tailNodeId].pos
    t2 = Draft_Nodes[tailNodeId].dir.xxy * {1, 0, 1} * f32(tailDirection)
    v := p2 - p1

    if(v3cross(t1, v).y == 0 && v3cross(t2, v).y == 0)
    {
        // rail is just a straight line
        temp_rail.arcs[0] = ArcSegment {p1, p2, 0}
        temp_rail.shape = 0
    }
    else
    {
        pm := GetBiarcConnection(p1, p2, t1, t2)

        temp_rail.arcs = {Arc_FromTwoPoints(p1, pm, t1), Arc_FromTwoPoints(p2, pm, -t2)}
        temp_rail.shape = 1
    }

    temp_rail.isSet = true
}

Draft_SaveTempRail :: proc()
{
    // assign tail node
    tailNodeId : int
    if(temp_rail.tailNodeId == -1)
    {
        arc := temp_rail.arcs[temp_rail.shape]
        tailNodeId = Draft_NewNode(Arc_ReturnPoint(arc, 1), v3rotate(Arc_ReturnNormal(arc, 1), {0, 1, 0}, 0.5 * PI).xz)
    }
    else
    {
        tailNodeId = temp_rail.tailNodeId    
    }

    if(temp_rail.shape == 0)
    {
        // create just one rail
        Draft_NewRail({temp_rail.arcs[0], temp_rail.headNodeId, tailNodeId})
    }
    else
    {
        // create two rails and middle node
        arc := temp_rail.arcs[0]
        middleNodeId := Draft_NewNode(Arc_ReturnPoint(arc, 1), v3rotate(Arc_ReturnNormal(arc, 1), {0, 1, 0}, 0.5 * PI).xz)
        
        Draft_NewRail({temp_rail.arcs[0], temp_rail.headNodeId, middleNodeId})
        Draft_NewRail({temp_rail.arcs[1], middleNodeId, tailNodeId})
    }

    Draft_ResetTempRail()
}

Draft_ResetTempRail :: proc()
{
    temp_rail.isSet = false
}

// returns the nearest node index to the given point
Draft_NearestNode :: proc(point : [3]f32, range : f32 = 4096) -> int
{
    closest_distance : f32 = 999999
    closest_index : int = -1
    for n, i in Draft_Nodes
    {
        dist := v3dist(n.pos, point)
        if(dist <= range && dist < closest_distance)
        {
            closest_distance = dist
            closest_index = i
        }
    }

    return closest_index
}

// returns the nearest draft rail index to the given point
Draft_NearestRail :: proc(point : [3]f32) -> int
{
    for r, i in Draft_Rails
    {
        if Arc_PointOnArc(r.arc, point) do return i
    }

    return -1
}

Draft_ConstructAll :: proc()
{
    // divide rails by intersection points (with some tolerance)
    // find rail line segments
    // find switches
    // save them all

    // reset the arrays
    shrink(&Draft_Nodes, 0)
    shrink(&Draft_Rails, 0)
}