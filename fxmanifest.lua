fx_version 'cerulean'
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'
author 'SpoiledMouse'
version '1.0'
name 'aprts_apiary'
description 'Pokročilý systém včelařství'

shared_script 'config.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- Načtení knihovny pro SQL
    'server/Genetics.lua',
    'server/main.lua'
}

client_scripts {
    'client/main.lua'
}

dependency 'vorp_core'
dependency 'vorp_inventory'