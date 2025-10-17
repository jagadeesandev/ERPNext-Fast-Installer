# ERPNext v15 Automated Installation Script

A simple bash script to automatically install ERPNext version 15 on Ubuntu 24.04 LTS.

## Quick Start

```bash
git clone https://github.com/jagadeesandev/ERPNext-Fast-Installer.git
cd ERPNext-Fast-Installer
chmod +x install_erpnext.sh
sudo ./install_erpnext.sh
```

## What it does

- Updates system packages
- Creates a Frappe user
- Installs MariaDB, Redis, Node.js, and other dependencies
- Sets up Frappe Bench
- Installs ERPNext and creates a site
- Optionally sets up production mode

## Requirements

- Ubuntu 24.04 LTS
- Root/sudo access
- 4GB RAM minimum
- 40GB disk space minimum
- Internet connection

## MySQL Root Password

The script automatically sets the MySQL root password to `erpnext123`. Save this password securely.

## Access ERPNext

- Development mode: http://localhost:8000
- Production mode: http://your-site-name

## Troubleshooting

Check the installation log file created during installation for any errors.

## License

MIT License
