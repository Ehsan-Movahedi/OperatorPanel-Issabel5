# Issabel 5 Operator Panel Installer

One-command installer for the official Issabel operator panel module:

- Upstream: https://github.com/ISSABELPBX/panel-issabel5
- Installs the `control_panel` module into `/var/www/html/modules`
- Registers the module in Issabel ACL and PBX menu databases
- Automatically grants the `access` permission to the `administrator` group
- Creates timestamped backups of the ACL database, menu database, and any existing module directory
- Checks PHP syntax and verifies the resulting database records
- Does not restart Asterisk, Apache, or PHP-FPM

## Requirements

- Issabel 5
- Root access
- `git`, `sqlite3`, and PHP CLI
- Standard Issabel paths:
  - `/var/www/html/modules`
  - `/var/www/db/acl.db`
  - `/var/www/db/menu.db`

The installer checks the expected database tables and resolves group/action/resource IDs from the live database. It does not assume fixed numeric IDs.

## Run

Run the following command on your Issabel 5 server as root:

```bash
curl -fL -o OperatorPanel-Issabel5.zip \
https://github.com/Ehsan-Movahedi/OperatorPanel-Issabel5/archive/refs/heads/main.zip \
&& unzip -o -q OperatorPanel-Issabel5.zip \
&& cd OperatorPanel-Issabel5-main \
&& chmod 755 install.sh \
&& ./install.sh
```

Run the command as `root`.

## Backups

Each run creates a directory under:

```text
/root/backup-panel-issabel5/YYYYMMDD-HHMMSS/
```

It contains copies of `acl.db` and `menu.db`, and (if a previous module directory existed) `module-before-install/`.

## Notes

- The installer is designed to be repeatable. Existing ACL and menu records are not duplicated.
- If the module is already installed, its directory is preserved in the timestamped backup before the new version is put in place.
- No GUI permission step is required: the Administrator ACL access record is added automatically.
- This repository provides the installer only. It downloads the official operator panel source directly from the IssabelPBX upstream repository.
