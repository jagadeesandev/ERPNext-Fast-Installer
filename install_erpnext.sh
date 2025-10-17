#!/bin/bash

# ERPNext v15 Automated Installation Script for Ubuntu 24.04 LTS
# This script automates the installation of ERPNext version 15 on Ubuntu 24.04 LTS

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="erpnext_install_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log_message() {
    local message="$1"
    local level="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        *)
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_message "This script must be run as root" "ERROR"
        exit 1
    fi
}

# Function to check system requirements
check_system_requirements() {
    log_message "Checking system requirements..." "INFO"
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        log_message "This script is designed for Ubuntu 24.04 LTS. Your system may not be compatible." "WARN"
        read -p "Do you want to continue anyway? (y/n): " continue_anyway
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            log_message "Installation aborted by user" "INFO"
            exit 0
        fi
    else
        log_message "Ubuntu 24.04 LTS detected" "INFO"
    fi
    
    # Check hardware requirements
    total_mem=$(free -m | awk '/^Mem:/{print $2}')
    total_disk=$(df -BG --output=size / | tail -n 1 | tr -d 'G' | tr -d ' ')
    
    if [ "$total_mem" -lt 4000 ]; then
        log_message "Warning: Less than 4GB RAM detected ($total_mem MB). ERPNext may run slowly." "WARN"
    else
        log_message "Memory check passed: $total_mem MB" "INFO"
    fi
    
    if [ "$total_disk" -lt 40 ]; then
        log_message "Warning: Less than 40GB disk space detected ($total_disk GB). You may run out of space." "WARN"
    else
        log_message "Disk space check passed: $total_disk GB" "INFO"
    fi
}

# Function to update and upgrade system packages
update_system() {
    log_message "Updating system packages..." "INFO"
    apt-get update -y && apt-get upgrade -y
    if [ $? -ne 0 ]; then
        log_message "Failed to update system packages" "ERROR"
        exit 1
    fi
    log_message "System packages updated successfully" "INFO"
}

# Function to create a new user for Frappe
create_frappe_user() {
    log_message "Setting up Frappe user..." "INFO"
    
    read -p "Enter username for Frappe bench user: " frappe_user
    
    # Check if user already exists
    if id "$frappe_user" &>/dev/null; then
        log_message "User $frappe_user already exists" "WARN"
        read -p "Do you want to use this existing user? (y/n): " use_existing
        if [[ "$use_existing" != "y" && "$use_existing" != "Y" ]]; then
            create_frappe_user
            return
        fi
    else
        # Create new user
        adduser "$frappe_user"
        if [ $? -ne 0 ]; then
            log_message "Failed to create user $frappe_user" "ERROR"
            exit 1
        fi
        
        # Add user to sudo group
        usermod -aG sudo "$frappe_user"
        if [ $? -ne 0 ]; then
            log_message "Failed to add $frappe_user to sudo group" "ERROR"
            exit 1
        fi
    fi
    
    log_message "Frappe user $frappe_user setup completed" "INFO"
    
    # Export the frappe_user variable for use in other functions
    export FRAPPE_USER="$frappe_user"
}

# Function to install required packages
install_packages() {
    log_message "Installing required packages..." "INFO"
    
    # Install Git
    log_message "Installing Git..." "INFO"
    apt-get install git -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install Git" "ERROR"
        exit 1
    fi
    
    # Install Python dependencies
    log_message "Installing Python dependencies..." "INFO"
    apt-get install python3-dev python3-setuptools python3-pip -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install Python dependencies" "ERROR"
        exit 1
    fi
    
    # Install Python virtualenv
    log_message "Installing Python virtualenv..." "INFO"
    apt install python3.12-venv -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install Python virtualenv" "ERROR"
        exit 1
    fi
    
    # Install Redis
    log_message "Installing Redis server..." "INFO"
    apt-get install redis-server -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install Redis server" "ERROR"
        exit 1
    fi
    
    # Install CURL
    log_message "Installing CURL..." "INFO"
    apt install curl -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install CURL" "ERROR"
        exit 1
    fi
    
    # Install NPM
    log_message "Installing NPM..." "INFO"
    apt-get install npm -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install NPM" "ERROR"
        exit 1
    fi
    
    # Install wkhtmltopdf
    log_message "Installing wkhtmltopdf..." "INFO"
    apt-get install xvfb libfontconfig wkhtmltopdf -y
    if [ $? -ne 0 ]; then
        log_message "Failed to install wkhtmltopdf" "ERROR"
        exit 1
    fi
    
    log_message "All required packages installed successfully" "INFO"
}

