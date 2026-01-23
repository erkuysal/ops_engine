#!/bin/bash
# modules/cert/handler.sh - Enhanced SSL/TLS Certificate Module with Detection
# Implements four-phase lifecycle: detect → setup → configure → deploy

# Get module directory
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPSENGINE_DIR="$(cd "$MODULE_DIR/../.." && pwd)"

# Load core modules if not already loaded
if [[ -z "${OPSENGINE_CORE_LOADED:-}" ]]; then
    source "$OPSENGINE_DIR/core/utils.sh"
    source "$OPSENGINE_DIR/core/config.sh"
    source "$OPSENGINE_DIR/core/state.sh"
    source "$OPSENGINE_DIR/core/executor.sh"
    source "$OPSENGINE_DIR/core/module_base.sh"
    source "$OPSENGINE_DIR/core/integration.sh"
fi

# =============================================================================
# Module Registration
# =============================================================================

module_register "cert" "SSL/TLS Certificate Management with Detection" "2.1.0"

# =============================================================================
# Module-Specific Detection Storage
# =============================================================================

declare -gA CERT_DETECTED

# =============================================================================
# Phase 0: DETECT - Find existing certificates
# =============================================================================

module_detect() {
    log_section "Detecting Existing SSL Certificates"
    echo ""
    
    local found_any=false
    
    # Check Let's Encrypt certificates
    if [[ -d "/etc/letsencrypt/live" ]]; then
        log_info "Checking Let's Encrypt certificates..."
        local cert_dirs=$(sudo find /etc/letsencrypt/live -maxdepth 1 -type d 2>/dev/null | tail -n +2)
        
        if [[ -n "$cert_dirs" ]]; then
            while IFS= read -r cert_dir; do
                local domain=$(basename "$cert_dir")
                local fullchain="$cert_dir/fullchain.pem"
                local privkey="$cert_dir/privkey.pem"
                
                if sudo test -f "$fullchain" && sudo test -f "$privkey"; then
                    # Get certificate details
                    local expiry=$(sudo openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2)
                    local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
                    local now_epoch=$(date +%s)
                    local days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))
                    
                    # Get issuer
                    local issuer=$(sudo openssl x509 -in "$fullchain" -noout -issuer 2>/dev/null | sed 's/issuer=//')
                    
                    # Store detection results
                    CERT_DETECTED["${domain}_found"]="true"
                    CERT_DETECTED["${domain}_path"]="$cert_dir"
                    CERT_DETECTED["${domain}_expiry"]="$expiry"
                    CERT_DETECTED["${domain}_days_left"]="$days_left"
                    CERT_DETECTED["${domain}_issuer"]="$issuer"
                    
                    # Display
                    if [[ $days_left -lt 30 ]]; then
                        log_warning "Found: $domain (expires in ${days_left} days) ⚠️"
                    else
                        log_success "Found: $domain (expires in ${days_left} days) ✓"
                    fi
                    
                    found_any=true
                fi
            done <<< "$cert_dirs"
        fi
    fi
    
    # Check custom certificate locations
    local custom_paths=(
        "/srv/docker-certs"
        "/etc/nginx/ssl"
        "/etc/ssl/certs"
    )
    
    for cert_path in "${custom_paths[@]}"; do
        if [[ -d "$cert_path" ]]; then
            local found_certs=$(find "$cert_path" -name "fullchain.pem" -o -name "*.crt" 2>/dev/null | head -5)
            if [[ -n "$found_certs" ]]; then
                log_info "Custom certificates in $cert_path:"
                while IFS= read -r cert_file; do
                    local domain=$(basename "$(dirname "$cert_file")")
                    CERT_DETECTED["custom_${domain}_path"]="$(dirname "$cert_file")"
                    log_success "  • $domain"
                    found_any=true
                done <<< "$found_certs"
            fi
        fi
    done
    
    # Check for certificate monitoring
    if [[ -f "/usr/local/bin/check-cert-expiration.sh" ]]; then
        CERT_DETECTED["monitoring_installed"]="true"
        log_success "Certificate monitoring is installed ✓"
        found_any=true
    fi
    
    echo ""
    if [[ "$found_any" == "true" ]]; then
        log_success "Detection complete - found existing certificates"
        return 0
    else
        log_info "No existing certificates found - will create new"
        return 1
    fi
}

