# Running the suite on Windows

Frappe/ERPNext (and therefore this suite) **does not run natively on Windows** —
it is a Python + MariaDB + Redis + Node server designed for Linux. There are two
supported ways to use it on Windows, plus one "hand it over" option:

| Route | Best for | Difficulty |
|-------|----------|------------|
| **A. WSL2 + Ubuntu** (recommended) | Normal use, development | Easy (one script) |
| **B. Docker Desktop** | Clean isolation, no Linux knowledge | Easy |
| **C. Prebuilt VM image** | Fully non-technical handover | Easiest for the user, needs someone to build the VM |

---

## Route A — WSL2 + Ubuntu (recommended)

WSL2 runs a real Ubuntu Linux kernel inside Windows. Once inside Ubuntu, the
bundle's `./install.sh` works exactly as on Linux, and you open the desk in your
normal Windows browser.

### 1. Run the setup script

Open **PowerShell as Administrator**, `cd` to the bundle's `windows` folder, and:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

This enables WSL2 + VirtualMachinePlatform and installs Ubuntu.

### 2. Reboot, then open Ubuntu

After rebooting, open **Ubuntu** from the Start menu and create a UNIX
username/password.

### 3. Install the suite inside Ubuntu

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/ShyberDev/Jew_Pawn-Lending-Suite.git
cd Jew_Pawn-Lending-Suite
./install.sh
```

### 4. Run it and open from Windows

```bash
sudo systemctl start mariadb
cd ~/frappe-bench
bench start
```

Then, in your **Windows browser**:

- **http://localhost:8000/desk** — works out of the box (WSL2 forwards localhost).
- or **http://library.local:8000/desk** — add the site to the Windows hosts file
  first (Admin PowerShell):
  ```powershell
  Add-Content C:\Windows\System32\drivers\etc\hosts "127.0.0.1 library.local"
  ```

Login: `Administrator` / the admin password you chose.

> **Keep the Ubuntu window open** while using the suite (or set it up as a
> service later with `sudo bench setup production <user>`).

---

## Route B — Docker Desktop

1. Install **Docker Desktop** and enable the **WSL2 backend**.
2. Follow [`../docker/README.md`](../docker/README.md): build the suite image and
   run it with the `frappe_docker` compose stack.
3. Open **http://library.local:8080/desk** (add the hosts entry above).

This is the cleanest option if you don't want to manage a Linux shell, but it
needs more RAM (give Docker Desktop ≥ 8 GB).

---

## Route C — Prebuilt VM image (best for a non-technical user)

A VM image contains a complete, already-installed machine (OS + MariaDB + bench +
site + data). The user just boots it.

**To build one** (do this on a Linux machine that already runs the suite):

1. Install the suite on a Linux VM / cloud instance with `./install.sh`.
2. Shut it down and export the disk image:
   - **VirtualBox / VMware:** export the VM as `.ova` / `.ovf`.
   - **Cloud:** create a machine image (AWS AMI, GCP image, etc.).
3. Give the user the image plus one line:
   ```
   Boot the VM, then run:  sudo systemctl start mariadb && cd ~/frappe-bench && bench start
   # open http://library.local:8000/desk
   ```

This removes every installation step for the end user. The trade-off is the image
is large (several GB) and must be distributed outside git.

---

## Notes

- **Mobile/tablet:** open the same URL in the tablet browser on the same
  network (replace `localhost` with the PC's LAN IP, e.g. `http://192.168.1.20:8000`).
  Mobile ↔ laptop data **sync** is planned separately (see the main README).
- **Grey desk / missing sidebar** on Windows is the same Frappe issue — apply the
  fix in [`../README_FIRST.md`](../README_FIRST.md) §7 and hard-refresh
  (`Ctrl+Shift+R`).
- **Do not** try to install the apps directly into native Windows Python — it is
  not supported.