# Function to setup MariaDB
setup_mariadb() {
    log_message "Setting up MariaDB..." "INFO"
    
    # Install MariaDB
    apt-get install software-properties-common -y
    apt install mariadb-server -y
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install MariaDB" "ERROR"
        exit 1
    fi
    
    # Start MariaDB service
    log_message "Starting MariaDB service..." "INFO"
    
    # First, try to clean up any previous failed installations
    if systemctl is-active --quiet mariadb; then
        log_message "MariaDB service is already running, stopping it first..." "INFO"
        systemctl stop mariadb
    fi
    
    # Reset MariaDB if it's in a failed state
    if systemctl is-failed --quiet mariadb; then
        log_message "MariaDB service is in failed state, resetting..." "INFO"
        systemctl reset-failed mariadb
    fi
    
    # Try to start MariaDB
    systemctl start mariadb
    if [ $? -ne 0 ]; then
        log_message "Failed to start MariaDB service normally, trying cleanup..." "WARN"
        
        # Try to purge and reinstall MariaDB
        log_message "Purging and reinstalling MariaDB..." "INFO"
        systemctl stop mariadb 2>/dev/null || true
        apt remove --purge mariadb-server mariadb-client mariadb-common -y 2>/dev/null || true
        rm -rf /var/lib/mysql /etc/mysql 2>/dev/null || true
        apt autoremove -y
        apt autoclean
        
        # Reinstall MariaDB
        apt update
        apt install mariadb-server -y
        
        # Try starting again
        systemctl start mariadb
        if [ $? -ne 0 ]; then
            log_message "Failed to start MariaDB service after cleanup" "ERROR"
            log_message "Please check system resources and try manual installation" "ERROR"
            exit 1
        fi
    fi
    
    # Enable MariaDB to start on boot
    systemctl enable mariadb
    
    log_message "Running MySQL secure installation..." "INFO"
    
    # Set MySQL root password and secure installation automatically
    MYSQL_ROOT_PASSWORD="erpnext123"
    log_message "Setting MySQL root password to: $MYSQL_ROOT_PASSWORD" "INFO"
    
    # Run mysql_secure_installation non-interactively
    mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF
    
    if [ $? -ne 0 ]; then
        log_message "Failed to secure MySQL installation" "ERROR"
        exit 1
    fi
    
    log_message "MySQL secured successfully" "INFO"
    log_message "MySQL root password set to: $MYSQL_ROOT_PASSWORD" "WARN"
    log_message "Please save this password securely!" "WARN"
    
    # Configure MySQL for ERPNext
    log_message "Configuring MySQL for ERPNext..." "INFO"
    
    # Create MySQL configuration
    cat > /etc/mysql/my.cnf << EOF
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
    
    # Restart MySQL service
    log_message "Restarting MySQL service..." "INFO"
    service mysql restart
    
    log_message "MariaDB setup completed" "INFO"
}

# Function to install Node.js using NVM
install_nodejs() {
    log_message "Installing Node.js..." "INFO"
    
    # Switch to frappe user
    su - "$FRAPPE_USER" -c "curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | bash && source ~/.profile && nvm install 18"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install Node.js" "ERROR"
        exit 1
    fi
    
    # Install Yarn
    log_message "Installing Yarn..." "INFO"
    su - "$FRAPPE_USER" -c "source ~/.profile && npm install -g yarn"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install Yarn" "ERROR"
        exit 1
    fi
    
    log_message "Node.js and Yarn installed successfully" "INFO"
}

# Function to install Frappe Bench
install_frappe_bench() {
    log_message "Installing Frappe Bench..." "INFO"
    
    # Install frappe-bench
    pip3 install frappe-bench --break-system-packages
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install Frappe Bench" "ERROR"
        exit 1
    fi
    
    # Install ansible
    pip3 install ansible --break-system-packages
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install Ansible" "ERROR"
        exit 1
    fi
    
    log_message "Frappe Bench installed successfully" "INFO"
}

# Function to initialize Frappe Bench
initialize_bench() {
    log_message "Initializing Frappe Bench..." "INFO"
    
    # Switch to frappe user
    cd /home/"$FRAPPE_USER"
    su - "$FRAPPE_USER" -c "bench init frappe-bench --frappe-branch version-15"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to initialize Frappe Bench" "ERROR"
        exit 1
    fi
    
    # Change directory permissions
    chmod -R o+rx /home/"$FRAPPE_USER"
    
    log_message "Frappe Bench initialized successfully" "INFO"
}

# Function to create a new site
create_site() {
    log_message "Creating a new site..." "INFO"
    
    # Prompt for site name
    read -p "Enter site name (e.g., mysite.local): " site_name
    
    # Switch to frappe user and create site
    cd /home/"$FRAPPE_USER"/frappe-bench
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench new-site $site_name"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to create site $site_name" "ERROR"
        exit 1
    fi
    
    # Export the site_name variable for use in other functions
    export SITE_NAME="$site_name"
    
    log_message "Site $site_name created successfully" "INFO"
}

