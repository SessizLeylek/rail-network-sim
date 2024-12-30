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
    rl.SetTargetFPS(120)

    screen_dim = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

    resources_setup()
    ui_setup()
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

//////////////////////////////////////////////////////////////
// Game Logic

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
        MOUSE_SENSITIVITY :: 0.1

        rl.SetMouseCursor(.RESIZE_ALL)
        camera_verticalAngle += cameraSpeedMultiplier * -rl.GetMouseDelta().x * MOUSE_SENSITIVITY
        camera_height += cameraSpeedMultiplier * rl.GetMouseDelta().y * 5 * MOUSE_SENSITIVITY
    }
    else
    {
        rl.SetMouseCursor(.DEFAULT)
    }

    camera_distance -= rl.GetMouseWheelMove()
    if(camera_distance < 1) do camera_distance = 1
    else if(camera_distance > 50) do camera_distance = 50

    if input_ispressed(INPUT_LEFTMOUSE)
    {
        if input_isoverUI() do fmt.println("OVER UI")
        else do fmt.println("FREE")
    }

    camera.position = rl.Vector3RotateByAxisAngle({-camera_distance, camera_height, 0}, {0, 1, 0}, camera_verticalAngle) + camera.target
}

// Creates a mesh from given rail line
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

//////////////////////////////////////////////////////////////
// Drawing Section

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
    for sec in ui_sections
    {
        if(!sec.isActive) do continue

        for &obj in sec.objects
        {
            ui_draw_object(&obj, sec)
        }
    }
}

