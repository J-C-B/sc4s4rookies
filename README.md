# sc4s4rookies

Community helpers to stand up a **Splunk Connect for Syslog (SC4S)**–friendly Splunk side for learning and labs (“4 rookies”): apps, TAs, rsyslog to local syslog, and HTTP Event Collector defaults.

Use at your own risk; read the script before you run it on anything important.

## What is in this repo

| Item | Purpose |
|------|--------|
| **`sc4rookies_builder_ubuntu2404_no_splunk.sh`** | Main installer for **Ubuntu 24.04**: Splunk detection, optional Splunk install, then SC4S4Rookies apps and config. |
| **`dependencies/`** | Splunk app and TA archives (`.tgz`, `.tar.gz`) versioned in git so **`wget` from GitHub raw** can pull them without S3 or a local clone. |
| **`archive/`** | Older builder scripts (CentOS 8, Ubuntu 20.04) kept for reference. |

## Quick start

1. On **Ubuntu 24.04**, run the script as **root** (for example `sudo bash sc4rookies_builder_ubuntu2404_no_splunk.sh`), or download raw and execute:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/J-C-B/sc4s4rookies/main/sc4rookies_builder_ubuntu2404_no_splunk.sh -o sc4rookies_builder_ubuntu2404_no_splunk.sh
   sudo bash sc4rookies_builder_ubuntu2404_no_splunk.sh
   ```

2. **Edit the script** (or export variables before running) for **`HEC_URL`** and **`HEC_TOKEN`** to match your indexer/heavy forwarder listener. Do not commit real secrets.

## Behavior at startup

The script uses colored prompts (green / yellow / red) so you can see what mode you are in.

1. **Splunk already installed** (`/opt/splunk/bin/splunk` exists and is executable)  
   - States that only **SC4S4Rookies** pieces will be applied.  
   - Asks **Continue? (y/n)** — **n** exits without changing rsyslog or running the rest.

2. **Splunk not found**  
   - Asks whether to **install Splunk first** using the community **Enterprise Ubuntu 24.04** script.  
   - **n** → exits with a clear message that SC4S4Rookies needs Splunk.  
   - **y** → downloads that script (**`curl`** preferred, **`wget`** fallback), runs it, verifies the Splunk binary, then continues with the same SC4S4Rookies steps as above.

If neither `curl` nor `wget` is available when Splunk is missing, the script tells you to install one and exits.

## Overrides (environment)

You can point at a fork, branch, or commit **without editing the file**:

| Variable | Default | Meaning |
|----------|---------|--------|
| **`SC4S4ROOKIES_DEPS_BASE_URL`** | `https://raw.githubusercontent.com/J-C-B/sc4s4rookies/main/dependencies` | Base URL for Splunk app/TA archives under `dependencies/`. Pin a commit by replacing `main` with a SHA. |
| **`SPLUNK_SCRIPT_URL`** | `https://raw.githubusercontent.com/J-C-B/community-splunk-scripts/master/enterprise-splunk-ubuntu2404.sh` | Full Splunk install when `/opt/splunk/bin/splunk` is missing and you answer **y**. |

Example:

```bash
export SC4S4ROOKIES_DEPS_BASE_URL='https://raw.githubusercontent.com/ORG/sc4s4rookies/my-branch/dependencies'
export SPLUNK_SCRIPT_URL='https://raw.githubusercontent.com/ORG/community-splunk-scripts/main/enterprise-splunk-ubuntu2404.sh'
sudo -E bash sc4rookies_builder_ubuntu2404_no_splunk.sh
```

## `dependencies/` folder

Archives in **`dependencies/`** should stay in sync with the **`wget`** lines in the Ubuntu 24.04 script. After you add or bump a package, commit and push so the raw GitHub URLs resolve.

**Private GitHub repos:** raw URLs will not serve binaries without authentication; use a public fork, release assets, or your own reachable URL via **`SC4S4ROOKIES_DEPS_BASE_URL`**.

## Troubleshooting SC4S startup messages

- **`curl: (60) … certificate subject name … does not match target hostname '127.0.0.1'`** and **`SC4S_ENV_CHECK_HEC`**: Splunk’s default HEC TLS certificate is not issued for the IP `127.0.0.1`. The builder defaults **`HEC_URL`** to **`https://<this-hostname>:8088`** so the name matches typical certs. Export **`HEC_URL`** yourself if Splunk listens under another DNS name or you terminate TLS elsewhere. Keep **`SC4S_DEST_SPLUNK_HEC_DEFAULT_TLS_VERIFY=no`** in the env file for lab/self-signed (already written by the script).

- **`tls(allow-compress(yes))` / OpenSSL 3.2** warnings in logs: noise from syslog-ng inside the container; upstream SC4S image behavior. They do not block startup if you see **sc4s version=…** and **starting syslog-ng**.

- **`netstat: command not found`**: Ubuntu does not ship **`netstat`** by default (and there is no `netstat` apt package). The script uses **`ss -tulpn`** instead.

## Contributing / maintenance

- Keep the script header comment block updated when behavior or defaults change.  
- Prefer small, focused changes to builders and a short note in this README when user-visible flow changes.
