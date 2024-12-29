package game

import rl "vendor:raylib"
import "core:fmt"

// DATA
TEXTURES : [16]rl.Texture2D

TEXTURE_ID :: enum int
{
    UI = 0,
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

snd :: proc(id : SOUND_ID) -> rl.Sound
{
    return SOUNDS[id]
}

// SETUP FUNCTION
resources_setup :: proc()
{
    // Setup Textures
    TEXTURES[0] = rl.LoadTexture("res/tex_ui.png")
}