//////////////////////////////////////////////////////////////
// UI Elements
when true
{
    screen_dim : [2]f32

    // stores transformation properties of a ui element
    UiElement :: struct
    {
        anchor, position, size : [2]f32,
    }

    UiTextField :: struct
    {
        element : UiElement,
        content : cstring,
        fontIndex : int,
        fontSize : f32,
        color : rl.Color,
        objectArray : ^[dynamic]UiObject,
        parentId : int,
    }

    // plain 2d image with a color
    UiPanel :: struct
    {
        element : UiElement,
        color : rl.Color
    }

    // a clickable panel
    UiButton :: struct
    {
        panel : UiPanel,
        originalSize : [2]f32,
        lastClickTime : f64,
        clickEvent : proc(),
    }

    // union of ui objects
    UiObject :: union
    {
        UiPanel, UiButton, UiTextField,
    }

    ui_get_element :: proc(obj : UiObject) -> UiElement
    {
        // gets the uielement out of ui object
        switch &v in obj
        {
            case UiPanel:
                return v.element
            case UiButton:
                return v.panel.element
            case UiTextField:
                return v.element
        }

        return {}
    }

    ui_calculate_pos :: proc(elem : UiElement, sec : $T) -> [2]f32
    {
        sec_pos := -sec.anchor * sec.size + sec.position * screen_dim
        return -elem.anchor * elem.size + elem.position * sec.size + sec_pos
    }

    ui_draw_object :: proc(obj : ^UiObject, sec : UiSection)
    {
        // Draw appropriate element
        switch &v in obj
        {
            case UiPanel:
                // Draw Panel
                ui_draw_panel(v, sec)
            case UiButton:
                // mouse over button logic
                button := &v
                dMousePos := rl.GetMousePosition() - ui_calculate_pos(v.panel.element, sec)
                if(dMousePos.x > 0 && dMousePos.y > 0 &&
                    dMousePos.x < button.originalSize.x && dMousePos.y < button.originalSize.y)
                {
                    // mouse is over button
                    button.panel.color = rl.SKYBLUE

                    //mouse click event
                    if(input_ispressed(INPUT_LEFTMOUSE))
                    {
                        button.panel.element.size = button.originalSize * {0.8, 1.25}
                        button.lastClickTime = rl.GetTime()
                        button.clickEvent()
                    }
                }
                else
                {
                    // mouse is not over button
                    button.panel.color = rl.BLUE
                }

                // button click animation
                lerpval := f32(clamp(rl.GetTime() - button.lastClickTime, 0, 0.25))
                button.panel.element.size = button.originalSize * ({0.8, 1.25} * (0.25 - lerpval) + {1, 1} * lerpval) * 4

                // Draw Button
                ui_draw_panel(v.panel, sec)
            case UiTextField:
                // Draw Text
                ui_draw_text(v, sec)
        }
    }

    ui_draw_panel :: proc(panel : UiPanel, sec : UiSection)
    {
        pos := ui_calculate_pos(panel.element, sec)
        rl.DrawTextureNPatch(tex(.UI), npatch(.UI_Button), {pos.x, pos.y, panel.element.size.x, panel.element.size.y}, {0, 0}, 0, panel.color)
    }

    ui_draw_text :: proc(text : UiTextField, sec : UiSection)
    {
        pos : [2]f32
        if(text.objectArray == nil) do pos = ui_calculate_pos(text.element, sec)
        else  
        {
            parent := ui_get_element(text.objectArray[text.parentId]) 
            pos = ui_calculate_pos(parent, sec) + (parent.size - text.element.size) * 0.5
        }

        rl.DrawTextEx(FONTS[text.fontIndex], text.content, pos, text.fontSize, 1, text.color)
    }

    // similar to html <div>
    UiSection :: struct
    {
        using element : UiElement,
        isActive : bool,
        objects : [dynamic]UiObject,
    }
    ui_sections : [4]UiSection

    // ui design
    ui_setup :: proc()
    {
        ui_sections[0] = UiSection {{{0.5, 1}, {0.5, 1}, {640, 160}}, true, make([dynamic]UiObject)}
        ui_sections[0].objects = {
            ui_setup_panel({0.5, 1}, {0.5, 1}, {640, 320}, rl.GRAY), 
            ui_setup_button({0.5, 0.5}, {0.5, 0.5}, {256, 128}, test_hi),
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 64, rl.BLACK, &ui_sections[0].objects, 1)}
        ui_update_text(&ui_sections[0].objects[2].(UiTextField), "TEST")
    }

    ui_setup_panel :: proc(anchor, pos, size : [2]f32, color : rl.Color) -> UiPanel
    {
        return UiPanel {{anchor, pos, size}, color}
    }

    ui_setup_button :: proc(anchor, pos, size : [2]f32, clickEvent : proc()) -> UiButton
    {
        return UiButton {ui_setup_panel(anchor, pos, size, rl.BLUE), size, -1, clickEvent}
    }

    ui_setup_text :: proc(anchor, pos : [2]f32, fontIndex : int, fontSize : f32, color : rl.Color, objectArray : ^[dynamic]UiObject, parentId : int) -> UiTextField
    {
        return UiTextField {{anchor, pos, {0, 0}}, "text not updated", fontIndex, fontSize, color, objectArray, parentId}
    }

    ui_update_text :: proc(text : ^UiTextField, content : cstring)
    {
        text.content = content
        text.element.size = rl.MeasureTextEx(FONTS[text.fontIndex], content, text.fontSize, 1)
    }

    test_hi :: proc()
    {
        fmt.println("HI!")
    }
}

//////////////////////////////////////////////////////////////
// Keyboard and Mouse Input
INPUT_LEFTMOUSE :: rl.MouseButton.LEFT
INPUT_RIGHTMOUSE :: rl.MouseButton.RIGHT
INPUT_FORWARD :: rl.KeyboardKey.W
INPUT_LEFT :: rl.KeyboardKey.A
INPUT_BACK :: rl.KeyboardKey.S
INPUT_RIGHT :: rl.KeyboardKey.D

input_isdown :: proc{rl.IsKeyDown, rl.IsMouseButtonDown}
input_ispressed :: proc{rl.IsKeyPressed, rl.IsMouseButtonPressed}

input_isoverUI :: proc() -> bool
{
    mousepos := rl.GetMousePosition()
    for sec in ui_sections
    {
        if !sec.isActive do continue

        dMousePos := rl.GetMousePosition() - ui_calculate_pos({{0, 0}, {0, 0}, sec.size}, sec)
        if(dMousePos.x > 0 && dMousePos.y > 0 && dMousePos.x < sec.size.x && dMousePos.y < sec.size.y) do return true
    }

    return false
}

