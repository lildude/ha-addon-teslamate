# Home Assistant Add-on: TeslaMate

A self-hosted data logger for your Tesla 🚘

## About

[TeslaMate][teslamate] is a powerful, self-hosted data logger for your Tesla.

- Written in **[Elixir][elixir]**
- Data is stored in a **PostgreSQL** database
- Visualization and data analysis with **Grafana**
- Vehicle data is published to a local **MQTT** Broker

This add-on allows you to run [TeslaMate][teslamate] on your Home Assistant server based on the the official TeslaMate [docker image][docker].

## Configuration

The configuration is self-explanatory, but essentially we need details about accessing the PostgreSQL database, Grafana and optionally MQTT.
You will also need to configure TeslaMate (see "TeslaMate Configuration" below) so the links to TeslaMate in the Grafana dashboards work.

### Options

Remember to restart the add-on when the configuration is changed.

#### Database Options

- `database_user`: The username used to connect to your PostgreSQL server.

- `database_pass`: The password for the user to connect to your PostgreSQL server.

- `database_port`: The port your PostgreSQL server is listening on. Default: `5432`.

- `database_host`: The hostname of your PostgreSQL server.

- `database_name`: The name of the PostgreSQL database. Default: `teslamate`.

- `database_ssl`: Use SSL to connect to the database.

#### MQTT Options (Optional)

