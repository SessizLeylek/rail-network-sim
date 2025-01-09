package game

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// Camera
camera : rl.Camera3D = {{1, 0, 0}, {0, 0, 0}, {0, 1, 0}, 90, rl.CameraProjection.PERSPECTIVE}
camera_verticalAngle : f32 = 0.0
camera_distance : f32 = 10.0
camera_height : f32 = 1.0
camera_speed :: 8

shouldClose := false
main :: proc()
{
    rl.InitWindow(1280, 720, "Rail Network Sim")
    rl.SetExitKey(.END)
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

        if shouldClose do break
    }

    rl.CloseWindow()
}

//////////////////////////////////////////////////////////////
// Game Logic

actionState : InteractionState = .None
selectedNodeId : int
highlightedNodeId : int = -1
highlightedRailId : int = -1

arc1 : ArcSegment
mesh1 : rl.Mesh

game_start :: proc()
{
    temp_railline : RailLine
    append(&temp_railline.rails, ArcSegment {{0, 0, 0}, {1, 0, 0}, -rl.PI})
    append(&temp_railline.rails, ArcSegment {{2, 0, 0}, {2, 0, 5}, 0})
    append(&temp_railline.rails, ArcSegment {{2, 0, 5}, {4, 0, 5}, rl.PI})
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
        camera_height += cameraSpeedMultiplier * rl.GetMouseDelta().y * MOUSE_SENSITIVITY
        if camera_height > rl.PI * 0.48 do camera_height = rl.PI * 0.48
        if camera_height < 0.1 do camera_height = 0.1
    }
    else
    {
        rl.SetMouseCursor(.DEFAULT)
    }

    camera_distance -= rl.GetMouseWheelMove()
    if(camera_distance < 1) do camera_distance = 1
    else if(camera_distance > 50) do camera_distance = 50

    camera.position = rl.Vector3RotateByAxisAngle({math.cos(camera_height), math.sin(camera_height), 0} * camera_distance, {0, 1, 0}, camera_verticalAngle) + camera.target

    ray := rl.GetMouseRay(rl.GetMousePosition(), camera)
    rayCollision := rl.GetRayCollisionQuad(ray, {-100, 0, -100}, {-100, 0, 100}, {100, 0, 100}, {100, 0, -100})
    nearestNodeIndex := Draft_NearestNode(rayCollision.point, 1)
    railToDelete := Draft_NearestRail(rayCollision.point)
    highlightedNodeId = nearestNodeIndex
    highlightedRailId = railToDelete

    switch actionState
        {
            case .None:

                // Escape pauses game
                if(input_ispressed(INPUT_ESC))
                {
                    shouldClose = true
                    return
                } 

            case .Draft_NewRail:           // NEW RAIL WILL BE START BUILDING
                if(!input_isoverUI() && input_ispressed(INPUT_LEFTMOUSE))
                {
                    // start creating a new rail
                    if(rayCollision.hit)
                    {
                        if(nearestNodeIndex == -1)
                        {
                            // start creating from 0
                            selectedNodeId = Draft_NewNode(rayCollision.point, {0, 1})
                            Draft_SetTempRail(rayCollision.point, selectedNodeId)
                            actionState = .Draft_NewRailEnd
                        }
                        else
                        {
                            // start creating from an existing node
                            selectedNodeId = nearestNodeIndex
                            Draft_SetTempRail(rayCollision.point, selectedNodeId)
                            actionState = .Draft_NewRailEnd
                        }
                    }
                }
                else if(input_ispressed(INPUT_ESC))
                {
                    // escape state
                    ui_sections[1].isActive = true
                    actionState = .None
                }
            case .Draft_NewRailEnd:        // NEW RAIL WILL BE BUILT
                // update selected node

                // if head node is independent, make it look towards mouse
                if len(Draft_Nodes[selectedNodeId].connectedRailIds) == 0
                {
                    Draft_Nodes[selectedNodeId].dir = rl.Vector2Normalize((rayCollision.point - Draft_Nodes[selectedNodeId].pos).xz)
                }

                // calculate extend direction
                extendDirection : i8 = 1
                if rl.Vector3DotProduct(Draft_Nodes[selectedNodeId].dir.xxy * {1, 0, 1}, rayCollision.point - Draft_Nodes[selectedNodeId].pos) < 0 do extendDirection = -1

                if nearestNodeIndex == -1
                {
                    // temp rail will not be connected to an existing node
                    Draft_SetTempRail(rayCollision.point, selectedNodeId, extendDirection)
                }
                else
                {
                    if selectedNodeId == nearestNodeIndex do break
                    // temp rail will connect to an existing node
                    extendDirectionTail : i8 = 1
                    if rl.Vector3DotProduct(Draft_Nodes[nearestNodeIndex].dir.xxy * {1, 0, 1}, rayCollision.point - Draft_Nodes[nearestNodeIndex].pos) > 0 do extendDirectionTail = -1
                    Draft_SetTempRail(rayCollision.point, selectedNodeId, extendDirection, nearestNodeIndex, extendDirectionTail)
                }

                if(!input_isoverUI() && input_ispressed(INPUT_LEFTMOUSE))
                {
                    Draft_SaveTempRail()
                    actionState = .Draft_NewRail
                    
                }
                else if(input_ispressed(INPUT_ESC))
                {
                    Draft_ResetTempRail()

                    // delete the independent node
                    if len(Draft_Nodes[selectedNodeId].connectedRailIds) == 0
                    {
                        Draft_RemoveNode(selectedNodeId)
                    }
                    
                    
                    // escape state
                    ui_sections[1].isActive = true
                    actionState = .None

                }
            case .Draft_RemoveRail:        // THE SELECTED RAIL WILL BE REMOVED
                if !input_isoverUI() && input_ispressed(INPUT_LEFTMOUSE) && railToDelete != -1
                {
                    Draft_RemoveRail(railToDelete)
                    
                    // escape state
                    ui_sections[1].isActive = true
                    actionState = .None
                }
                else if input_ispressed(INPUT_ESC)
                {
                    // escape state
                    ui_sections[1].isActive = true
                    actionState = .None
                }
        }
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
            track_mesh.vertices[6 * vs]     = (midpoint + rightvec).x
            track_mesh.vertices[6 * vs + 1] = (midpoint + rightvec).y
            track_mesh.vertices[6 * vs + 2] = (midpoint + rightvec).z
            // second vertex
            track_mesh.vertices[6 * vs + 3] = (midpoint - rightvec).x
            track_mesh.vertices[6 * vs + 4] = (midpoint - rightvec).y
            track_mesh.vertices[6 * vs + 5] = (midpoint - rightvec).z
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

