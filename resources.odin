package game

import rl "vendor:raylib"
import "core:fmt"

// DATA
TEXTURES : [4]rl.Texture2D
TEXTURE_NPATCHES : [4][dynamic]rl.NPatchInfo = {
    //ui
    {
        {{0, 0, 128, 128}, 32, 32, 32, 32, rl.NPatchLayout.NINE_PATCH}, // ui panel
    },
    {},
    {},
    {}
}

TEXTURE_ID :: enum int
{
    UI = 0,
}

NPATCH_ID :: enum int
{
    // 100x for each group
    UI_Button = 0,
}


SOUNDS : [16]rl.Sound

SOUND_ID :: enum int 
{
    NULL = 0,
}

FONTS : [4]rl.Font

// RETURN FUNCTIONS
tex :: proc (id : TEXTURE_ID) -> rl.Texture2D
{
    return TEXTURES[id]
}

npatch :: proc (id : NPATCH_ID) -> rl.NPatchInfo
{
    return TEXTURE_NPATCHES[int(id) / 100][int(id) % 100]
}

snd :: proc(id : SOUND_ID) -> rl.Sound
{
    return SOUNDS[id]
}

// SETUP FUNCTION
resources_setup :: proc()
{
    // Setup Textures
    TEXTURES[0] = rl.LoadTexture("res/tex_ui.png")

    // Setup Fonts
    FONTS[0] = rl.GetFontDefault()
}