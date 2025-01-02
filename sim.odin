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
    if(arc.a == 0)
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
        anglet := arc.a * t + angle0
        yt := arc.p0.y * (1 - t) + arc.p1.y * t

        return arc.p1 + {math.cos(anglet) * r, yt, math.sin(anglet) * r}
    }
}

// returns the length of the arc segment
Arc_ReturnLength :: proc(arc : ArcSegment) -> f32
{
    if(arc.a == 0)
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
    if(arc.a == 0)
    {
        return v3normal(arc.p1 - arc.p0).zyx * {-1, 1, 1}
    }
    else
    {
        return v3normal(v3rotate((arc.p1 - arc.p0) * math.sign(arc.a), {0, 1, 0}, -arc.a * t))
    }
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
    unordered_remove(&Draft_Nodes, nodeId)

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
        for &i, p in n.connectedRailIds
        {
            if i == railId do unordered_remove(&n.connectedRailIds, p)
            if i == switchedIndex do i = railId
        }
    }
}

CalculateBiarcs :: proc(p1, p2, t1, t2 : [3]f32) -> [2]ArcSegment
{
    // biarc interpolation formulas are gotten from ryan juckett
    v := p2 - p1

    pm, c1, c2 : [3]f32
    d : f32
    if v3dot(t1, t2) != 0 do d = (-(v3dot(v, t1 + t2)) + math.sqrt(v3dot(v, t1 + t2) * v3dot(v, t1 + t2) + 2 * (1 - v3dot(t1, t2)) * v3dot(v, v))) / (2 * (1 - v3dot(t1, t2))) 
    if v3dot(v, t2) != 0 do d = v3dot(v, v) / v3dot(v, t2) * 0.25
    else
    {
        // two semicircles situation
        c1 = p1 + 0.25 * v
        c2 = p2 + 0.75 * v
        a1, a2 : f32
        if v3cross(v, t1).y < 0 do a1 = PI
        else do a1 = -PI
        if v3cross(v, t2).y < 0 do a2 = PI
        else do a2 = -PI

        return {ArcSegment {p1, c1, a1}, ArcSegment {pm, c2, a2}}
    }

    pm = (p1 + d * t1 + p2 - d* t2) * 0.5

    n1 := t1.zyx * {-1, 0, 1}
    n2 := t2.zyx * {-1, 0, 1}
    s1 := (v3dot(pm - p1, pm - p1)/v3dot(2 * n1, pm - p1))
    s2 := (v3dot(pm - p2, pm - p2)/v3dot(2 * n2, pm - p2))

    c1 = p1 + n1 * s1
    c2 = p2 + n1 * s2

    a1 := v3angle(v3normal(p1 - c1), v3normal(pm - c1))
    a2 := v3angle(v3normal(p2 - c2), v3normal(c2 - pm))

    return {ArcSegment {p1, c1, a1}, ArcSegment {pm, c2, a2}}
}

// updates all connected rails
DraftNode_UpdateRails :: proc(nodeId : int)
{
    array_len := len(Draft_Nodes[nodeId].connectedRailIds)
    for i in 0..<array_len
    {
        // remove rail changes the order, new elements put to the end
        // getting element 0 all time would help us
        r := Draft_Nodes[nodeId].connectedRailIds[0]

        otherNode : int
        if Draft_Rails[r].headNodeId == nodeId do otherNode = Draft_Rails[r].tailNodeId
        else do otherNode = Draft_Rails[r].headNodeId

        Draft_RemoveRail(r)
        Draft_SetTempRail({}, nodeId, otherNode)
        Draft_SaveTempRail()
    }
}

Draft_SetTempRail :: proc(endPos : [3]f32, headNodeId : int, tailNodeId : int = -1)
{
    temp_rail.headNodeId = headNodeId
    temp_rail.tailNodeId = tailNodeId

    p1 := Draft_Nodes[headNodeId].pos
    t1 := rl.Vector3 { Draft_Nodes[headNodeId].dir.x, 0,  Draft_Nodes[headNodeId].dir.y}

    p2, t2 : [3]f32
    if(tailNodeId > -1)
    {
        // valid tail node
        p2 = Draft_Nodes[tailNodeId].pos
        t2 = rl.Vector3 { Draft_Nodes[tailNodeId].dir.x, 0,  Draft_Nodes[tailNodeId].dir.y}
    }
    else
    {
        // tail node not valid
        p2 = endPos
        t2 = v3normal(2 * (endPos - p1) - t1)
    }
    v := p2 - p1

    if(v3cross(t1, v).y == 0 && v3cross(t2, v).y == 0)
    {
        // rail is just a straight line
        temp_rail.arcs[0] = ArcSegment {p1, p2, 0}
        temp_rail.shape = 0
    }
    else
    {
        // we need two rails to connect them
        biarc := CalculateBiarcs(p1, p2, t1, t2)
        //biarc_tm := v3rotate(t1, {0, 1, 0}, biarc.a1).xz

        // correct the end point if the arcs are a line
        if biarc[0].a == 0 do biarc[0].p1 = biarc[1].p0
        if biarc[1].a == 0 do biarc[1].p1 = p2

        temp_rail.arcs = biarc
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
    closest_distance : f32
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

// moves and rotates a node, updates the connected rails
DraftNode_MoveRotate :: proc(nodeId : int, newPos : [3]f32, newDir : [2]f32)
{
    Draft_Nodes[nodeId].pos = newPos
    Draft_Nodes[nodeId].dir = newDir
}