# =============================================================================
# Phase 0.5: INTEGRATE - Use detected certificates
# =============================================================================

module_integrate() {
    log_section "Integrating Existing Certificates"
    echo ""
    
    # List detected certificates
    local domains=()
    for key in "${!CERT_DETECTED[@]}"; do
        if [[ "$key" == *"_found" ]] && [[ "${CERT_DETECTED[$key]}" == "true" ]]; then
            local domain="${key%_found}"
            domains+=("$domain")
        fi
    done
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        log_info "No certificates to integrate"
        return 0
    fi
    
    echo "Found certificates for:"
    local i=1
    for domain in "${domains[@]}"; do
        local days_left="${CERT_DETECTED[${domain}_days_left]}"
        echo "  $i) $domain (${days_left} days left)"
        ((i++))
    done
    echo ""
    
    read -p "Select certificate to use (1-${#domains[@]}, or 0 for new): " choice
    
    if [[ "$choice" == "0" ]]; then
        log_info "Will create new certificate"
        config_set "use_existing" "false"
        return 0
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#domains[@]} ]]; then
        local selected_domain="${domains[$((choice-1))]}"
        local cert_path="${CERT_DETECTED[${selected_domain}_path]}"
        
        log_success "Selected: $selected_domain"
        
        # Import configuration
        config_set "use_existing" "true"
        config_set "domain" "$selected_domain"
        config_set "cert_path" "$cert_path"
        config_set "fullchain_path" "$cert_path/fullchain.pem"
        config_set "privkey_path" "$cert_path/privkey.pem"
        
        # Check if renewal needed
        local days_left="${CERT_DETECTED[${selected_domain}_days_left]}"
        if [[ $days_left -lt 30 ]]; then
            log_warning "Certificate expires soon - consider renewal"
            if confirm "Renew certificate now?" "y"; then
                config_set "action" "renew"
            else
                config_set "action" "use"
            fi
        else
            config_set "action" "use"
        fi
        
        return 0
    else
        log_error "Invalid selection"
        return 1
    fi
}

# =============================================================================
# Additional Commands: Diagnose, Repair, Monitor
# =============================================================================

