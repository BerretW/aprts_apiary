local function getFPS()
    local frameTime = GetFrameTime()
    local frame = 1.0 / frameTime
    return frame
end

function fpsTimer()
    local minFPS = 15
    local maxFPS = 165
    local minSpeed = 0
    local maxSpeed = 15
    local coefficient = 1 - (getFPS() - minFPS) / (maxFPS - minFPS)
    return minSpeed + coefficient * (maxSpeed - minSpeed)
end

-- Funkce pro konverzi hex kódu na RGB (např. "#fc0a03" => 252, 10, 3)
function hexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
end

function DrawTxt(str, x, y, w, h, enableShadow, col1, col2, col3, a, centre)
    local str = CreateVarString(10, "LITERAL_STRING", str)
    SetTextScale(w, h)
    SetTextColor(math.floor(col1), math.floor(col2), math.floor(col3), math.floor(a))
    SetTextCentre(centre)
    if enableShadow then
        SetTextDropshadow(1, 0, 0, 0, 255)
    end
    Citizen.InvokeNative(0xADA9255D, 22)
    DisplayText(str, x, y)
end

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoord())
    local dist = GetDistanceBetweenCoords(px, py, pz, x, y, z, 1)
    local scale = (2 / dist) * 1.1

    local str = CreateVarString(10, "LITERAL_STRING", text, Citizen.ResultAsLong())
    local fov = (2 / GetGameplayCamFov()) * 100
    local scale = scale * fov
    if onScreen then
        SetTextScale(0.18 * scale, 0.18 * scale)
        SetTextFontForCurrentCommand(1)
        SetTextColor(180, 180, 240, 205)
        SetTextCentre(1)
        DisplayText(str, _x, _y)
        local factor = (string.len(text)) / 355
    end
end

function displayData3D(x, y, z, data, showImage, imagePath)
    -- Získání koordinátů na obrazovce a vzdálenosti od kamery
    local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoord())
    local dist = GetDistanceBetweenCoords(px, py, pz, x, y, z, 1)

    -- Pevná škála, která bere v potaz vzdálenost a fov kamery
    local scale = (1 / dist) * 2.0
    local fov = (1 / GetGameplayCamFov()) * 100
    scale = scale * fov

    if onScreen then
        -- Upravíme základní posun na ose Y, aby se prvky pohybovaly správně vzhledem k pozici
        local baseYOffset = -0.03 -- Posun, aby první řádek začal o trochu výše

        -- Projdi jednotlivé položky v `data` tabulce
        for i, row in pairs(data) do
            local yOffset = baseYOffset + (0.03 * (i - 1)) * scale -- Dynamický posun na základě škálování

            -- Zpracuj a vykresli text pro aktuální řádek
            if row.text then
                SetTextScale(0.35 * scale, 0.35 * scale) -- Zvětšíme text dle vzdálenosti
                SetTextFontForCurrentCommand(1)
                local r, g, b = hexToRGB(row.color) -- Konverze hex na RGB
                SetTextColor(r, g, b, 255)
                SetTextCentre(1)
                DisplayText(CreateVarString(10, "LITERAL_STRING", row.text, Citizen.ResultAsLong()), _x, _y + yOffset)
            end

            -- Pokud je definovaná čára (line = true), vykresli ji s procentuální hodnotou (value)
            if row.line and row.value then
                local lineLength = 0.06 * scale -- Délka čáry (přizpůsobená dle měřítka)
                local lineStartX = _x - (lineLength / 2) -- Začátek čáry
                local lineEndX = lineStartX + (lineLength * (row.value / 100)) -- Konec čáry dle procent

                local lineColorR, lineColorG, lineColorB = hexToRGB(row.lineColor or "#ffffff") -- Barva čáry
                local lineWidth = row.lineWidth or 0.005 -- Tloušťka čáry

                -- Vykreslení čáry blíže pod text
                DrawRect(lineStartX + ((lineEndX - lineStartX) / 2), _y + yOffset + (0.015 * scale),
                    (lineEndX - lineStartX), lineWidth * scale, lineColorR, lineColorG, lineColorB, 255)
            end
        end

        -- Vykreslení PNG obrázku, pokud je zapnuto
        if showImage and imagePath then
            DrawSprite(imagePath, "default", _x + 0.05 * scale, _y + 0.02 * scale, 0.05 * scale, 0.05 * scale, 0.0, 255,
                255, 255, 255)
        end
    end
end

local tabulkaData = {
    head = {
        { name = "Název",   key="name", width=5, align="left",  color="#FFD700" },
        { name = "Cena $",  key="cena", width=1, align="center", color={200,200,255} }
    },
    rows = {
        { name = "Prémiové seno",      cena = 15  },
        { name = "Jablečná pochoutka", cena = 5   },
        { name = "Koňský kartáč",      cena = 25  },
        { name = "Nové sedlo",         cena = 150 },
        { name = "Vak na zásoby",      cena = 75  },
    }
}




