local mapa_permitido = "ph_danceparty_d3" -- Enter the exact map name here (without .bsp)

if string.lower(game.GetMap()) ~= string.lower(mapa_permitido) then
    return
end

AddCSLuaFile("danceparty_dj/sh_config.lua")
AddCSLuaFile("danceparty_dj/cl_dj.lua")
AddCSLuaFile("danceparty_dj/cl_ui.lua")

include("danceparty_dj/sh_config.lua")

if SERVER then
    include("danceparty_dj/sv_dj.lua")
end

if CLIENT then
    include("danceparty_dj/cl_dj.lua")
    include("danceparty_dj/cl_ui.lua")
end