cert_diagnose() {
    log_section "SSL Certificate Diagnostics"
    echo ""
    
    local domain=$(config_get "domain")
    if [[ -z "$domain" ]]; then
        read -p "Enter domain to diagnose: " domain
    fi
    
    log_step "Testing SSL connection to $domain..."
    echo ""
    
    # Test 1: Basic connection
    log_info "1. Connection Test"
    if curl -sI "https://$domain" >/dev/null 2>&1; then
        log_success "  ✓ HTTPS connection successful"
    else
        log_error "  ✗ HTTPS connection failed"
    fi
    echo ""
    
    # Test 2: Certificate details
    log_info "2. Certificate Details"
    local cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates -issuer -subject 2>/dev/null)
    if [[ -n "$cert_info" ]]; then
        echo "$cert_info" | while IFS= read -r line; do
            log_success "  $line"
        done
    else
        log_error "  ✗ Could not retrieve certificate"
    fi
    echo ""
    
    # Test 3: Check certificate files
    log_info "3. Certificate Files"
    local cert_paths=(
        "/etc/letsencrypt/live/$domain"
        "/srv/docker-certs/$domain"
    )
    
    for cert_path in "${cert_paths[@]}"; do
        if [[ -d "$cert_path" ]]; then
            log_success "  ✓ Found: $cert_path"
            if [[ -f "$cert_path/fullchain.pem" ]]; then
                local size=$(stat -c%s "$cert_path/fullchain.pem" 2>/dev/null || echo 0)
                log_success "    fullchain.pem ($size bytes)"
            fi
            if [[ -f "$cert_path/privkey.pem" ]]; then
                local size=$(stat -c%s "$cert_path/privkey.pem" 2>/dev/null || echo 0)
                log_success "    privkey.pem ($size bytes)"
            fi
        fi
    done
    echo ""
    
    # Test 4: Expiration check
    log_info "4. Expiration Status"
    local fullchain="/etc/letsencrypt/live/$domain/fullchain.pem"
    if [[ -f "$fullchain" ]]; then
        local expiry=$(sudo openssl x509 -in "$fullchain" -noout -enddate 2>/dev/null | cut -d= -f2)
        local days_left=$(( ($(date -d "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s)) / 86400 ))
        
        if [[ $days_left -lt 7 ]]; then
            log_error "  ⚠️  URGENT: Expires in $days_left days!"
        elif [[ $days_left -lt 30 ]]; then
            log_warning "  ⚠️  Expires in $days_left days"
        else
            log_success "  ✓ Valid for $days_left days"
        fi
    fi
    echo ""
    
    # Test 5: Check for symlink issues
    log_info "5. Symlink Validation"
    if [[ -L "$fullchain" ]]; then
        local target=$(readlink -f "$fullchain" 2>/dev/null)
        if [[ -f "$target" ]]; then
            log_success "  ✓ Symlink valid: $target"
        else
            log_error "  ✗ Broken symlink!"
        fi
    fi
}

cert_repair() {
    log_section "Certificate Repair"
    echo ""
    
    local domain=$(config_get "domain")
    if [[ -z "$domain" ]]; then
        read -p "Enter domain to repair: " domain
    fi
    
    log_info "Checking for common issues..."
    
    # Issue 1: Broken symlinks
    local cert_live="/etc/letsencrypt/live/$domain"
    local cert_archive="/etc/letsencrypt/archive/$domain"
    
    if [[ -d "$cert_live" ]]; then
        local fullchain="$cert_live/fullchain.pem"
        if [[ -L "$fullchain" ]]; then
            local target=$(readlink -f "$fullchain" 2>/dev/null)
            if [[ ! -f "$target" ]]; then
                log_warning "Found broken symlink, attempting repair..."
                
                # Find latest certificate in archive
                if [[ -d "$cert_archive" ]]; then
                    local latest=$(ls -1t "$cert_archive"/fullchain*.pem 2>/dev/null | head -1)
                    if [[ -f "$latest" ]]; then
                        sudo cp "$latest" "$cert_live/fullchain.pem"
                        sudo cp "$(dirname "$latest")/privkey$(basename "$latest" | sed 's/fullchain//')" "$cert_live/privkey.pem"
                        log_success "Repaired symlinks by copying from archive"
                    fi
                fi
            fi
        fi
    fi
    
    # Issue 2: Permission issues
    log_info "Checking permissions..."
    if [[ -f "$cert_live/fullchain.pem" ]]; then
        sudo chmod 644 "$cert_live/fullchain.pem"
        sudo chmod 600 "$cert_live/privkey.pem"
        log_success "Fixed permissions"
    fi
    
    # Issue 3: Nginx reload
    if command -v nginx &>/dev/null; then
        log_info "Testing Nginx configuration..."
        if sudo nginx -t 2>/dev/null; then
            log_success "Nginx config valid"
            if confirm "Reload Nginx?" "y"; then
                sudo nginx -s reload
                log_success "Nginx reloaded"
            fi
        else
            log_error "Nginx config has errors"
        fi
    fi
}

cert_monitor() {
    log_section "Setup Certificate Monitoring"
    echo ""
    
    local domain=$(config_get "domain")
    if [[ -z "$domain" ]]; then
        read -p "Enter domain to monitor: " domain
    fi
    
    read -p "Alert threshold (days before expiry, default: 30): " alert_days
    alert_days=${alert_days:-30}
    
    read -p "Email for alerts (optional): " alert_email
    
    # Create monitoring script
    local monitor_script="/usr/local/bin/check-cert-expiration.sh"
    
    log_info "Creating monitoring script..."
    sudo tee "$monitor_script" > /dev/null <<EOF
#!/bin/bash
# Auto-generated by opsengine cert monitor

DOMAIN="$domain"
ALERT_DAYS=$alert_days
ALERT_EMAIL="$alert_email"
LOG_FILE="/var/log/cert-expiration.log"

check_cert() {
    local cert_file="/etc/letsencrypt/live/\$DOMAIN/fullchain.pem"
    
    if [[ ! -f "\$cert_file" ]]; then
        echo "[\$(date)] ERROR: Certificate not found" >> "\$LOG_FILE"
        return 1
    fi
    
    local expiry=\$(sudo openssl x509 -in "\$cert_file" -noout -enddate | cut -d= -f2)
    local days_left=\$(( (\$(date -d "\$expiry" +%s) - \$(date +%s)) / 86400 ))
    
    echo "[\$(date)] \$DOMAIN: \$days_left days remaining" >> "\$LOG_FILE"
    
    if [[ \$days_left -lt \$ALERT_DAYS ]]; then
        local message="WARNING: SSL certificate for \$DOMAIN expires in \$days_left days"
        echo "\$message" >> "\$LOG_FILE"
        
        if [[ -n "\$ALERT_EMAIL" ]]; then
            echo "\$message" | mail -s "SSL Certificate Expiring Soon" "\$ALERT_EMAIL"
        fi
    fi
}

check_cert
EOF
    
    sudo chmod +x "$monitor_script"
    log_success "Created monitoring script"
    
    # Setup cron job
    log_info "Setting up daily cron job..."
    local cron_entry="0 2 * * * $monitor_script"
    
    (crontab -l 2>/dev/null | grep -v "check-cert-expiration.sh"; echo "$cron_entry") | crontab -
    log_success "Cron job installed (runs daily at 2 AM)"
    
    echo ""
    log_success "Monitoring setup complete!"
    echo ""
    echo "Test the monitor:"
    echo "  sudo $monitor_script"
    echo ""
    echo "View logs:"
    echo "  tail -f /var/log/cert-expiration.log"
}

# =============================================================================
# Enhanced module_main to handle extra commands
# =============================================================================

cert_main() {
    local action="${1:-run}"
    shift 2>/dev/null || true
    
    case "$action" in
        diagnose|check|verify)
            cert_diagnose
            ;;
        repair|fix)
            cert_repair
            ;;
        monitor|watch)
            cert_monitor
            ;;
        *)
            # Delegate to standard module_main
            module_main "$action" "$@"
            ;;
    esac
}

# Override the standard help
module_help() {
    cat <<EOF
Module: cert
============
SSL/TLS Certificate Management with Detection & Diagnostics

Standard Workflow:
  ops cert detect     Detect existing certificates
  ops cert integrate  Use detected certificates
  ops cert setup      Check prerequisites
  ops cert configure  Configure certificate
  ops cert deploy     Create/deploy certificate
  ops cert run        Full workflow (auto-detects)

Diagnostics & Maintenance:
  ops cert diagnose   Run comprehensive diagnostics
  ops cert repair     Auto-repair common issues
  ops cert monitor    Setup expiration monitoring
  ops cert status     Show current state
  ops cert reset      Reset to initial state

Examples:
  # Fresh setup with auto-detection
  ops cert run
  
  # Use existing certificate
  ops cert detect
  ops cert integrate
  
  # Troubleshooting
  ops cert diagnose
  ops cert repair
  
  # Setup monitoring
  ops cert monitor

EOF
}

# Export and run
export -f module_detect module_integrate
export -f cert_diagnose cert_repair cert_monitor cert_main

# Use custom main instead of standard module_main
cert_main "$@"
