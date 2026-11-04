surface.CreateFont("DJ_Title",   { font = "Roboto", size = 18, weight = 700, antialias = true })
surface.CreateFont("DJ_Text",    { font = "Roboto", size = 15, weight = 500, antialias = true })
surface.CreateFont("DJ_SubText", { font = "Roboto", size = 13, weight = 400, antialias = true })

-- =====================================================================
-- Main Menu: Track Selection
-- =====================================================================
net.Receive("DanceParty_OpenMenu", function()
    local frame = vgui.Create("DFrame")
    frame:SetSize(420, 560)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()

    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(24, 24, 27, 250))
        draw.RoundedBoxEx(8, 0, 0, w, 46, Color(15, 15, 17, 255), true, true, false, false)
        draw.SimpleText("Dance Party DJ", "DJ_Title", 16, 23, Color(240, 240, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        -- Fallback UI se a playlist estiver vazia (ainda baixando a internet)
        if not DancePartyDJ.Playlist or #DancePartyDJ.Playlist == 0 then
            draw.SimpleText("Loading track list...", "DJ_Title", w / 2, h / 2 - 20, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Please wait a few seconds.", "DJ_SubText", w / 2, h / 2 + 5, Color(160, 160, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetSize(30, 30)
    closeBtn:SetPos(frame:GetWide() - 40, 8)
    closeBtn:SetText("✕")
    closeBtn:SetFont("DJ_Title")
    closeBtn.Paint = function(self, w, h)
        if self:IsHovered() then
            draw.RoundedBox(6, 0, 0, w, h, Color(239, 68, 68, 200))
            self:SetTextColor(Color(255, 255, 255))
        else
            self:SetTextColor(Color(160, 160, 170))
        end
    end
    
    closeBtn.DoClick = function()
        frame:SetVisible(false)
        frame:Close()
        gui.EnableScreenClicker(false)
    end

    -- Search bar
    local searchEntry = vgui.Create("DTextEntry", frame)
    searchEntry:SetPos(16, 56)
    searchEntry:SetSize(frame:GetWide() - 32, 36)
    searchEntry:SetFont("DJ_Text")
    searchEntry:SetTextColor(Color(245, 245, 245))
    searchEntry:SetPlaceholderText("Search track by name or ID...")
    searchEntry.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(39, 39, 42, 255))
        if self:GetText() == "" and not self:HasFocus() then
            draw.SimpleText(self:GetPlaceholderText(), "DJ_Text", 12, h / 2, Color(113, 113, 122), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        self:DrawTextEntryText(Color(240, 240, 245), Color(59, 130, 246), Color(255, 255, 255))
    end

    -- Scrollable track list
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:SetPos(16, 100)
    scroll:SetSize(frame:GetWide() - 32, frame:GetTall() - 116)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function() end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        draw.RoundedBox(3, 0, 0, w, h, Color(82, 82, 91, 180))
    end

    local function PopulateList(filter)
        scroll:Clear()
        if not DancePartyDJ.Playlist or #DancePartyDJ.Playlist == 0 then return end
        
        filter = string.lower(string.Trim(filter or ""))

        for id, data in ipairs(DancePartyDJ.Playlist) do
            local name = data.name
            if filter == "" or string.find(string.lower(name), filter, 1, true) or tostring(id) == filter then
                local card = scroll:Add("DButton")
                card:Dock(TOP)
                card:DockMargin(0, 0, 0, 8)
                card:SetTall(50)
                card:SetText("")

                card.Paint = function(self, w, h)
                    local bgCol = self:IsHovered() and Color(59, 130, 246, 35) or Color(39, 39, 42, 200)
                    local borderCol = self:IsHovered() and Color(59, 130, 246, 180) or Color(63, 63, 70, 100)

                    draw.RoundedBox(6, 0, 0, w, h, bgCol)
                    surface.SetDrawColor(borderCol)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)

                    draw.RoundedBox(4, 10, 10, 30, 30, Color(24, 24, 27, 220))
                    draw.SimpleText(id, "DJ_Title", 25, 25, Color(161, 161, 170), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

                    draw.SimpleText(name, "DJ_Text", 52, 18, Color(245, 245, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("Click to play track", "DJ_SubText", 52, 34, Color(113, 113, 122), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                card.DoClick = function()
                    net.Start("DanceParty_StartVoteReq")
                        net.WriteUInt(id, 8)
                    net.SendToServer()
                    
                    frame:SetVisible(false)
                    frame:Close()
                    gui.EnableScreenClicker(false)
                end
            end
        end
    end

    searchEntry.OnChange = function(self)
        PopulateList(self:GetText())
    end

    PopulateList("")
    
    -- Vigia infinito que atualiza o menu sozinho caso ele tenha sido aberto enquanto a lista estava a carregar
    frame.Think = function(self)
        if not self.LastPlaylistCount then self.LastPlaylistCount = 0 end
        local currentCount = (DancePartyDJ.Playlist and #DancePartyDJ.Playlist) or 0
        
        if currentCount ~= self.LastPlaylistCount then
            self.LastPlaylistCount = currentCount
            PopulateList(searchEntry:GetText())
        end
    end
end)

-- =====================================================================
-- Mini Panel: Only for Volume Control (!djvol)
-- =====================================================================
function DancePartyDJ.OpenVolumeMenu()
    if IsValid(DancePartyDJ.VolFrame) then DancePartyDJ.VolFrame:Remove() end

    local frame = vgui.Create("DFrame")
    frame:SetSize(300, 100)
    frame:Center()
    frame:SetTitle("DJ - Volume Control")
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(30, 30, 30, 240))
        draw.RoundedBox(8, 0, 0, w, 25, Color(50, 50, 50, 255))
    end
    DancePartyDJ.VolFrame = frame

    local slider = vgui.Create("DNumSlider", frame)
    slider:Dock(FILL)
    slider:DockMargin(15, 10, 15, 10)
    slider:SetText("Volume (%)")
    slider:SetMin(0)
    slider:SetMax(100)
    slider:SetDecimals(0)
    slider:SetValue(DancePartyDJ.UserVolume * 100)

    slider.OnValueChanged = function(self, val)
        DancePartyDJ.SetUserVolume(val / 100)
    end
end

-- =====================================================================
-- Local Chat Interceptor (!djvol, !djmute, !djlist)
-- =====================================================================
hook.Add("OnPlayerChat", "DanceParty_ClientCommands", function(ply, text)
    if ply ~= LocalPlayer() then return end
    
    local args = string.Explode(" ", string.lower(text))
    local cmd = args[1]
    
    -- Mute command
    if cmd == "!djmute" then
        if DancePartyDJ.UserVolume > 0 then
            DancePartyDJ.LastVolume = DancePartyDJ.UserVolume
            DancePartyDJ.SetUserVolume(0)
            chat.AddText(Color(0, 200, 255), "[DJ] ", Color(255, 255, 255), "Music muted.")
        else
            DancePartyDJ.SetUserVolume(DancePartyDJ.LastVolume or 0.5)
            chat.AddText(Color(0, 200, 255), "[DJ] ", Color(255, 255, 255), "Music unmuted.")
        end
        return true 
    end
    
    -- Volume command
    if cmd == "!djvol" then
        local val = tonumber(args[2])
        if val then
            DancePartyDJ.SetUserVolume(math.Clamp(val / 100, 0, 1))
            chat.AddText(Color(0, 200, 255), "[DJ] ", Color(255, 255, 255), "Volume set to " .. math.floor(val) .. "%")
        else
            DancePartyDJ.OpenVolumeMenu()
        end
        return true
    end

    -- Comando: !djlist (Mostra a lista localmente sem poluir o chat global)
    if cmd == "!djlist" then
        if not DancePartyDJ.Playlist or #DancePartyDJ.Playlist == 0 then
            chat.AddText(Color(0, 200, 255), "[DJ] ", Color(255, 100, 100), "The playlist is currently loading or empty.")
            return true
        end

        chat.AddText(Color(0, 200, 255), "=== DJ TRACK LIST ===")
        for id, track in ipairs(DancePartyDJ.Playlist) do
            chat.AddText(Color(100, 255, 100), tostring(id) .. " - ", Color(200, 200, 200), track.name)
        end
        chat.AddText(Color(0, 200, 255), "======================")
        chat.AddText(Color(255, 255, 255), "Total: ", Color(0, 200, 255), tostring(#DancePartyDJ.Playlist), Color(255, 255, 255), " tracks. Go to the laptop to play!")
        
        return true
    end
end)