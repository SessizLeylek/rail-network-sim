package game

import "core:math"

// Raylib specific functions, in case we decide to change the library
import rl "vendor:raylib"
v3dist :: rl.Vector3Distance
v3normal :: rl.Vector3Normalize
v3rotate :: rl.Vector3RotateByAxisAngle
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
    rail_maxspeed : [dynamic]f32,
    trains_on : [dynamic]i32,   //index of trains on this rail line
}

RailLines : [dynamic]RailLine
Switches : [dynamic]Switch

Draft_RailLines : [dynamic]RailLine
Draft_Switches : [dynamic]Switch
