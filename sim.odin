package game

import "core:math"

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
}

// a rail line is a collection of arcs
RailLine :: struct
{
    start_switch, end_switch : i32, // index of the switches at head and tail
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

Draft_Nodes : [dynamic]DraftNode
Draft_Rails : [dynamic]DraftRail

// creates a new node and returns its index
Draft_NewNode :: proc(node : DraftNode) -> int
{
    return append(&Draft_Nodes, node)
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

Biarc :: struct
{
    pm, c1, c2 : [3]f32,
    a1, a2 : f32,
}

CalculateBiarcs :: proc(p1, p2, t1, t2 : [3]f32) -> Biarc
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

        return {pm, c1, c2, a1, a2}
    }

    pm = (p1 + d * t1 + p2 - d* t2) * 0.5

    n1 := t1.zyx * {-1, 0, 1}
    n2 := t2.zyx * {-1, 0, 1}
    s1 := (v3dot(pm - p1, pm - p1)/v3dot(2 * n1, pm - p1))
    s2 := (v3dot(pm - p2, pm - p2)/v3dot(2 * n2, pm - p2))

    c1 = p1 + n1 * s1
    c2 = p2 + n1 * s2

    a1 := v3angle(v3normal(p1 - c1), v3normal(pm - c1))
    a2 := v3angle(v3normal(p2 - c2), v3normal(pm - c2))
    
    return {pm, c1, c2, a1, a2}
}

// connects two nodes by adding appropriate rails between
Draft_ConnectNodes :: proc(node1Id, node2Id : int)
{
    p1 := Draft_Nodes[node1Id].pos
    p2 := Draft_Nodes[node2Id].pos 
    t1 := rl.Vector3 { Draft_Nodes[node1Id].dir.x, 0,  Draft_Nodes[node1Id].dir.y}
    t2 := rl.Vector3 { Draft_Nodes[node2Id].dir.x, 0,  Draft_Nodes[node2Id].dir.y}
    v := p2 - p1

    if(v3dot(t1, v) == 0 && v3dot(t2, v) == 0)
    {
        // rail is just a straight line
        append(&Draft_Rails, DraftRail{{p1, p2, 0}, node1Id, node2Id})
    }
    else
    {
        // we need to rails to connect them
        biarc := CalculateBiarcs(p1, p2, t1, t2)

        biarc_tm := v3rotate(t1, {0, 1, 0}, biarc.a1).xz
        midNodeId := Draft_NewNode({biarc.pm, biarc_tm, make([dynamic]int)})

        arc1 := ArcSegment {p1, biarc.c1, biarc.a1}
        arc2 := ArcSegment {biarc.pm, biarc.c2, biarc.a2}

        // correct the end point if the arcs are a line
        if arc1.a == 0 do arc1.p1 = biarc.pm
        if arc2.a == 0 do arc2.p1 = p2

        append(&Draft_Rails, DraftRail {arc1, node1Id, midNodeId})
        append(&Draft_Rails, DraftRail {arc2, midNodeId, node2Id})
    }
}

// moves and rotates a node, updates the connected rails
DraftNode_MoveRotate :: proc(nodeId : int, newPos : [3]f32, newDir : [2]f32)
{
    Draft_Nodes[nodeId].pos = newPos
    Draft_Nodes[nodeId].dir = newDir
}