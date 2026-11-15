[README.md](https://github.com/user-attachments/files/34868916/README.md)
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

After publishing this repository to GitHub, replace `YOUR_GITHUB_USER` below with the GitHub account or organization that owns this repository:

```bash
curl -fL -o install-panel-issabel5.zip \
  https://github.com/YOUR_GITHUB_USER/install-panel-issabel5/archive/refs/heads/main.zip \
&& unzip -o -q install-panel-issabel5.zip \
&& cd install-panel-issabel5-main \
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
- The script does not publish itself to GitHub. Create a repository named `install-panel-issabel5`, upload these files, then use the command above.
