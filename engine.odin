package game

import rl "vendor:raylib"

main :: proc()
{
    rl.InitWindow(640, 640, "Rail Network Sim")

    for !rl.WindowShouldClose()
    {
        game_update()

        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)
        game_draw()
        rl.EndDrawing()
    }

    rl.CloseWindow()
}

arc1 : ArcSegment

game_update :: proc()
{
    if rl.IsKeyPressed(.Q)
    {
        arc1.p0 = {rl.GetMousePosition().x, 0, rl.GetMousePosition().y}
    }
    if rl.IsKeyPressed(.W)
    {
        arc1.p1 = {rl.GetMousePosition().x, 0, rl.GetMousePosition().y}
    }

    if rl.IsKeyDown(.A)
    {
        arc1.a += rl.GetFrameTime()

        if(arc1.a > rl.PI) do arc1.a = rl.PI
    }
    if rl.IsKeyDown(.S)
    {
        arc1.a -= rl.GetFrameTime()

        if(arc1.a < 0) do arc1.a = 0
    }
}

game_draw :: proc()
{
    rl.DrawCircleV(arc1.p0.xz, 2, rl.YELLOW)
    rl.DrawCircleV(arc1.p1.xz, 2, rl.YELLOW)
    for i in 0..=f32(100)
    {
        rl.DrawCircleV(Arc_ReturnPoint(arc1, i / 100).xz, 1, rl.WHITE)
    }
    
}
