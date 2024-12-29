package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// Camera
camera : rl.Camera3D = {{1, 0, 0}, {0, 0, 0}, {0, 1, 0}, 90, rl.CameraProjection.PERSPECTIVE}
camera_verticalAngle : f32 = 0.0
camera_distance : f32 = 10.0
camera_height : f32 = 5.0
camera_speed :: 8

main :: proc()
{
    rl.InitWindow(960, 960, "Rail Network Sim")

    game_start()

    for !rl.WindowShouldClose()
    {
        game_update()

        rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)
            rl.BeginMode3D(camera)
            rl.DrawGrid(20, 1)
            rl.DrawSphereWires(camera.target, 0.2, 2, 8, rl.LIME)
            game_draw3d()
            rl.EndMode3D()
            game_drawui()
        rl.EndDrawing()
    }

    rl.CloseWindow()
}

arc1 : ArcSegment
mesh1 : rl.Mesh

game_start :: proc()
{
    temp_railline : RailLine
    append(&temp_railline.rails, ArcSegment {{0, 0, 0}, {1, 0, 0}, rl.PI})
    append(&temp_railline.rails, ArcSegment {{2, 0, 0}, {2, 0, 5}, 0})
    append(&temp_railline.rails, ArcSegment {{2, 0, 5}, {4, 0, 5}, -rl.PI})
    mesh1 = mesh_from_railline(temp_railline)
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

    if input_isdown(INPUT_RIGHTMOUSE)
    {
        rl.SetMouseCursor(.RESIZE_ALL)
        camera_verticalAngle += cameraSpeedMultiplier * -rl.GetMouseDelta().x
        camera_height += cameraSpeedMultiplier * rl.GetMouseDelta().y * 5
    }
    else
    {
        rl.SetMouseCursor(.DEFAULT)
    }

    camera_distance -= rl.GetMouseWheelMove()
    if(camera_distance < 1) do camera_distance = 1
    else if(camera_distance > 50) do camera_distance = 50

    camera.position = rl.Vector3RotateByAxisAngle({-camera_distance, camera_height, 0}, {0, 1, 0}, camera_verticalAngle) + camera.target
}

mesh_from_railline :: proc(rails : RailLine) -> rl.Mesh
{
    // Calculate number of rectangles will form the mesh
    rectCount : i32 = 0
    for r in rails.rails
    {
        rectCount += i32(math.ceil(Arc_ReturnLength(r)))
    }

    // define mesh attributes
    track_mesh : rl.Mesh

    track_mesh.vertexCount = 2 + rectCount * 2
    track_mesh.triangleCount = rectCount * 2
        
    track_mesh.vertices = make([^]f32, 3 * track_mesh.vertexCount)   // 3 values for each vertex: x y z
    track_mesh.texcoords = make([^]f32, 2 * track_mesh.vertexCount)  // 2 values for each texture coordinates: x y
    track_mesh.indices = make([^]u16, 3 * track_mesh.triangleCount)  // 3 vertex indices for each face
    
    // position mesh vertices
    vs := 0 // vertices set
    for r, ri in rails.rails
    {
        arclen := i32(math.ceil(Arc_ReturnLength(r)))

        for i in 0..=arclen
        {
            if(i == 0 && vs > 0) do continue    // skip every first 2 vertices except the head
            defer vs += 1

            fmt.printfln("%v", vs)

            // for each rectangle;
            // calculate the necessary values
            lerp_value := f32(i) / f32(arclen)
            midpoint := Arc_ReturnPoint(r, lerp_value)
            rightvec := Arc_ReturnNormal(r, lerp_value)
            rightvec.y = 0
            rightvec = rl.Vector3Normalize(rightvec) * 0.5

            // set vertices
            // first vertex
            track_mesh.vertices[6 * vs]     = (midpoint - rightvec).x
            track_mesh.vertices[6 * vs + 1] = (midpoint - rightvec).y
            track_mesh.vertices[6 * vs + 2] = (midpoint - rightvec).z
            // second vertex
            track_mesh.vertices[6 * vs + 3] = (midpoint + rightvec).x
            track_mesh.vertices[6 * vs + 4] = (midpoint + rightvec).y
            track_mesh.vertices[6 * vs + 5] = (midpoint + rightvec).z
            // texture coordinates
            track_mesh.texcoords[4 * vs]     = 0
            track_mesh.texcoords[4 * vs + 2] = 1
            track_mesh.texcoords[4 * vs + 1] = f32(vs % 2)
            track_mesh.texcoords[4 * vs + 3] = f32(vs % 2)

            // we do not have enough vertices to create
            // a face at the first iteration so we pass
            if(vs == 0) do continue  

            // first face (left triangle)
            track_mesh.indices[6 * vs - 6] = u16(2 * vs - 2)
            track_mesh.indices[6 * vs - 5] = u16(2 * vs - 1)
            track_mesh.indices[6 * vs - 4] = u16(2 * vs)
            // second face (right triangle)
            track_mesh.indices[6 * vs - 3] = u16(2 * vs + 1)
            track_mesh.indices[6 * vs - 2] = u16(2 * vs)
            track_mesh.indices[6 * vs - 1] = u16(2 * vs - 1)
        }
    }

    rl.UploadMesh(&track_mesh, false) // upload mesh to gpu
    return track_mesh
}

MATRIX1 : rl.Matrix :
{
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
}

draw_mesh :: rl.DrawMesh

game_draw3d :: proc()
{
    draw_mesh(mesh1, rl.LoadMaterialDefault(), MATRIX1)
}

game_drawui :: proc()
{
    /*rl.DrawCircleV(arc1.p0.xz, 2, rl.YELLOW)
    rl.DrawCircleV(arc1.p1.xz, 2, rl.YELLOW)
    for i in 0..=f32(100)
    {
        rl.DrawCircleV(Arc_ReturnPoint(arc1, i / 100).xz, 1, rl.WHITE)
    }*/
}

// Keyboard and Mouse Input
INPUT_LEFTMOUSE :: rl.MouseButton.LEFT
INPUT_RIGHTMOUSE :: rl.MouseButton.RIGHT
INPUT_FORWARD :: rl.KeyboardKey.W
INPUT_LEFT :: rl.KeyboardKey.A
INPUT_BACK :: rl.KeyboardKey.S
INPUT_RIGHT :: rl.KeyboardKey.D

input_isdown :: proc{rl.IsKeyDown, rl.IsMouseButtonDown}