MySQL = exports.oxmysql
Core = exports.vorp_core:GetCore()
Apiaries = {}
Hives = {}
Queens = {}
Bees = {}
QueensByUID = QueensByUID or {}
QueensByHive = QueensByHive or {}
function debugPrint(msg)
    if Config.Debug == true then
        print("^1[APIARY]^0 " .. msg)
    end
end
function Notify(playerId, message)
    TriggerClientEvent('notifications:notify', playerId, "APIARY", message, 4000)
end

function table.count(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function hasJob(player, jobtable)
    local pjob = Player(player).state.Character.Job
    local pGrade = Player(player).state.Character.Grade
    local pLabel = Player(player).state.Character.Label
    for _, v in pairs(jobtable) do
        if v.job == pjob and v.grade <= pGrade and (v.label == "" or v.label == nil or v.label == pLabel) then
            return true
        end
    end
    return false
end

function round(num)
    return math.floor(num * 100 + 0.5) / 100
end

function GetPlayerName(source)
    local user = Core.getUser(source)
    if not user then
        return "nobody"
    end
    local character = user.getUsedCharacter
    local firstname = character.firstname
    local lastname = character.lastname
    return firstname .. " " .. lastname
end

function getTimeStamp()
    local time = 0
    MySQL:execute("SELECT NOW() as time", {}, function(result)
        if result then
            time = result[1].time
        end
    end)
    while time == 0 do
        Wait(100)
    end
    return time
end

function unixToDateTime(unixTime)
    return os.date('%Y-%m-%d %H:%M:%S', unixTime)
end

function DiscordWeb(name, message, footer)
    if Config.WebHook == "" then
        return
    end
    local embed = {{
        ["color"] = Config.DiscordColor,
        ["title"] = "",
        ["description"] = "**" .. name .. "** \n" .. message .. "\n\n",
        ["footer"] = {
            ["text"] = footer
        }
    }}
    PerformHttpRequest(Config.WebHook, function(err, text, headers)
    end, 'POST', json.encode({
        username = Config.ServerName,
        embeds = embed
    }), {
        ['Content-Type'] = 'application/json'
    })
end

function LokiLog(event, player, playerName, message, ...)

    local text = Player(player).state.Character.CharId .. "/" .. playerName .. ": " .. message
    lib.logger(player, event, text, ...)

end

function LOG(player, event, message, ...)
    local playerName = GetPlayerName(player)
    local charID = 0
    if Player(player) and Player(player).state and Player(player).state.Character and
        Player(player).state.Character.CharId then
        charID = Player(player).state.Character.CharId
    end
    local text = charID .. "/" .. playerName .. ": " .. message
    if Config.Debug == true then
        print("^1[" .. event .. "]^0 " .. text .. "\n")
    end
    DiscordWeb(event .. ", " .. playerName, message, os.date("Datum: %d.%m.%Y Čas: %H:%M:%S"))
    lib.logger(player, event, text, ...)

end

function GetIdentifier(source)
    local chadID = Player(source).state.Character.CharId
    return chadID
end
