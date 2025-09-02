# lubuntuscript
📄 Deskripsi Repo

Lubuntu Initialization & Tuning Script

Script shell untuk basic initialization dan tuning pada Lubuntu 24.04.3 LTS (Noble Numbat).
Dirancang agar cepat, aman, dan modular dengan konfigurasi yang bisa disesuaikan.

✨ Fitur

* Update & dist-upgrade otomatis
* Install common tools (build-essential, curl, git, htop, dll)
* Konfigurasi firewall UFW + Fail2ban (optional SSH allow)
* Enable unattended-upgrades (security updates)
* Tuning sysctl (swappiness rendah, BBR, fq qdisc, inotify limits, dll)
* File descriptor limit tinggi (1M)
* Batasi journal systemd (200MB default)
* Aktifkan weekly SSD/NVMe trim
* Tambah alias bash handy (ll, .., grep, dll)

🚀 Cara Pakai
git clone <repo-url>
cd <repo>
sudo bash lubuntu-init.sh

Edit bagian CONFIG di awal script sesuai kebutuhan (port SSH, ukuran journal, dsb).

📌 Catatan
* Script ini lebih cocok untuk desktop / workstation.
* Untuk server, tambahin hardening (AppArmor, auditd, dsb) sesuai kebutuhan.
* Reboot setelah eksekusi direkomendasikan.
