DancePartyDJ = DancePartyDJ or {}

DancePartyDJ.TargetSpeakerName = "soundbar_1"
DancePartyDJ.CooldownTime = 60
DancePartyDJ.FadeMin = 350
DancePartyDJ.FadeMid = 700 
DancePartyDJ.FadeMax = 3000
DancePartyDJ.FadeMidVolume = 0.05

-- Permissions ULX / Staff
DancePartyDJ.StaffGroups = {
    ["superadmin"] = true,
    ["admin"]      = true,
    ["moderator"]  = true,
    ["helper"]     = true,
}

-- Vinyl scratch sound
DancePartyDJ.ScratchSound = "ambient/machines/squeak_5.wav"

-- Proteção Anti-Refresh: Mantém a lista intacta se o arquivo for recarregado pelo motor do jogo
DancePartyDJ.Playlist = DancePartyDJ.Playlist or {}

-- Transformada em função global para ser acessada em qualquer cenário
function DancePartyDJ.FetchPlaylist()
    -- Replace with your domain or IP where the Python panel runs
    http.Fetch("http://108.174.151.244:5000/api/tracks",
        function(body, length, headers, code)
            if code == 200 then
                local data = util.JSONToTable(body)
                if data and istable(data) then
                    DancePartyDJ.Playlist = {}
                    for _, track in ipairs(data) do
                        table.insert(DancePartyDJ.Playlist, {
                            name = track.name,
                            url = track.url
                        })
                    end
                    print(string.format("[DJ] Playlist loaded successfully! Total tracks: %d", #DancePartyDJ.Playlist))
                end
            else
                print("[DJ] Failed to fetch playlist. HTTP code: " .. tostring(code))
            end
        end,
        function(failed)
            print("[DJ] HTTP request failed: " .. tostring(failed))
        end
    )
end

-- Usa InitPostEntity para garantir que a placa de rede virtual do GMod já está operante
hook.Add("InitPostEntity", "DanceParty_LoadRemotePlaylist", function()
    timer.Simple(2.0, function()
        DancePartyDJ.FetchPlaylist()
    end)
end)

-- Gatilho de Segurança: Se a lista zerar (por salvar o script com o jogo aberto), força o download na hora
if not DancePartyDJ.Playlist or #DancePartyDJ.Playlist == 0 then
    DancePartyDJ.FetchPlaylist()
end

-- Console command for staff to hot-reload the playlist without restarting the map
if SERVER then
    util.AddNetworkString("DJ_SyncPlaylist")

    concommand.Add("dj_refresh_playlist", function(ply)
        if IsValid(ply) and not DancePartyDJ.IsStaff(ply) then return end
        
        -- O servidor atualiza a sua própria lista interna
        DancePartyDJ.FetchPlaylist()
        
        -- Envia um sinal de rede forçando TODOS os jogadores a baixarem a lista nova
        net.Start("DJ_SyncPlaylist")
        net.Broadcast()

        if IsValid(ply) then
            ply:ChatPrint("[DJ] Playlist atualizada no servidor e forçada em todos os clientes!")
        end
    end)
end

if CLIENT then
    net.Receive("DJ_SyncPlaylist", function()
        -- O jogo de cada jogador recebe o aviso e baixa o JSON do painel Python
        DancePartyDJ.FetchPlaylist()
        chat.AddText(Color(50, 200, 255), "[DJ] ", Color(255, 255, 255), "A playlist de músicas foi atualizada pela staff!")
    end)
end

function DancePartyDJ.IsStaff(ply)
    if not IsValid(ply) then return true end
    return DancePartyDJ.StaffGroups[string.lower(ply:GetUserGroup())] or ply:IsAdmin()
end