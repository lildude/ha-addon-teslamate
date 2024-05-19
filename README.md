# Home Assistant Add-on: TeslaMate

A self-hosted data logger for your Tesla 🚘

## About

[TeslaMate][teslamate] is a powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir][elixir]**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

This addon allows you to run [TeslaMate][teslamate] on your Home Assistant server based on the the official TeslaMate [docker image][docker].

[![Sponsor me to maintain this addon][sponsor-badge]](https://github.com/sponsors/lildude)

![TeslaMate Version][teslamate-version]
![Ingress][ingres-badge]
![Supported Architectures][archs]

## Requirements

TeslaMate needs a PostgreSQL database.
All development and testing has been done using [PostgreSQL add-on][postgres] for convenience but you're welcome to use your own.

For convenience, my [add-ons repository][addons-repo] includes configuration that points to the [PostgreSQL add-on][postgres] so you can install everything from one repo.

To get the full experience, it is recommended that you also install the community [Grafana add-on][grafana-addon] and [MQTT integration][mqtt].

## Installation

1. Add my [add-ons repository][addons-repo] to Home Assistant or click the button below to open my add-on repository on your Home Assistant instance.

   [![Open add-on repo on your Home Assistant instance][repo-btn]][addon]

1. Install this add-on.
1. Install the PostgreSQL add-on and configure and start it, if you wish to use this add-on.
1. Configure Grafana as detailed in this addon's documentation.
1. Enter your PostgreSQL configuration information.
1. Enter your Grafana configuration information.
1. Enter your MQTT configuration information.
1. Click the `Save` button to store your configuration.
1. Start the add-on.
1. Check the logs of the add-on to see if everything went well.
1. Click the `OPEN WEB UI` button to open TeslaMate.

[addon]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Flildude%2Fha-addons
[addons-repo]: https://github.com/lildude/ha-addons
[archs]: https://img.shields.io/badge/dynamic/json?color=green&label=Arch&query=%24.arch&url=https%3A%2F%2Fraw.githubusercontent.com%2Flildude%2Fha-addon-teslamate%2Fmain%2Fconfig.json
[docker]: https://hub.docker.com/r/teslamate/teslamate
[elixir]: https://elixir-lang.org/
[grafana-addon]: https://github.com/hassio-addons/addon-grafana
[ingres-badge]: https://img.shields.io/badge/dynamic/json?label=Ingress&query=%24.ingress&url=https%3A%2F%2Fraw.githubusercontent.com%2Flildude%2Fha-addon-teslamate%2Fmain%2Fconfig.json
[mqtt]: https://www.home-assistant.io/integrations/mqtt
[postgres]: https://github.com/matt-FFFFFF/hassio-addon-postgres
[repo-btn]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[sponsor-badge]: https://img.shields.io/badge/Sponsor_Me-%E2%9D%A4-ec6cb9?logo=GitHub
[teslamate-version]: https://img.shields.io/badge/dynamic/json?label=TeslaMate%20Version&url=https%3A%2F%2Fraw.githubusercontent.com%2Flildude%2Fha-addon-teslamate%2Fmain%2Fbuild.json&query=%24.args.teslamate_version
[teslamate]: https://github.com/teslamate-org/teslamate/