# Function to install ERPNext and other apps
install_apps() {
    log_message "Installing ERPNext and other apps..." "INFO"
    
    # Switch to frappe user and install payments app
    cd /home/"$FRAPPE_USER"/frappe-bench
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench get-app payments"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install payments app" "ERROR"
        exit 1
    fi
    
    # Install ERPNext
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench get-app --branch version-15 erpnext"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install ERPNext" "ERROR"
        exit 1
    fi
    
    # Ask if user wants to install HRMS
    read -p "Do you want to install HRMS app? (y/n): " install_hrms
    if [[ "$install_hrms" == "y" || "$install_hrms" == "Y" ]]; then
        su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench get-app hrms"
        
        if [ $? -ne 0 ]; then
            log_message "Failed to install HRMS app" "ERROR"
            exit 1
        fi
    fi
    
    # Install apps on site
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME install-app erpnext"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to install ERPNext on site $SITE_NAME" "ERROR"
        exit 1
    fi
    
    # Install HRMS on site if selected
    if [[ "$install_hrms" == "y" || "$install_hrms" == "Y" ]]; then
        su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME install-app hrms"
        
        if [ $? -ne 0 ]; then
            log_message "Failed to install HRMS app on site $SITE_NAME" "ERROR"
            exit 1
        fi
    fi
    
    log_message "ERPNext and selected apps installed successfully" "INFO"
}

# Function to setup production mode
setup_production() {
    log_message "Setting up production mode..." "INFO"
    
    # Ask if user wants to set up production mode
    read -p "Do you want to set up ERPNext for production mode? (y/n): " setup_prod
    if [[ "$setup_prod" != "y" && "$setup_prod" != "Y" ]]; then
        log_message "Skipping production setup" "INFO"
        return
    fi
    
    # Enable scheduler
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME enable-scheduler"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to enable scheduler" "ERROR"
        exit 1
    fi
    
    # Disable maintenance mode
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench --site $SITE_NAME set-maintenance-mode off"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to disable maintenance mode" "ERROR"
        exit 1
    fi
    
    # Setup production config
    cd /home/"$FRAPPE_USER"/frappe-bench
    bench setup production "$FRAPPE_USER"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to setup production config" "ERROR"
        exit 1
    fi
    
    # Setup NGINX
    su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench setup nginx"
    
    if [ $? -ne 0 ]; then
        log_message "Failed to setup NGINX" "ERROR"
        exit 1
    fi
    
    # Restart supervisor
    supervisorctl restart all
    
    # Setup production again
    bench setup production "$FRAPPE_USER"
    
    log_message "Production setup completed successfully" "INFO"
}

# Function to start ERPNext
start_erpnext() {
    log_message "Starting ERPNext..." "INFO"
    
    # Check if production mode is set up
    if [ -f "/home/$FRAPPE_USER/frappe-bench/config/supervisor.conf" ]; then
        log_message "ERPNext is set up in production mode. It will start automatically." "INFO"
        log_message "You can access it at http://$SITE_NAME" "INFO"
    else
        log_message "ERPNext is set up in development mode." "INFO"
        log_message "To start ERPNext, run the following command:" "INFO"
        log_message "su - $FRAPPE_USER -c 'cd /home/$FRAPPE_USER/frappe-bench && bench start'" "INFO"
        log_message "You can access it at http://localhost:8000" "INFO"
        
        # Ask if user wants to start ERPNext now
        read -p "Do you want to start ERPNext now? (y/n): " start_now
        if [[ "$start_now" == "y" || "$start_now" == "Y" ]]; then
            su - "$FRAPPE_USER" -c "cd /home/$FRAPPE_USER/frappe-bench && bench start &"
            log_message "ERPNext started. You can access it at http://localhost:8000" "INFO"
        fi
    fi
}

# Main function
main() {
    log_message "Starting ERPNext v15 installation on Ubuntu 24.04 LTS" "INFO"
    
    # Check if running as root
    check_root
    
    # Check system requirements
    check_system_requirements
    
    # Update system
    update_system
    
    # Create Frappe user
    create_frappe_user
    
    # Install required packages
    install_packages
    
    # Setup MariaDB
    setup_mariadb
    
    # Install Node.js
    install_nodejs
    
    # Install Frappe Bench
    install_frappe_bench
    
    # Initialize Bench
    initialize_bench
    
    # Create site
    create_site
    
    # Install ERPNext and other apps
    install_apps
    
    # Setup production mode
    setup_production
    
    # Start ERPNext
    start_erpnext
    
    log_message "ERPNext v15 installation completed successfully!" "INFO"
    log_message "Installation log saved to $LOG_FILE" "INFO"
}

# Run main function
main