// how should user's interactions result
InteractionState :: enum int
{
    None = 0x00,
    Draft_NewRail = 0x10,
    Draft_NewRailEnd = 0x11,
    Draft_RemoveRail = 0x12,
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

    // Draw Draft Mode
    if(i32(actionState) / 16 == 1 || ui_sections[1].isActive)
    {
        for n, i in Draft_Nodes
        {
            col := rl.YELLOW
            if highlightedNodeId == i && (actionState == .Draft_NewRail || actionState == .Draft_NewRailEnd) do col = rl.SKYBLUE

            rl.DrawSphere(n.pos, 0.5, col)
        }

        for r, j in Draft_Rails
        {
            for i in 0..<Arc_ReturnLength(r.arc) * 5
            {
                col := rl.GREEN
                if highlightedRailId == j && actionState == .Draft_RemoveRail do col = rl.SKYBLUE

                rl.DrawSphere(Arc_ReturnPoint(r.arc, f32(i) / Arc_ReturnLength(r.arc) * 0.2), 0.1, col)
            }
        }

        if temp_rail.isSet
        {
            for s in 0..=temp_rail.shape
            {
                for i in 0..=Arc_ReturnLength(temp_rail.arcs[s])
                {
                    rl.DrawSphere(Arc_ReturnPoint(temp_rail.arcs[s], f32(i) / Arc_ReturnLength(temp_rail.arcs[s])), 0.1, rl.LIGHTGRAY)
                }
            }
        }
    }
}

