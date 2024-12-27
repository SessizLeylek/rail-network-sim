package game

import "core:math"

// Raylib specific functions, in case we decide to change the library
import rl "vendor:raylib"
v3dist :: rl.Vector3Distance

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
        // When angle is 0, the arc is a line
        return arc.p0 * (1 - t) + arc.p1 * t
    }
    else
    {
        // When angle is not 0, it is a circular arc
        m := (arc.p0 + arc.p1) * 0.5
        d := v3dist(arc.p0, arc.p1)
        r := d / math.sqrt(2 * (1 - math.cos(arc.a)))
        h := math.sqrt(r * r - d * d * 0.25)
        origin := m + h * ((arc.p1 - arc.p0).zyx * {-1 , 1, 1}) / d
        angle0 := math.atan2((arc.p0 - origin).z, (arc.p0 - origin).x)
        angle1 := math.atan2((arc.p1 - origin).z, (arc.p1 - origin).x)
        
        if(angle1 < angle0) do angle1 += rl.PI * 2  // to prevent angle1 jumping back 0

        // interpolation
        anglet := angle1 * t + angle0 * (1 - t)
        yt := arc.p0.y * (1 - t) + arc.p1.y * t

        return origin + {math.cos(anglet) * r, yt, math.sin(anglet) * r}
    }
}