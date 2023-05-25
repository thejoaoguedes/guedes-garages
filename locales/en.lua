local Translations = {
    error = {
        no_vehicles = "Não há veículos estacionados nesse lugar!",
        not_impound = "Seu veículo não está no impound!",
        not_owned = "Esse veículo não pode ser estacionado!",
        not_correct_type = "Esse tipo de veículo não pode ser estacionado aqui!",
        not_enough = "Você não tem dinheiro suficiente.",
        no_garage = "N/A",
        too_far_away = "Você está muito longe da vaga!",
        occupied = "Essa vaga já está ocupada!",
        all_occupied = "Todas as vagas estão ocupadas!",
        no_vehicle = "Não há veículo para estacionar.",
        no_house_keys = "Você não tem as chaves dessa casa!",
    },
    success = {
        vehicle_parked = "Veículo estacionado com sucesso!",
    },
    menu = {
        header = {
            house_garage = "**Garagem Pessoal**",
            house_car = "**Garagem Pessoal**  \n *%{value}*",
            public_car = "**Garagem Pública**  \n *%{value}*",
            public_sea = "**Marina Pública**  \n *%{value}*",
            public_air = "**Hangar Público**  \n *%{value}*",
            job_car = "**Garagem de Trabalho**  \n *%{value}*",
            job_sea = "**Marina de Trabalho**  \n *%{value}*",
            job_air = "**Hangar de Trabalho**  \n *%{value}*",
            gang_car = "**Garagem de Gangue**  \n *%{value}*",
            gang_sea = "**Marina de Gangue**  \n *%{value}*",
            gang_air = "**Hangar de Gangue**  \n *%{value}*",
            depot_car = "**Apreendido**  \n *%{value}*",
            depot_sea = "**Apreendido**  \n *%{value}*",
            depot_air = "**Apreendido**  \n *%{value}*",
            vehicles = "Veículos Disponíveis",
            depot = "%{value} [ $%{value2} ]",
            garage = "%{value} [ %{value2} ]",
        },
        leave = {
            car = "Sair",
            sea = "Sair",
            air = "Sair",
            job = "Sair"
        },
        text = {
            vehicles = "Veículos",
            vehicles2 = "Veja os veículos estacionados!",
            depot = "Placa: %{value} \n Combustível: %{value2} | Motor: %{value3} | Lataria: %{value4}",
            garage = "Estado: %{value} \n Combustível: %{value2} | Motor: %{value3} | Lataria: %{value4}",
        }
    },
    status = {
        out = "Fora",
        garaged = "Estacionado",
        impound = "Apreendido",
    },
}

Lang = Lang or Locale:new({
    phrases = Translations,
    warnOnMissing = true
})
