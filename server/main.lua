local QBCore = exports['qb-core']:GetCoreObject()
local OutsideVehicles = {}
local VehicleSpawnerVehicles = {}

local function TableContains (tab, val)
    if type(val) == "table" then
        for _, value in ipairs(tab) do
            if TableContains(val, value) then
                return true
            end
        end
        return false
    else
        for _, value in ipairs(tab) do
            if value == val then
                return true
            end
        end
    end
    return false
end

local function GetVehicles(citizenid, garageName, state, cb)
    local result = nil
    if not Config.GlobalParking then
        result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = @citizenid AND garage = @garage AND state = @state', {
            ['@citizenid'] = citizenid,
            ['@garage'] = garageName,
            ['@state'] = state
        })
    else
        result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = @citizenid AND state = @state', {
            ['@citizenid'] = citizenid,
            ['@state'] = state
        })
    end
    cb(result)
end

local function GetDepotVehicles(citizenid, state, garage, cb)
    local result = MySQL.Sync.fetchAll("SELECT * FROM player_vehicles WHERE citizenid = @citizenid AND (state = @state OR garage = @garage OR garage IS NULL or garage = '')", {
        ['@citizenid'] = citizenid,
        ['@state'] = state,
        ['@garage'] = garage
    })
    cb(result)
end

local function GetVehicleByPlate(plate)
    local vehicles = GetAllVehicles() -- Get all vehicles known to the server
    for _, vehicle in pairs(vehicles) do
        local pl = GetVehicleNumberPlateText(vehicle)
        if pl == plate then
            return vehicle
        end
    end
    return nil
end

QBCore.Functions.CreateCallback("qb-garage:server:GetOutsideVehicle", function(source, cb, plate)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
    if not OutsideVehicles[plate] then cb(nil) return end
     MySQL.query('SELECT * FROM player_vehicles WHERE citizenid = ? and plate = ?', {pData.PlayerData.citizenid, plate}, function(result)
        if result[1] then
            cb(result[1])
        else
            cb(nil)
        end
    end)
end)

lib.callback.register('qb-garage:server:IsVehicleOwned', function(source, plate)
    if OutsideVehicles[plate] then return true end

    MySQL.query('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result[1] then
            return true
        end
    end)

    return false
end)

QBCore.Functions.CreateCallback("qb-garages:server:GetVehicleLocation", function(source, cb, plate)
    local src = source
    local vehicles = GetAllVehicles()
    for _, vehicle in pairs(vehicles) do
        local pl = GetVehicleNumberPlateText(vehicle)
        if pl == plate then
            cb(GetEntityCoords(vehicle))
            return
        end
    end
    local result = MySQL.Sync.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate})
    local veh = result[1]
    if veh then
        if Config.StoreParkinglotAccuratly and veh.parkingspot then
            local location = json.decode(veh.parkingspot)
            cb(vector3(location.x, location.y, location.z))
        else
            local garageName = veh and veh.garage
            local garage = Config.Garages[garageName]
            if garage and garage.blipcoords then
                cb(garage.blipcoords)
            elseif garage and garage.Zone and garage.Zone.Shape and garage.Zone.Shape[1] then
                cb(vector3(garage.Zone.Shape[1].x, garage.Zone.Shape[1].y, garage.Zone.minZ))
            else
                local result = MySQL.query.await('SELECT * FROM houselocations WHERE name = ?', {garageName})
                if result and result[1] then
                    local coords = json.decode(result[1].garage)
                    if coords then
                        cb(vector3(coords.x, coords.y, coords.z))
                    else
                        cb(nil)
                    end
                else
                    cb(nil)
                end
            end
        end
    end
end)

QBCore.Functions.CreateCallback("qb-garage:server:CheckSpawnedVehicle", function(source, cb, plate)
    cb(VehicleSpawnerVehicles[plate] ~= nil and VehicleSpawnerVehicles[plate])
end)

RegisterNetEvent("qb-garage:server:UpdateSpawnedVehicle", function(plate, value)
    VehicleSpawnerVehicles[plate] = value
end)

