DancePartyDJ = DancePartyDJ or {}

local active_channels = {}
local current_playback_id = 0
local playback_start_time = 0

DancePartyDJ.UserVolume = 1.0

if CLIENT then
    timer.Simple(1.0, function()
        pcall(function()
            DancePartyDJ.UserVolume = cookie.GetNumber("danceparty_dj_vol", 1.0)
        end)
    end)
end

function DancePartyDJ.SetUserVolume(vol)
    DancePartyDJ.UserVolume = math.Clamp(vol, 0.0, 1.0)
    pcall(function()
        cookie.Set("danceparty_dj_vol", tostring(DancePartyDJ.UserVolume))
    end)
end

local function ClearActiveChannels(play_scratch)
    current_playback_id = current_playback_id + 1
    local channels_to_kill = active_channels
    active_channels = {}

    if play_scratch and #channels_to_kill > 0 and DancePartyDJ.ScratchSound then
        surface.PlaySound(DancePartyDJ.ScratchSound)
    end

    for _, ch in pairs(channels_to_kill) do
        if IsValid(ch) then ch:Stop() end
    end
end

net.Receive("DanceParty_StopTrack", function()
    ClearActiveChannels(true)
end)

-- =====================================================================
-- O SISTEMA DE BUFFER PERFEITO (4 CAIXAS FÍSICAS SIMULTÂNEAS)
-- =====================================================================
-- Flags corretas: noplay + noblock (obrigatório pro SetTime funcionar bem)
local PLAY_FLAGS = "3d mono noplay noblock"

net.Receive("DanceParty_PlayTrack", function()
    local request_time = CurTime()
    local track_id = net.ReadUInt(8)
    local base_elapsed_time = net.ReadFloat()
    local count = net.ReadUInt(8)

    local positions = {}
    for i = 1, count do
        table.insert(positions, net.ReadVector())
    end

    local track = DancePartyDJ.Playlist[track_id]
    if not track then return end

    ClearActiveChannels(true)

    local session_id = current_playback_id
    local loaded_stations = {}
    local responses = 0

    for idx = 1, count do
        sound.PlayURL(track.url, PLAY_FLAGS, function(station, errCode, errDesc)
            responses = responses + 1

            if session_id ~= current_playback_id then
                if IsValid(station) then station:Stop() end
                return
            end

            if IsValid(station) then
                station:SetPos(positions[idx])
                station:Set3DFadeDistance(999999, 999999)
                station:SetVolume(0)
                table.insert(loaded_stations, station)
            else
                print(string.format("[DJ] Speaker error (%s): %s", tostring(errCode), tostring(errDesc or "unknown")))
            end
        end)
    end

    local check_timer = "DJ_BufferCheck_" .. session_id
    timer.Create(check_timer, 0.05, 0, function()
        if session_id ~= current_playback_id then
            timer.Remove(check_timer)
            return
        end

        if responses < count then return end
        if #loaded_stations == 0 then
            timer.Remove(check_timer)
            return
        end

        -- Com "noplay" o estado correto é STOPPED (ou PAUSED em alguns casos)
        local all_ready = true
        for _, st in ipairs(loaded_stations) do
            if not IsValid(st) or (st:GetState() ~= GMOD_CHANNEL_STOPPED and st:GetState() ~= GMOD_CHANNEL_PAUSED) then
                all_ready = false
                break
            end
        end

        if not all_ready then return end

        timer.Remove(check_timer)

        -- Tempo alvo (levando em conta o delay do net + carregamento)
        local tempo_exato = base_elapsed_time + (CurTime() - request_time)
        playback_start_time = CurTime()

        -- Disparo simultâneo o mais apertado possível
        for _, st in ipairs(loaded_stations) do
            if IsValid(st) then
                st:SetTime(tempo_exato)
                st:Play()
                table.insert(active_channels, st)
            end
        end

        -- =====================================================
        -- CORREÇÃO CONTÍNUA (isso é o que realmente resolve o desync)
        -- =====================================================
        local resync_timer = "DJ_Resync_" .. session_id
        timer.Create(resync_timer, 0.8, 0, function() -- 0.6 ~ 1.2s funciona bem
            if session_id ~= current_playback_id or #active_channels == 0 then
                timer.Remove(resync_timer)
                return
            end

            -- Tempo esperado baseado no momento em que começamos a tocar
            local expected = tempo_exato + (CurTime() - playback_start_time)

            -- Ou use o canal mais "atrasado"/mais "avançado" como master (melhor em alguns casos)
            -- local master = active_channels[1]
            -- if not IsValid(master) then return end
            -- local expected = master:GetTime()

            for _, st in ipairs(active_channels) do
                if IsValid(st) and st:GetState() == GMOD_CHANNEL_PLAYING then
                    local current = st:GetTime()
                    local diff = math.abs(current - expected)

                    -- Só corrige se a diferença for perceptível (evita clicks)
                    if diff > 0.04 then -- 40ms é um bom limite
                        st:SetTime(expected)
                    end
                end
            end
        end)
    end)
end)

-- =====================================================================
-- O Cérebro de Volume e Distância (Think)
-- =====================================================================
hook.Add("Think", "DancePartyDJ_VolumeFader", function()
    if #active_channels == 0 then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local view_ent = ply:GetViewEntity()
    local listener_pos = IsValid(view_ent) and view_ent:GetPos() or ply:GetPos()

    local fade_min = DancePartyDJ.FadeMin or 350
    local fade_mid = DancePartyDJ.FadeMid or 700
    local fade_max = DancePartyDJ.FadeMax or 3000
    local mid_vol = DancePartyDJ.FadeMidVolume or 0.05
    local user_vol = DancePartyDJ.UserVolume or 1
    
    local fade_in_mult = math.Clamp((CurTime() - playback_start_time) / 1.0, 0, 1)

    for i = #active_channels, 1, -1 do
        local station = active_channels[i]
        if not IsValid(station) then
            table.remove(active_channels, i)
            continue
        end
        
        local dist = listener_pos:Distance(station:GetPos())
        local dist_mult = 1
        
        if dist >= fade_max then
            dist_mult = 0 
        elseif dist > fade_mid then
            local fraction = (dist - fade_mid) / (fade_max - fade_mid)
            dist_mult = mid_vol * (1 - fraction)
        elseif dist > fade_min then
            local fraction = (dist - fade_min) / (fade_mid - fade_min)
            dist_mult = mid_vol + (1 - mid_vol) * math.pow(1 - fraction, 3)
        end
        
        station:SetVolume(user_vol * fade_in_mult * dist_mult)
    end
end)