-- obdélník
local function DrawRectUI(x, y, w, h, color)
    DrawRect(x, y, w, h, color[1], color[2], color[3], color[4] or 255)
end

-- tabulka vycentrovaná podle středu
function DrawTableCentered(data, centerX, centerY, rowHeight, textScale, totalWidth, config)
    if not data or not data.head or not data.rows then return end

    local cfg = config or {}
    local h = rowHeight or 0.03
    local s = textScale or 0.35
    local w = totalWidth or 0.6
    local pad = 0.004

    local cols = #data.head
    if cols == 0 then return end

    local totalRows = #data.rows + 1 -- hlavička + data
    local totalHeight = totalRows * h

    -- počáteční offset podle středu
    local x = centerX - (w * 0.5)
    local y = centerY - (totalHeight * 0.5)

    -- barvy pozadí
    local headBgColor = cfg.headBgColor or {40,40,40,200}
    local rowOddBg    = cfg.rowOddBg    or {30,30,30,150}
    local rowEvenBg   = cfg.rowEvenBg   or {20,20,20,150}

    -- váhy sloupců
    local sumWidth = 0
    for i=1, cols do
        sumWidth = sumWidth + (data.head[i].width or 1)
    end

    -- === HLAVIČKA pozadí ===
    DrawRectUI(x + w*0.5, y + h*0.5, w, h, headBgColor)

    -- === HLAVIČKA text ===
    local colX = x
    for i, head in ipairs(data.head) do
        local colW = w * ((head.width or 1) / sumWidth)
        local cx = colX + colW * 0.5

        local r,g,b = 255,255,0
        if head.color then
            if type(head.color) == "string" then
                r,g,b = hexToRGB(head.color)
            elseif type(head.color) == "table" then
                r,g,b = head.color[1], head.color[2], head.color[3]
            end
        end

        DrawTxt(head.name or "", cx, y, s, s, true, r,g,b,255, true)
        colX = colX + colW
    end

    -- === ŘÁDKY ===
    local rowY = y + h
    for idx, row in ipairs(data.rows) do
        local bg = (idx % 2 == 0) and rowEvenBg or rowOddBg
        DrawRectUI(x + w*0.5, rowY + h*0.5, w, h, bg)

        colX = x
        for j, head in ipairs(data.head) do
            local colW = w * ((head.width or 1) / sumWidth)

            -- získání hodnoty buňky
            local cell = row[j]
            if cell == nil and head.key then cell = row[head.key] end
            if cell == nil and head.name then cell = row[head.name] end
            if cell == nil then cell = "" end

            -- barva textu
            local r,g,b = 255,255,255
            if head.color then
                if type(head.color) == "string" then
                    r,g,b = hexToRGB(head.color)
                elseif type(head.color) == "table" then
                    r,g,b = head.color[1], head.color[2], head.color[3]
                end
            end

            local align = head.align or "left"
            if align == "center" then
                DrawTxt(tostring(cell), colX + colW*0.5, rowY, s, s, false, r,g,b,255, true)
            elseif align == "right" then
                DrawTxt(tostring(cell), colX + colW - pad, rowY, s, s, false, r,g,b,255, false)
            else
                DrawTxt(tostring(cell), colX + pad, rowY, s, s, false, r,g,b,255, false)
            end

            colX = colX + colW
        end
        rowY = rowY + h
    end
end

-- DrawTableCentered(tabulkaData, 0.75, 0.2, 0.035, 0.35, 0.3, {
--     headBgColor = {80, 20, 20, 200},
--     rowOddBg = {40, 40, 40, 150},
--     rowEvenBg = {30, 30, 30, 150}
-- })

function drawMarker(x, y, z)
    Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, 0.3, 0.3, 0.6, 100, 100, 20,
        20.0, 0, 0, 2, 0, 0, 0, 0)
end

function drawMarkerBig(x, y, z)
    Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 0.6, 100, 100, 20,
        20.0, 0, 0, 2, 0, 0, 0, 0)
end

function drawPole(x, y, z, r, g, b)
    if r == nil then
        r = 255
    end
    if g == nil then
        g = 255
    end
    if b == nil then
        b = 255
    end
    Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, x, y, z - 1.0, 0, 0, 0, 0, 0, 0, 0.1, 0.1, 2.0, r, g, b, 100,
        0, 0, 2, 0, 0, 0, 0)
    -- print("Pole placed at " .. x .. ", " .. y .. ", " .. z)
end

-- Citizen.CreateThread(function()
--     while true do
--         local pause = 1000

--         local playerPed = PlayerPedId()
--         local playerPos = GetEntityCoords(playerPed)
--         DrawTxt("In Tar Zone: " .. tostring(IsNearTar()).. ". Has Bucket: " .. tostring(hasBucketInHands()), 0.5, 0.01,
--             0.5, 0.5, true, 255, 255, 255, 255, true)
--         pause = fpsTimer()
--         Citizen.Wait(pause)
--     end
-- end)