QBCore.Functions.CreateCallback('qb-garage:server:spawnvehicle', function (source, cb, vehInfo, coords, warp)
    local netID = QBCore.Functions.CreateVehicleServer(source, vehInfo.vehicle, coords, warp)
    local veh = NetworkGetEntityFromNetworkId(netID)

    if not netID or not veh then
        while not netID or not veh do
            if netID then
                veh = NetworkGetEntityFromNetworkId(netID)
            end
            Wait(0)
        end
    end

    local vehProps = {}
    local plate = vehInfo.plate

    local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})
    if result[1] then vehProps = json.decode(result[1].mods) end

    OutsideVehicles[plate] = {netID = netID, entity = veh}
    cb(netID, vehProps)
end)

QBCore.Functions.CreateCallback("qb-garage:server:GetGarageVehicles", function(source, cb, garage, garageType, category)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
    local playerGang = pData.PlayerData.gang.name;

    if garageType == "public" then        --Public garages give player cars in the garage only
        GetVehicles(pData.PlayerData.citizenid, garage, 1, function(result)
            local vehs = {}
            if result[1] then
                for _, vehicle in pairs(result) do
                    if vehicle.parkingspot then
                        local spot = json.decode(vehicle.parkingspot)
                        if spot and spot.x then
                            vehicle.parkingspot = vector3(spot.x, spot.y, spot.z)
                        end
                    end
                    if vehicle.damage then
                        vehicle.damage = json.decode(vehicle.damage)
                    end
                    vehs[#vehs + 1] = vehicle
                end
                cb(vehs)
            else
                cb(nil)
            end
        end)
    elseif garageType == "depot" then    --Depot give player cars that are not in garage only
        GetDepotVehicles(pData.PlayerData.citizenid, 0, garage, function(result)
            local tosend = {}
            if result[1] then
                if type(category) == 'table' then
                    if TableContains(category, {'car'}) then
                        category = 'car'
                    elseif TableContains(category, {'plane', 'helicopter'}) then
                        category = 'air'
                    elseif TableContains(category, 'boat') then
                        category = 'sea'
                    end
                end
                for _, vehicle in pairs(result) do
                    if GetVehicleByPlate(vehicle.plate) or not QBCore.Shared.Vehicles[vehicle.vehicle] then
                        goto skip
                    end
                    if vehicle.depotprice == 0 then
                        vehicle.depotprice = Config.DepotPrice
                    end

                    vehicle.parkingspot = nil
                    if vehicle.damage then
                        vehicle.damage = json.decode(vehicle.damage)
                    end

                    if category == "air" and ( QBCore.Shared.Vehicles[vehicle.vehicle].category == "helicopters" or QBCore.Shared.Vehicles[vehicle.vehicle].category == "planes" ) then
                        tosend[#tosend + 1] = vehicle
                    elseif category == "sea" and QBCore.Shared.Vehicles[vehicle.vehicle].category == "boats" then
                        tosend[#tosend + 1] = vehicle
                    elseif category == "car" and QBCore.Shared.Vehicles[vehicle.vehicle].category ~= "helicopters" and QBCore.Shared.Vehicles[vehicle.vehicle].category ~= "planes" and QBCore.Shared.Vehicles[vehicle.vehicle].category ~= "boats" then
                        tosend[#tosend + 1] = vehicle
                    end
                    ::skip::
                end
                cb(tosend)
            else
                cb(nil)
            end
        end)
    else                            --House give all cars in the garage, Job and Gang depend of config
        local shared = ''
        if not TableContains(Config.SharedJobGarages, garage) and not (Config.SharedHouseGarage and garageType == "house") and not ((Config.SharedGangGarages == true or (type(Config.SharedGangGarages) == "table" and Config.SharedGangGarages[playerGang])) and garageType == "gang") then
            shared = " AND citizenid = '"..pData.PlayerData.citizenid.."'"
        end
         MySQL.query('SELECT * FROM player_vehicles WHERE garage = ? AND state = ?'..shared, {garage, 1}, function(result)
            if result[1] then
                local vehs = {}
                for _, vehicle in pairs(result) do
                    local spot = json.decode(vehicle.parkingspot)
                    if vehicle.parkingspot then
                        vehicle.parkingspot = vector3(spot.x, spot.y, spot.z)
                    end
                    if vehicle.damage then
                        vehicle.damage = json.decode(vehicle.damage)
                    end
                    vehs[#vehs + 1] = vehicle
                end
                cb(vehs)
            else
                cb(nil)
            end
        end)
    end
end)

QBCore.Functions.CreateCallback("qb-garage:server:checkOwnership", function(source, cb, plate, garageType, garage, gang)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
    if garageType == "public" then        --Public garages only for player cars
        local addSQLForAllowParkingAnyonesVehicle = ""
        if not Config.AllowParkingAnyonesVehicle then
            addSQLForAllowParkingAnyonesVehicle = " AND citizenid = '"..pData.PlayerData.citizenid.."' "
        end
         MySQL.query('SELECT * FROM player_vehicles WHERE plate = ? ' .. addSQLForAllowParkingAnyonesVehicle,{plate}, function(result)
            if result[1] then
                cb(true)
            else
                cb(false)
            end
        end)
    elseif garageType == "house" then     --House garages only for player cars that have keys of the house
         MySQL.query('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
            if result[1] then
                cb(true)
            else
                cb(false)
            end
        end)
    elseif garageType == "gang" then        --Gang garages only for gang members cars (for sharing)
         MySQL.query('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
            if result[1] then
                --Check if found owner is part of the gang
                local Player = QBCore.Functions.GetPlayer(source)
                local playerGang = Player.PlayerData.gang.name
                cb(playerGang == gang)
            else
                cb(false)
            end
        end)
    else                            --Job garages only for cars that are owned by someone (for sharing and service) or only by player depending of config
        local shared = ''
        if not TableContains(Config.SharedJobGarages, garage) then
            shared = " AND citizenid = '"..pData.PlayerData.citizenid.."'"
        end
         MySQL.query('SELECT * FROM player_vehicles WHERE plate = ?'..shared, {plate}, function(result)
            if result[1] then
                cb(true)
            else
                cb(false)
            end
        end)
    end
end)

QBCore.Functions.CreateCallback("qb-garage:server:GetVehicleProperties", function(source, cb, plate)
    local properties = {}
    local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})
    if result[1] then
        properties = json.decode(result[1].mods)
    end
    cb(properties)
end)

RegisterNetEvent('qb-garage:server:updateVehicle', function(state, fuel, engine, body, properties, plate, garage, location, damage)
    if location and type(location) == 'vector3' then
        if Config.StoreDamageAccuratly then
            MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ?, parkingspot = ?, damage = ? WHERE plate = ?',{state, garage, fuel, engine, body, json.encode(properties), json.encode(location), json.encode(damage), plate})
        else
            local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})
            local propertiesNew = properties
            if result[1] then
                propertiesNew = json.decode(result[1].mods)
                if properties.doorStatus then
                    propertiesNew.doorStatus = properties.doorStatus
                end
                if properties.tireHealth then
                    propertiesNew.tireHealth = properties.tireHealth
                end
                if properties.oilLevel then
                    propertiesNew.oilLevel = properties.oilLevel
                end
                if properties.bodyHealth then
                    propertiesNew.bodyHealth = properties.bodyHealth
                end
                if properties.tireBurstCompletely then
                    propertiesNew.tireBurstCompletely = properties.tireBurstCompletely
                end
                if properties.windowStatus then
                    propertiesNew.windowStatus = properties.windowStatus
                end
                if properties.tankHealth then
                    propertiesNew.tankHealth = properties.tankHealth
                end
                if properties.tireBurstState then
                    propertiesNew.tireBurstState = properties.tireBurstState
                end
                if properties.dirtLevel then
                    propertiesNew.dirtLevel = properties.dirtLevel
                end
            end
            MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ?, parkingspot = ? WHERE plate = ?',{state, garage, fuel, engine, body, json.encode(propertiesNew), json.encode(location), plate})
        end
    else
        if Config.StoreDamageAccuratly then
            MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ?, damage = ? WHERE plate = ?',{state, garage, fuel, engine, body, json.encode(properties), json.encode(damage), plate})
        else
            local result = MySQL.query.await('SELECT mods FROM player_vehicles WHERE plate = ?', {plate})
            local propertiesNew = properties
            if result[1] then
                propertiesNew = json.decode(result[1].mods)
                if properties.doorStatus then
                    propertiesNew.doorStatus = properties.doorStatus
                end
                if properties.tireHealth then
                    propertiesNew.tireHealth = properties.tireHealth
                end
                if properties.oilLevel then
                    propertiesNew.oilLevel = properties.oilLevel
                end
                if properties.bodyHealth then
                    propertiesNew.bodyHealth = properties.bodyHealth
                end
                if properties.tireBurstCompletely then
                    propertiesNew.tireBurstCompletely = properties.tireBurstCompletely
                end
                if properties.windowStatus then
                    propertiesNew.windowStatus = properties.windowStatus
                end
                if properties.tankHealth then
                    propertiesNew.tankHealth = properties.tankHealth
                end
                if properties.tireBurstState then
                    propertiesNew.tireBurstState = properties.tireBurstState
                end
                if properties.dirtLevel then
                    propertiesNew.dirtLevel = properties.dirtLevel
                end
            end
            MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, fuel = ?, engine = ?, body = ?, mods = ? WHERE plate = ?', {state, garage, fuel, engine, body, json.encode(propertiesNew), plate})
        end
    end
end)

RegisterNetEvent('qb-garage:server:updateVehicleState', function(state, plate, garage)
    MySQL.update('UPDATE player_vehicles SET state = ?, garage = ?, depotprice = ? WHERE plate = ?',{state, garage, 0, plate})
end)

RegisterNetEvent('qb-garages:server:UpdateOutsideVehicles', function(Vehicles)
    local src = source
    local ply = QBCore.Functions.GetPlayer(src)
    local citizenId = ply.PlayerData.citizenid
    OutsideVehicles[citizenId] = Vehicles
end)

QBCore.Functions.CreateCallback("qb-garage:server:GetOutsideVehicles", function(source, cb)
    local ply = QBCore.Functions.GetPlayer(source)
    local citizenId = ply.PlayerData.citizenid
    if OutsideVehicles[citizenId] and next(OutsideVehicles[citizenId]) then
        cb(OutsideVehicles[citizenId])
    else
        cb({})
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        Wait(100)
        if Config.AutoRespawn then
            MySQL.update('UPDATE player_vehicles SET state = 1 WHERE state = 0', {})
        end
    end
end)

RegisterNetEvent('qb-garage:server:PayDepotPrice', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local cashBalance = Player.PlayerData.money["cash"]
    local bankBalance = Player.PlayerData.money["bank"]


    local vehicle = data.vehicle

     MySQL.query('SELECT * FROM player_vehicles WHERE plate = ?', {vehicle.plate}, function(result)
        if result[1] then
            local vehicle = result[1]
            local depotPrice = vehicle.depotprice ~= 0 and vehicle.depotprice or Config.DepotPrice
            if cashBalance >= depotPrice then
                Player.Functions.RemoveMoney("cash", depotPrice, "paid-depot")
            elseif bankBalance >= depotPrice then
                Player.Functions.RemoveMoney("bank", depotPrice, "paid-depot")
            else
                TriggerClientEvent('QBCore:Notify', src, Lang:t("error.not_enough"), 'error')
            end
        end
    end)
end)

RegisterNetEvent('qb-garages:server:parkVehicle', function(plate)
    local vehicle = GetVehicleByPlate(plate)
    if vehicle then
        Entity(vehicle).state:set('ServerVehicle', false, true)
        Wait(100)
        DeleteEntity(vehicle)
    end
end)

--External Calls
--Call from qb-vehiclesales
QBCore.Functions.CreateCallback("qb-garage:server:checkVehicleOwner", function(source, cb, plate)
    local src = source
    local pData = QBCore.Functions.GetPlayer(src)
     MySQL.query('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?',{plate, pData.PlayerData.citizenid}, function(result)
        if result[1] then
            cb(true, result[1].balance)
        else
            cb(false)
        end
    end)
end)

--Call from qb-phone
QBCore.Functions.CreateCallback('qb-garage:server:GetPlayerVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local Vehicles = {}

     MySQL.query('SELECT * FROM player_vehicles WHERE citizenid = ?', {Player.PlayerData.citizenid}, function(result)
        if result[1] then
            for k, v in pairs(result) do
                local VehicleData = QBCore.Shared.Vehicles[v.vehicle]
                if not VehicleData then goto continue end
                local VehicleGarage = Lang:t("error.no_garage")
                if v.garage ~= nil then
                    if Config.Garages[v.garage] ~= nil then
                        VehicleGarage = Config.Garages[v.garage].label
                    elseif Config.HouseGarages[v.garage] then
                        VehicleGarage = Config.HouseGarages[v.garage].label
                    end
                end

                if v.state == 0 then
                    v.state = Lang:t("status.out")
                elseif v.state == 1 then
                    v.state = Lang:t("status.garaged")
                elseif v.state == 2 then
                    v.state = Lang:t("status.impound")
                end

                local fullname
                if VehicleData["brand"] ~= nil then
                    fullname = VehicleData["brand"] .. " " .. VehicleData["name"]
                else
                    fullname = VehicleData["name"]
                end
                local spot = json.decode(v.parkingspot)
                Vehicles[#Vehicles+1] = {
                    fullname = fullname,
                    brand = VehicleData["brand"],
                    model = VehicleData["name"],
                    plate = v.plate,
                    garage = VehicleGarage,
                    state = v.state,
                    fuel = v.fuel,
                    engine = v.engine,
                    body = v.body,
                    parkingspot = spot and vector3(spot.x, spot.y, spot.z) or nil,
                    damage = json.decode(v.damage)
                }
                ::continue::
            end
            cb(Vehicles)
        else
            cb(nil)
        end
    end)
end)

local function GetRandomPublicGarage()
    for garageName, garage in pairs(Config.Garages)do
        if garage.type == 'public' then
            return garageName -- return the first garageName
        end
    end
end

-- Command to restore lost cars (garage: 'None' or something similar)
QBCore.Commands.Add("restorelostcars", "Restores cars that were parked in a grage that no longer exists in the config or is invalid (name change or removed).", {{name = "destination_garage", help = "(Optional) Garage where the cars are being sent to."}}, false,
function(source, args)
    local src = source
    if next(Config.Garages) ~= nil then
        local destinationGarage = args[1] and args[1] or GetRandomPublicGarage()
        if Config.Garages[destinationGarage] == nil then
            TriggerClientEvent('QBCore:Notify', src, 'Invalid garage name provided', 'error', 4500)
            return
        end

        local invalidGarages = {}
         MySQL.query('SELECT garage FROM player_vehicles', function(result)
            if result[1] then
                for _,v in ipairs(result) do
                    if Config.Garages[v.garage] == nil then
                        if v.garage then
                            invalidGarages[v.garage] = true
                        end
                    end
                end
                for garage,_ in pairs(invalidGarages) do
                    MySQL.update('UPDATE player_vehicles set garage = ? WHERE garage = ?',{destinationGarage, garage})
                end
                MySQL.update('UPDATE player_vehicles set garage = ? WHERE garage IS NULL OR garage = \'\'',{destinationGarage})
            end
        end)
    end
end, Config.RestoreCommandPermissionLevel)

if Config.EnableTrackVehicleByPlateCommand then
    QBCore.Commands.Add(Config.TrackVehicleByPlateCommand, 'Track vehicle', {{name='plate', help='Plate'}}, true, function(source, args)
    TriggerClientEvent('qb-garages:client:TrackVehicleByPlate', source, args[1])
    end, Config.TrackVehicleByPlateCommandPermissionLevel)
end

AddEventHandler('entityRemoved', function (entity)
    if GetEntityType(entity) == 2 then
        if Entity(entity).state.ServerVehicle then
            local plate = GetVehicleNumberPlateText(entity)
            local coords = GetEntityCoords(entity)
            local model = GetEntityModel(entity)
            local script = GetEntityScript(entity)
            local type = GetVehicleType(entity)
            local owner = NetworkGetEntityOwner(entity)
            local fOwner = NetworkGetFirstEntityOwner(entity)
            local bucket = GetEntityRoutingBucket(entity)

            if owner ~= -1 then
                local ping = GetPlayerPing(owner)
                local Player = QBCore.Functions.GetPlayer(owner).PlayerData
                local pName = Player.charinfo.firstname .. ' ' .. Player.charinfo.lastname
                local CitizenID = Player.citizenid

                local discord,playerip = '',''

                for k,v in ipairs(GetPlayerIdentifiers(owner)) do
                    if string.sub(v, 1, string.len("discord:")) == "discord:" then
                        discord = string.sub(v, string.len("discord:") + 1)
                    elseif string.sub(v, 1, string.len("ip:")) == "ip:" then
                        playerip = string.sub(v, string.len("ip:") + 1)
                    end
                end


                local discord1,playerip1 = '',''

                if not discord          then discord1          = "N/A" else discord1          = discord          end
                if not playerip         then playerip1         = "N/A" else playerip1         = playerip         end

                local connect = {
                    {
                        ["color"] = "000000",
                        ["title"] = "Veículo Deletado Indevidamente",
                        ["description"] = "\n**ID: **"..owner.."\n**Nome: **"..pName.."\n**CSN: **"..CitizenID.."\n**Ping: **"..ping.."ms\n** Discord: **"..discord1.."\n**IP:** "..playerip1.."\n\n **Placa:** "..plate.."\n**Script:** "..script.."\n**Coords:** "..coords.."\n**Modelo:** "..model.."\n**Tipo:** "..type.."\n**Bucket:** "..bucket.."\n**Primeiro Dono:** "..fOwner,
                        ["footer"] = {
                            text = "4Life RP",
                            icon_url = "https://i.imgflip.com/185a81.jpg"
                        },
                        ["timestamp"] = os.date('!%Y-%m-%dT%H:%M:%S'),
                        ["author"] = {
                            name = "4Life RP",
                            icon_url = "https://i.imgflip.com/185a81.jpg"
                        },
                    },
                }
                PerformHttpRequest('https://discord.com/api/webhooks/1111705050100809738/H5nZfBoDhCDSPCkPAkl-Mi-Tx0zYdvU4DUGSq43oJaPr-lSbEYd2NJrd8boRxEHExifT', function(err, text, headers) end, 'POST', json.encode({username = "4Life RP", content = "", embeds = connect}), { ['Content-Type'] = 'application/json' })
            else
                local connect = {
                    {
                        ["color"] = "FFFFFF",
                        ["title"] = "Veículo Deletado Indevidamente",
                        ["description"] = "**Placa:** "..plate.."\n**Script:** "..script.."\n**Coords:** "..coords.."\n**Modelo:** "..model.."\n**Tipo:** "..type.."\n**Bucket:** "..bucket.."\n**Primeiro Dono:** "..fOwner,
                        ["footer"] = {
                            text = "4Life RP",
                            icon_url = "https://i.imgflip.com/185a81.jpg"
                        },
                        ["timestamp"] = os.date('!%Y-%m-%dT%H:%M:%S'),
                        ["author"] = {
                            name = "4Life RP",
                            icon_url = "https://i.imgflip.com/185a81.jpg"
                        },
                    },
                }
                PerformHttpRequest('https://discord.com/api/webhooks/1111705050100809738/H5nZfBoDhCDSPCkPAkl-Mi-Tx0zYdvU4DUGSq43oJaPr-lSbEYd2NJrd8boRxEHExifT', function(err, text, headers) end, 'POST', json.encode({username = "4Life RP", content = "", embeds = connect}), { ['Content-Type'] = 'application/json' })
            end

            Entity(entity).state:set('ServerVehicle', false, true)
            Wait(100)
            if DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
        end
    end
end)

lib.callback.register('guedes-garages:server:isVehicleSpawned', function(source, plate)
    if OutsideVehicles[plate] or VehicleSpawnerVehicles[plate] then
        return true
    end
end)

exports('CheckVehicleIsOwned', function(plate)
    return OutsideVehicles[plate]
end)

CreateThread(function ()
    while true do
        local houses = exports['qs-housing']:GetHouses()
        local housesNames = {}
        local housesOwners = {}

        for key, value in pairs(houses) do
            local houseName = 'house '..key

            if value?.keys and value?.keys[1] then
                housesOwners[houseName] = value.keys
            else
                housesOwners[houseName] = value.identifier
            end

            table.insert(housesNames, houseName)
        end

        local housesVehicles = MySQL.query.await("SELECT * FROM player_vehicles WHERE garage LIKE 'house %%'")
        for key, value in pairs(housesVehicles) do
            if type(housesOwners[value.garage]) == 'table' then
                if not lib.table.contains(housesOwners[value.garage], value.citizenid) then
                    MySQL.update("UPDATE player_vehicles SET garage = ? WHERE citizenid = ? and garage = ?", {'pillboxgarage', value.citizenid, value.garage})
                end
            else
                if housesOwners[value.garage] ~= value.citizenid then
                    MySQL.update("UPDATE player_vehicles SET garage = ? WHERE citizenid = ? and garage = ?", {'pillboxgarage', value.citizenid, value.garage})
                end
            end
        end

        MySQL.update("UPDATE player_vehicles SET garage = ? WHERE garage LIKE 'house %%' AND garage NOT IN ('" .. table.concat(housesNames, "', '") .. "')", {'pillboxgarage'})

        Wait(20000)
    end
end)