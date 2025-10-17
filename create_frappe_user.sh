# Function to create a new user for Frappe
create_frappe_user() {
    log_message "Setting up Frappe user..." "INFO"
    
    read -p "Enter username for Frappe bench user: " frappe_user
    
    # Check if user already exists
    if id "$frappe_user" &>/dev/null; then
        log_message "User $frappe_user already exists" "INFO"
        log_message "Continuing with existing user $frappe_user" "INFO"
    else
        # List available users
        log_message "User $frappe_user does not exist. Available users:" "INFO"
        awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd | grep -v "nobody"
        
        read -p "Do you want to use one of these existing users? (y/n): " use_existing
        
        if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
            read -p "Enter the username of the existing user: " frappe_user
            
            # Verify the user exists
            if ! id "$frappe_user" &>/dev/null; then
                log_message "User $frappe_user does not exist" "ERROR"
                create_frappe_user
                return
            fi
            
            log_message "Using existing user $frappe_user" "INFO"
            # No need to create a new user, just use the existing one
        else
            # Create new user
            log_message "Creating new user $frappe_user..." "INFO"
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
    fi
    
    log_message "Frappe user $frappe_user setup completed" "INFO"
    
    # Export the frappe_user variable for use in other functions
    export FRAPPE_USER="$frappe_user"
}