If you are going to use MQTT, you **must** have a username and password defined for your MQTT user; do not use the HA local login (thanks [quach128](https://github.com/quach128)).

You must also specify an access control list entry for the teslamate user, for example:

```text
user teslamate
topic readwrite teslamate/#
```

See the [official docs][mosquitto-docs] on how to configure access control with Mosquitto

- `disable_mqtt`: Disable MQTT?

- `mqtt_host`: The hostname of your MQTT server.

- `mqtt_user`: The username used to connect to your MQTT server.

- `mqtt_pass`: The password for the user to connect to your PostgreSQL server.

- `mqtt_tls`: Use TLS to connect to MQTT?

- `mqtt_tls_accept_invalid_certs`: MQTT TLS Accepts invalid certificates

- `mqtt_namespace`: MQTT Namespace

#### Grafana Options

I recommend you use the existing [Grafana add-on][grafana-addon] from the community add-ons, if you do, please enable the following plugins in your yaml configurations, e.g.

```yaml
plugins:
  - natel-discrete-panel
  - natel-plotly-panel
  - pr0ps-trackmap-panel
  - grafana-piechart-panel
custom_plugins:
  - name: panodata-map-panel
    url: https://github.com/panodata/panodata-map-panel/releases/download/0.16.0/panodata-map-panel-0.16.0.zip
    unsigned: true
env_vars:
  - name: GF_SECURITY_ADMIN_USER
    value: <youruser>
  - name: GF_SECURITY_ADMIN_PASSWORD
    value: <yourpass>
ssl: true                 # optional if you are using TLS
certfile: fullchain.pem    # optional if you are using TLS
keyfile: privkey.pem       # optional if you are using TLS
```

_Note_ that the security admin password and usernames can only be set on the first start of the Grafana add-on, so if you already have it configured you'll need to use the same details or remove the add-on and re-add it.

- `grafana_import_dashboards`: (Optional, but recommended) Automatically import the grafana dashboards on startup?

- `grafana_folder_name`: Folder within Grafana to store all the dashboards. Default: `TeslaMate`.

- `grafana_host`: The hostname of your Grafana server. Default: `a0d7b954-grafana`.

- `grafana_port`: The port your Grafana server is listening on. Default: `3000`.

- `grafana_user`: The username used to connect to your Grafana server.

- `grafana_pass`: The password for the user to connect to your Grafana server.

- `timezone`: Timezone to use for Granafa dashboards.

Once you have Grafana up and running, you'll need to configure a data source to read data from the PostgreSQL database:

‼️ **Note**: The name must be `TeslaMate` as all the dashboards expect the datasource to use this name.

![Grafana PostgreSQL data source][grafana-datasource]

#### Other Options

- `default_geofence`: (Optional) The default geofence to send via `GEOFENCE` if the car is not in a geofence.

- `encryption_key`: (Optional) A random string used as encrypt and protect the Tesla API keys. This will be auto-generated on first run if not set.

- `import_dir`: (Optional) The path to the directory where TeslaMate should look for the TeslaMate export CSV file. Default: `/share/teslamate`.

- `env_vars`: (Optional) Set additional environment variables for TeslaMate which aren't currently exposed by the configuration options in this add-on.

  Each entry is made up of a name and value:

  - `name`: The case-sensitive environment variable name.
  - `value`: The value to be set in the environment variable.

  Note: These will also overwrite any environment variable set using the configuration options above.

## TeslaMate Configuration

In order for the links in the Grafana dashboards and the TeslaMate UI to link to the correct locations, you will also need to configure TeslaMate.
Once you have started the add-on, look at the log output for the section which looks like this and take note of the two lines with `=>`:

```
[09:26:32] INFO: Configure TeslaMate settings by adding these values
                 to the URL you use to access your Home Assistant instance:

  => Web App: /api/hassio_ingress/ljiIc6sOVGOSQfTRjscvLVJJS5Rxp33gsdEtf9y3oQY
  => Dashboards: /api/hassio_ingress/G9ocwA44wt9Bcba8LvP8tDhlfFiFnnPftOZBwp-Pgzs

```

From the add-on Info tab, click "Open Web UI", enter the Tesla API access and refresh tokens if you haven't already, and then go to TeslaMate's Settings.
Scroll to the very bottom and set each of the URLs to the URL you use to access your Home Assistant instance with each of the above appended.

For example, if you access your Home Assistant instance at `https://ha.example.com`, set each as follows:

- Web App: `https://ha.example.com/api/hassio_ingress/ljiIc6sOVGOSQfTRjscvLVJJS5Rxp33gsdEtf9y3oQY`
- Dashboards: `https://ha.example.com/api/hassio_ingress/G9ocwA44wt9Bcba8LvP8tDhlfFiFnnPftOZBwp-Pgzs`

Do _not_ use these values. Use the values from your log output.

**Note:** If you do not see the links in your add-on logs, clear the values in the TeslaMate configuration and restart the add-on.

## Migrate TeslaMate to a Different PostgreSQL Server

In order to migrate TeslaMate to a different PostgreSQL server, you will need to make a backup of the original data and then restore it to the destination server.
This isn't much of a challenge for the seasoned sysadmin familiar with Docker, PostgreSQL and the command line, however most Home Assistant users aren't expert sysadmins so this guide if for you.

1. Ensure you have both the current and new PostgreSQL servers installed and running and ensure you have the same users and roles configured on both.

2. Stop the TeslaMate add-on.

3. Install the [pgAdmin4](https://github.com/expaso/hassos-addons) add-on.

4. Start the pgAdmin4 add-on and open the web UI

5. Make a new connection to the current PostgreSQL server by clicking "Add New Server".

   1. Give it a recognisable name in the General tab.

   2. Switch to the Connection tab and enter the hostname, port, username and password currently used.
      You can find these in your TeslaMate add-on configuration.

   3. Click Save

6. Click the dropdown next to the new server -> Databases and then select the database you use for TeslaMate.
   This will be the same name you configured in the TeslaMate add-on configuration.

7. Go to Tools -> Backup, enter a filename, if you know what you're doing feel free to make other customisations but it's not essential, and then click Backup. [^1]

8. Once the backup has finished, repeats step 5 for your new PostgreSQL server to establish a connection to your new PostgreSQL server.

9. Select the new server, if not already selected, and go to Object -> Create -> Database and enter the same name and owner as used on your old server and click Save.

10. If the database is not already selected, select it and then go to Tools -> Restore, enter the filename you entered in step 7 and click Restore.
    You may need to use the file browser to locate the file. If you didn't change the path in step 7, the backup should be in `/root/`.

11. Once the restore has completed, go to the TeslaMate add-on settings and update the database settings to point to your new database server.
    The easiest approach is to use the steps in [Migrating to this version of the add-on][migrate-addon] further down in this file and change the `database_host` to the name of your new PostgreSQL server.

12. Update the Grafana configuration by going to the Grafana add-on -> Open web UI -> Grafana logo in top left -> Connections -> Datasources, select the TeslaMate source and change the Host URL to your new PostgreSQL server and click "Save & test".

13. Start the TeslaMate add-on and verifying everything is working as it was before. [^2]

You can now uninstall the pgAdmin4 add-on if you want and stop and uninstall your old PostgreSQL server if you're not using it for anything else.

## Import TeslaMate Backup

If you have made a backup of a TeslaMate installation as per the [TeslaMate backup documentation][teslamate-backup] and now have a `teslamate.bak` file you want to use with this add-on, you can do so as follows:

1. Install this TeslaMate add-on if you haven't already, but don't start it.

2. Install a PostgreSQL server and start it if you haven't already.
   We recommend the [PostgreSQL 17 add-on][alexbelgium-postgres] from @alexbelgium's repository, or [TimescaleDB][timescaledb] (for advanced users).

3. Perform steps 3, 4 and 5 from [Migrate TeslaMate to a Different PostreSQL Server][migrate-psql] above.

4. Transfer the `teslamate.bck` file to the `/share/teslamate` folder on your Home Assistant instance.
   You can do this using the [Samba][samba-addon] or [SSH][ssh-addon] add-ons.

5. Perform steps 9 and 10 from [Migrate TeslaMate to a Different PostreSQL Server][migrate-psql] above.
   Note: the file location will be `/share/teslamate/teslamate.bck`.

6. Configure TeslaMate and Grafana as per the details at the top of this file.

7. Start TeslaMate.

## Data Import from TeslaFi

It is now possible to import CSV data from TeslaFi, refer to the [official docs][teslafi-import].

Follow this process:

1. Copy the CSV data to the `/share/teslamate` folder on your Home Assistant instance.
   You can do this using the [Samba][samba-addon] or [SSH][ssh-addon] add-ons.

2. Make sure the `import_path` configuration setting is set to `/share/teslamate`.

3. Restart the TeslaMate add-on and navigate to the web UI, you should be presented with the import screen.

4. Import the data

5. Once imported sucessfully, delete the CSV files to avoid the import screen being presented.

[alexbelgium-postgres]: https://github.com/alexbelgium/hassio-addons/tree/master/postgres_17
[docker]: https://hub.docker.com/r/teslamate/teslamate
[elixir]: https://elixir-lang.org/
[grafana-addon]: https://github.com/hassio-addons/addon-grafana
[grafana-datasource]: https://raw.githubusercontent.com/lildude/ha-addon-teslamate/main/imgs/grafana-postgres.png
[migrate-psql]: #migrate-teslamate-to-a-different-postresql-server
[migrate-addon]: https://github.com/lildude/ha-addon-teslamate/blob/main/README.md#migrating-to-this-version-of-the-add-on
[mosquitto-docs]: https://github.com/home-assistant/addons/blob/master/mosquitto/DOCS.md
[pgadmin4]: https://github.com/expaso/hassos-addons
[samba-addon]: https://github.com/home-assistant/addons/blob/master/samba/DOCS.md
[ssh-addon]: https://github.com/home-assistant/addons/blob/master/ssh/DOCS.md
[teslafi-import]: https://docs.teslamate.org/docs/import/teslafi
[teslamate]: https://github.com/teslamate-org/teslamate/
[teslamate-backup]: https://docs.teslamate.org/docs/maintenance/backup_restore/#backup
[timescaledb]: https://github.com/expaso/hassos-addon-timescaledb

[^1]:
    If the backup or restore fails due to a `server version mismatch` error, you will need to select the latest version of PostgreSQL in pgAdmin4 by going to File -> Paths -> Binary paths and add the correct path for each version.
    For example, for PostgreSQL 14, enter `/usr/local/pgsql-14`, for PostgreSQL 15, enter `/usr/local/pgsql-15` etc.

[^2]:
    If you see the `ERROR:  type "earth" does not exist at character` error in the TeslaMate log, you can fix this by going back into pgAdmin4 and right click on the TeslaMate database -> "CREATE script".
    Delete everything auto generated and paste in the [codeblock here](https://github.com/diogob/activerecord-postgres-earthdistance/issues/30#issuecomment-2122829036).
    Click "Execute script" (It's the ▶️ symbol at the top).
