package game

import rl "vendor:raylib"

// Camera
camera : rl.Camera3D = {{1, 0, 0}, {0, 0, 0}, {0, 1, 0}, 90, rl.CameraProjection.PERSPECTIVE}
camera_verticalAngle : f32 = 0.0
camera_distance : f32 = 10.0
camera_height : f32 = 5.0
camera_speed :: 8

main :: proc()
{
    rl.InitWindow(640, 640, "Rail Network Sim")

    game_start()

    for !rl.WindowShouldClose()
    {
        game_update()

        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            rl.BeginMode3D(camera)
            rl.DrawGrid(20, 1)
            game_draw3d()
            rl.EndMode3D()
            game_drawui()
        rl.EndDrawing()
    }

    rl.CloseWindow()
}

arc1 : ArcSegment

game_start :: proc()
{

}

game_update :: proc()
{
    // Camera Position Update
    cameraForwardVector := rl.Vector3Normalize(camera.target - camera.position)
    cameraRightVector := rl.Vector3Normalize(rl.Vector3CrossProduct(cameraForwardVector, camera.up))
    cameraUpVector := rl.Vector3CrossProduct(cameraRightVector, cameraForwardVector)
    cameraSpeedMultiplier := rl.GetFrameTime() * camera_speed

    if input_isdown(INPUT_RIGHT) do camera.target += {cameraRightVector.x, 0, cameraRightVector.z} * cameraSpeedMultiplier
    if input_isdown(INPUT_LEFT) do camera.target -= {cameraRightVector.x, 0, cameraRightVector.z} * cameraSpeedMultiplier
    if input_isdown(INPUT_FORWARD) do camera.target += {cameraForwardVector.x, 0, cameraForwardVector.z} * cameraSpeedMultiplier
    if input_isdown(INPUT_BACK) do camera.target -= {cameraForwardVector.x, 0, cameraForwardVector.z} * cameraSpeedMultiplier

    if input_isdown(INPUT_UP) do camera_height += cameraSpeedMultiplier
    if input_isdown(INPUT_DOWN) do camera_height -= cameraSpeedMultiplier
    if input_isdown(INPUT_RIGHTMOUSE)
    {
        rl.SetMouseCursor(.CROSSHAIR)
        camera_verticalAngle += cameraSpeedMultiplier * -rl.GetMouseDelta().x
    }
    else
    {
        rl.SetMouseCursor(.ARROW)
    }

    camera.position = rl.Vector3RotateByAxisAngle({-camera_distance, camera_height, 0}, {0, 1, 0}, camera_verticalAngle) + camera.target

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

mesh_from_railline :: proc(rails : RailLine) -> rl.Mesh
{
    // not done 0
    track_mesh : rl.Mesh
    rectCount :: 1

    track_mesh.vertexCount = rectCount * 6
    track_mesh.triangleCount = rectCount * 2
        
    track_mesh.vertices = make([^]f32, 18 * rectCount)  // 6 vertices for rect and 3 values for each vertex: x y z
    track_mesh.texcoords = make([^]f32, 12 * rectCount)  // 6 vertices for rect and 2 values for each texture coordinates: x y
    
    rl.UploadMesh(&track_mesh, false) // upload mesh to gpu
    return track_mesh
}

game_draw3d :: proc()
{
    
}

game_drawui :: proc()
{
    rl.DrawCircleV(arc1.p0.xz, 2, rl.YELLOW)
    rl.DrawCircleV(arc1.p1.xz, 2, rl.YELLOW)
    for i in 0..=f32(100)
    {
        rl.DrawCircleV(Arc_ReturnPoint(arc1, i / 100).xz, 1, rl.WHITE)
    }
}

// Keyboard and Mouse Input
INPUT_LEFTMOUSE :: rl.MouseButton.LEFT
INPUT_RIGHTMOUSE :: rl.MouseButton.RIGHT
INPUT_FORWARD :: rl.KeyboardKey.W
INPUT_LEFT :: rl.KeyboardKey.A
INPUT_BACK :: rl.KeyboardKey.S
INPUT_RIGHT :: rl.KeyboardKey.D
INPUT_UP :: rl.KeyboardKey.SPACE
INPUT_DOWN :: rl.KeyboardKey.LEFT_SHIFT

input_isdown :: proc{rl.IsKeyDown, rl.IsMouseButtonDown}