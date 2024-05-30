# Home Assistant Add-on: TeslaMate

A self-hosted data logger for your Tesla 🚘

## About

[TeslaMate][teslamate] is a powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir][elixir]**
- Data is stored in a **Postgres** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

This add-on allows you to run [TeslaMate][teslamate] on your Home Assistant server based on the the official TeslaMate [docker image][docker].

This add-on is a fork of the unmaintained add-on at <https://github.com/matt-FFFFFF/hassio-addon-teslamate>.
Thanks to @matt-FFFFFF for maintaining this add-on in the past.

[![Sponsor me to maintain this add-on][sponsor-badge]](https://github.com/sponsors/lildude)

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
1. Install the PostgreSQL add-on and configure and start it, if you wish to use this add-on. The database name isn't important here as the TeslaMate add-on will create the database you name in the settings if it doesn't exist.
1. Configure Grafana as detailed in this add-on's documentation.
1. Enter your PostgreSQL configuration information.
1. Enter your Grafana configuration information.
1. Enter your MQTT configuration information.
1. Click the `Save` button to store your configuration.
1. Start the add-on.
1. Check the logs of the add-on to see if everything went well.
1. Click the `OPEN WEB UI` button to open TeslaMate.

## Migrating to this version of the add-on

Migrating to this version of the add-on should not result in any loss of data, but you can never be too careful, so I recommend you take a full backup of your Home Assistant instance and also a direct backup of the TeslaMate database as detailed in the [TeslaMate documentation][teslamate-backup] before proceeding.

To migrate:

1. Install this version of the TeslaMate add-on as per the details above. Keep your current version installed for now.
1. Open the old add-on configuration options.
1. Click the three dots at the top and select "Edit in YAML".
1. Highlight and copy all the options.
1. Open this add-on's configuration options.
1. Click the three dots at the top and select "Edit in YAML".
1. Replace all content with the configuration copied above.
1. Stop the old add-on.
1. Start the new add-on.
1. Verify everything is working as before and uninstall the old add-on.

Everything should pick up where it was before.

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
[teslamate-backup]: https://docs.teslamate.org/docs/maintenance/backup_restore
[teslamate-version]: https://img.shields.io/badge/dynamic/json?label=TeslaMate%20Version&url=https%3A%2F%2Fraw.githubusercontent.com%2Flildude%2Fha-addon-teslamate%2Fmain%2Fbuild.json&query=%24.args.teslamate_version
[teslamate]: https://github.com/teslamate-org/teslamate/