game_drawui :: proc()
{
    // Draw Dynamic Ui
    button_clicked = false
    for &sec in ui_sections
    {
        if(!sec.isActive) do continue

        for &obj in sec.objects
        {
            ui_draw_object(&obj, &sec)
        }
    }

    // state
    rl.DrawFPS(0, 0)
    rl.DrawText(rl.TextFormat("state: %i", actionState), 0, 64, 32, rl.RAYWHITE)
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
        clickEvent : proc(),
    }

    // the effect that starts when a button is pressed
    UiButtonEffect :: struct
    {
        panel: UiPanel,
        startTime : f64,
    }

    // union of ui objects
    UiObject :: union
    {
        UiPanel, UiButton, UiButtonEffect, UiTextField,
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
            case UiButtonEffect:
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

    ui_draw_object :: proc(obj : ^UiObject, sec : ^UiSection)
    {
        
        // Draw appropriate element
        switch &v in obj
        {
            case UiPanel:
                // Draw Panel
                ui_draw_panel(v, sec^)
            case UiButton:
                // mouse over button logic
                button := &v
                dMousePos := rl.GetMousePosition() - ui_calculate_pos(v.panel.element, sec)
                if(dMousePos.x > 0 && dMousePos.y > 0 &&
                    dMousePos.x < ui_get_element(v).size.x && dMousePos.y < ui_get_element(v).size.y)
                {
                    // mouse is over button
                    button.panel.color = rl.SKYBLUE

                    //mouse click event
                    if(input_ispressed(INPUT_LEFTMOUSE) && !button_clicked)
                    {
                        ui_create_button_effect(ui_get_element(v), sec^)

                        button_clicked = true
                        if button.clickEvent != nil do button.clickEvent()
                    }
                }
                else
                {
                    // mouse is not over button
                    button.panel.color = rl.BLUE
                }

                // Draw Button
                ui_draw_panel(v.panel, sec^)
            case UiButtonEffect:
                // slowly fade button effect
                passedTime := rl.GetTime() - v.startTime 
                if(passedTime < 0.25)
                {
                    panel := &v.panel

                    // increase size and opacity over time
                    newColor := rl.SKYBLUE
                    newColor.a = 255 - u8(passedTime * 1020)
                    panel.color = newColor
                    panel.element.size *= f32(1 + (0.25 - passedTime) * 0.02)
                    ui_draw_panel(panel^, sec^)
                }
                else
                {
                    // hide the section when it is time
                    sec.isActive = false
                }

            case UiTextField:
                // Draw Text
                ui_draw_text(v, sec^)
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
    ui_sections : [8]UiSection

    // ui design
    ui_setup :: proc()
    {
        // section 7 is reserved for temp
        ui_sections[7] = UiSection {{{0, 0}, {0, 0}, {0, 0}}, false, make([dynamic]UiObject)}

        // Main Hotbar
        ui_sections[0] = UiSection {{{0.5, 1}, {0.5, 1}, {640, 128}}, true, make([dynamic]UiObject)}
        ui_sections[0].objects = {
            ui_setup_panel({0.5, 1}, {0.5, 1}, {640, 128}, rl.GRAY), 
            ui_setup_button({0.5, 0.5}, {0.75, 0.18}, {300, 40}, button_enter_draft_mode),     // draft mode button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[0].objects, 1),
            ui_setup_button({0.5, 0.5}, {0.75, 0.5}, {300, 40}, button_enter_line_mode),     // rail line button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[0].objects, 3),
            ui_setup_button({0.5, 0.5}, {0.75, 0.82}, {300, 40}, button_enter_route_mode),     // route mode button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[0].objects, 5)}
        ui_update_text(&ui_sections[0].objects[2].(UiTextField), "Draft Mode")
        ui_update_text(&ui_sections[0].objects[4].(UiTextField), "Rail Lines")
        ui_update_text(&ui_sections[0].objects[6].(UiTextField), "Route Mode")

        // Draft Mode Hotbar
        ui_sections[1] = UiSection {{{0.5, 1}, {0.5, 1}, {640, 128}}, false, make([dynamic]UiObject)}
        ui_sections[1].objects = {
            ui_setup_panel({0.5, 1}, {0.5, 1}, {640, 128}, rl.GRAY), 
            ui_setup_text({0.5, 0}, {0.5, 0.02}, 0, 40, rl.WHITE, nil, 0),    // mode title
            ui_setup_button({0.5, 0.5}, {0.25, 0.5}, {300, 40}, button_draft_newrail),     // new rail button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[1].objects, 2),
            ui_setup_button({0.5, 0.5}, {0.75, 0.5}, {300, 40}, button_draft_delete),     // delete rail button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[1].objects, 4),
            ui_setup_button({0.5, 0.5}, {0.25, 0.82}, {300, 40}, button_exit_draft_mode),     // return button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[1].objects, 6),
            ui_setup_button({0.5, 0.5}, {0.75, 0.82}, {300, 40}, button_draft_construct),     // construct button
            ui_setup_text({0.5, 0.5}, {0.5, 0.5}, 0, 32, rl.BLACK, &ui_sections[1].objects, 8)}
        ui_update_text(&ui_sections[1].objects[1].(UiTextField), "Draft Mode")
        ui_update_text(&ui_sections[1].objects[3].(UiTextField), "New Rail")
        ui_update_text(&ui_sections[1].objects[5].(UiTextField), "Delete Rail")
        ui_update_text(&ui_sections[1].objects[7].(UiTextField), "Save & Return")
        ui_update_text(&ui_sections[1].objects[9].(UiTextField), "Construct Rails")
    }

    ui_setup_panel :: proc(anchor, pos, size : [2]f32, color : rl.Color) -> UiPanel
    {
        return UiPanel {{anchor, pos, size}, color}
    }

    ui_setup_button :: proc(anchor, pos, size : [2]f32, clickEvent : proc()) -> UiButton
    {
        return UiButton {ui_setup_panel(anchor, pos, size, rl.BLUE), clickEvent}
    }

    ui_setup_buttonEffect :: proc(size : [2]f32) -> UiButtonEffect
    {
        return UiButtonEffect {ui_setup_panel({0.5, 0.5}, {0.5, 0.5}, size, rl.SKYBLUE), rl.GetTime()}
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

    // creates a button effect
    ui_create_button_effect :: proc(elem : UiElement, sec : UiSection)
    {
        // create temp section
        delete_dynamic_array(ui_sections[7].objects)
        ui_sections[7] = UiSection {{{0, 0}, ui_calculate_pos(elem, sec) / screen_dim, elem.size}, true, make([dynamic]UiObject)}
        ui_sections[7].objects = {ui_setup_buttonEffect(elem.size)}
    }

    test_hi :: proc()
    {
        fmt.println("HI!")
    }

    button_clicked : bool = false

    // Enter Draft Mode Button
    button_enter_draft_mode :: proc()
    {
        ui_sections[0].isActive = false
        ui_sections[1].isActive = true
    }

    button_enter_line_mode :: proc()
    {

    }

    button_enter_route_mode :: proc()
    {

    }

    // Exit Draft Mode Button
    button_exit_draft_mode :: proc()
    {
        ui_sections[0].isActive = true
        ui_sections[1].isActive = false
    }

    button_draft_construct :: proc()
    {
        //exit draft mode
        button_exit_draft_mode()
        Draft_ConstructAll()
    }

    button_draft_newrail :: proc()
    {
        // start placing a new node
        ui_sections[1].isActive = false
        actionState = .Draft_NewRail
    }

    button_draft_delete :: proc()
    {
        // delete a new node
        ui_sections[1].isActive = false
        actionState = .Draft_RemoveRail
    }
}

//////////////////////////////////////////////////////////////
// Keyboard and Mouse Input
INPUT_LEFTMOUSE :: rl.MouseButton.LEFT
INPUT_RIGHTMOUSE :: rl.MouseButton.RIGHT
INPUT_ESC :: rl.KeyboardKey.ESCAPE
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

