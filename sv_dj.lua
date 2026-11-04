util.AddNetworkString("DanceParty_PlayTrack")
util.AddNetworkString("DanceParty_StopTrack")
util.AddNetworkString("DanceParty_OpenMenu")
util.AddNetworkString("DanceParty_StartVoteReq")
util.AddNetworkString("DanceParty_SyncPlayer")

local next_play_time = 0
local current_track_id = nil
local current_track_start = 0

local function NotifyPlayer(ply, msg)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

local function BroadcastChat(msg)
    for _, p in ipairs(player.GetAll()) do
        p:ChatPrint(msg)
    end
end

-- Função principal de disparo de áudio
local function TriggerPlay(track_id, forced_by, cooldown_override)
    if not DancePartyDJ.Playlist[track_id] then return end

    local speakers = ents.FindByName(DancePartyDJ.TargetSpeakerName)
    local positions = {}

    for _, ent in ipairs(speakers) do
        if IsValid(ent) then table.insert(positions, ent:GetPos()) end
    end

    if #positions == 0 then return end

    -- Aplica o cooldown especificado
    next_play_time = CurTime() + (cooldown_override or 60)
    current_track_id = track_id
    current_track_start = CurTime()

    net.Start("DanceParty_PlayTrack")
        net.WriteUInt(track_id, 8)
        net.WriteFloat(0.0)
        net.WriteUInt(#positions, 8)
        for _, pos in ipairs(positions) do
            net.WriteVector(pos)
        end
    net.Broadcast()

    if forced_by then
        BroadcastChat(string.format("[DJ] %s played: %s", forced_by, DancePartyDJ.Playlist[track_id].name))
    else
        BroadcastChat("[DJ] Auto-play: " .. DancePartyDJ.Playlist[track_id].name)
    end
end

local function PlayRandomTrack()
    if #DancePartyDJ.Playlist == 0 then return end
    local random_id = math.random(1, #DancePartyDJ.Playlist)
    TriggerPlay(random_id, nil, 30)
end

-- Intercepta o pedido do menu do cliente e toca instantaneamente
net.Receive("DanceParty_StartVoteReq", function(len, ply)
    local track_id = net.ReadUInt(8)
    if not DancePartyDJ.Playlist[track_id] then return end
    
    -- Se for Staff usando o menu, funciona exatamente como o !djforce (ignora cooldown)
    if DancePartyDJ.IsStaff(ply) then
        TriggerPlay(track_id, "Staff " .. ply:Nick(), 60)
        return
    end

    -- Se for um jogador normal pelo notebook, verifica se está em cooldown
    local time_left = math.ceil(next_play_time - CurTime())
    if time_left > 0 then
        NotifyPlayer(ply, string.format("[DJ] Please wait! System on cooldown for %d more seconds.", time_left))
        return
    end

    TriggerPlay(track_id, ply:Nick(), 60)
end)

-- Sincroniza jogadores que entram no meio do round
hook.Add("PlayerInitialSpawn", "DanceParty_SyncNewPlayer", function(ply)
    if current_track_id and DancePartyDJ.Playlist[current_track_id] then
        local elapsed = CurTime() - current_track_start
        local speakers = ents.FindByName(DancePartyDJ.TargetSpeakerName)
        local positions = {}

        for _, ent in ipairs(speakers) do
            if IsValid(ent) then table.insert(positions, ent:GetPos()) end
        end

        if #positions > 0 then
            timer.Simple(5.0, function()
                if IsValid(ply) and current_track_id then
                    net.Start("DanceParty_PlayTrack")
                        net.WriteUInt(current_track_id, 8)
                        net.WriteFloat(elapsed)
                        net.WriteUInt(#positions, 8)
                        for _, pos in ipairs(positions) do
                            net.WriteVector(pos)
                        end
                    net.Send(ply)
                end
            end)
        end
    end
end)

hook.Add("PlayerSay", "DanceParty_ChatCommands", function(ply, text)
    local args = string.Explode(" ", string.Trim(text))
    local cmd = string.lower(args[1] or "")

    if cmd == "!dj" then
        NotifyPlayer(ply, "[DJ Commands]: Interact with the laptop to pick a song | !djvol <0-100> | !djmute")
        if DancePartyDJ.IsStaff(ply) then
            -- Atualizei a mensagem de ajuda da Staff aqui também
            NotifyPlayer(ply, "[Staff Commands]: !djplay [id] (open menu or force track) | !djstop")
        end
        return ""
    end

    -- O novo comando inteligente !djplay
    if cmd == "!djplay" then
        if DancePartyDJ.IsStaff(ply) then
            local track_id = tonumber(args[2])
            
            -- Se ele digitou um número válido (ex: !djplay 5)
            if track_id and DancePartyDJ.Playlist[track_id] then
                TriggerPlay(track_id, "Staff " .. ply:Nick(), 60)
            else
                -- Se digitou APENAS !djplay ou um ID inválido, abre o menu
                net.Start("DanceParty_OpenMenu")
                net.Send(ply)
            end
        else
            NotifyPlayer(ply, "[DJ] Only Staff can use this remotely! Go to the DJ table and press 'E' on the laptop.")
        end
        return ""
    end

    if cmd == "!djstop" and DancePartyDJ.IsStaff(ply) then
        net.Start("DanceParty_StopTrack")
        net.Broadcast()
        current_track_id = nil
        next_play_time = 0
        BroadcastChat(string.format("[DJ] Music stopped by %s.", ply:Nick()))
        return ""
    end
end)

hook.Add("InitPostEntity", "DanceParty_AutoPlay_Spawn", function()
    timer.Simple(3.0, PlayRandomTrack)
end)

hook.Add("PH_RoundStart", "DanceParty_AutoPlay_RoundStart", function()
    timer.Simple(1.0, PlayRandomTrack)
end)

local next_spam_check = {}

hook.Add("PlayerUse", "DanceParty_LaptopInteraction", function(ply, ent)
    if IsValid(ent) and ent:GetName() == "dj_laptop" then
        if ply.DanceParty_MenuOpen and ply.DanceParty_MenuOpen > CurTime() then return end

        local time_left = math.ceil(next_play_time - CurTime())
        local steamid = ply:SteamID()

        -- Bloqueia TODOS (incluindo Staff) se houver cooldown no notebook físico
        if time_left > 0 then
            if not next_spam_check[steamid] or CurTime() >= next_spam_check[steamid] then
                NotifyPlayer(ply, string.format("[DJ] Please wait! Cooldown active for %d more seconds.", time_left))
                next_spam_check[steamid] = CurTime() + 3
            end
            return
        end

        ply.DanceParty_MenuOpen = CurTime() + 1.0
        net.Start("DanceParty_OpenMenu")
        net.Send(ply)
    end
end)