#!/bin/bash
# modules/cert/handler.sh - SSL/TLS Certificate Module
# Implements three-phase lifecycle: setup → configure → deploy

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
fi

# =============================================================================
# Module Registration
# =============================================================================

module_register "cert" "SSL/TLS Certificate Management" "2.0.0"

# =============================================================================
# Phase 1: SETUP - Check prerequisites
# =============================================================================

module_setup() {
    local total_steps=4
    local step=0
    
    step=$((step + 1))
    step_progress $step $total_steps "Checking for certbot..."
    
    if ! check_tool "certbot" \
        "brew install certbot" \
        "sudo apt install certbot python3-certbot-nginx" \
        "cert"; then
        return 1
    fi
    
    step=$((step + 1))
    step_progress $step $total_steps "Checking for nginx..."
    
    if ! check_tool "nginx" \
        "brew install nginx" \
        "sudo apt install nginx" \
        "cert"; then
        return 1
    fi
    
    step=$((step + 1))
    step_progress $step $total_steps "Checking nginx service..."
    
    if ! check_service "nginx" \
        "sudo systemctl start nginx" \
        "brew services start nginx" \
        "cert"; then
        return 1
    fi
    
    step=$((step + 1))
    step_progress $step $total_steps "Checking root/sudo access..."
    
    # Check if we can run certbot
    if ! sudo -n true 2>/dev/null && ! sudo -v 2>/dev/null; then
        guidance_box "Sudo Access Required" \
            "SSL certificate creation requires root access.\nPlease ensure you have sudo privileges." \
            "ops cert resume"
        state_block "cert" "Sudo access required for certificate creation"
        return 1
    fi
    
    log_success "All prerequisites satisfied"
    return 0
}

# =============================================================================
# Phase 2: CONFIGURE - Collect settings
# =============================================================================

module_configure() {
    echo ""
    log_info "Configure SSL Certificate Settings"
    echo ""
    
    # Get domain
    local domain=$(config_prompt "Domain name (e.g., example.com)" "domain" "")
    
    if [[ -z "$domain" ]]; then
        log_error "Domain name is required"
        return 1
    fi
    
    # Validate domain format
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        log_warning "Domain format looks unusual: $domain"
        if ! confirm "Continue anyway?" "n"; then
            return 1
        fi
    fi
    
    # Check DNS resolution
    log_step "Checking DNS for $domain..."
    if ! check_dns "$domain"; then
        guidance_box "DNS Not Resolving" \
            "Domain $domain does not resolve.\nMake sure DNS is configured and propagated." \
            "ops cert resume"
        state_block "cert" "DNS not resolving for $domain"
        return 1
    fi
    
    # Get email
    local email=$(config_prompt "Email for certificate notifications" "email" "")
    
    if [[ -z "$email" ]]; then
        log_error "Email is required for Let's Encrypt"
        return 1
    fi
    
    # Certificate type
    echo ""
    echo "Certificate type:"
    echo "  1) Single domain ($domain)"
    echo "  2) Wildcard (*.$domain) - requires DNS validation"
    echo ""
    
    local cert_type="single"
    read -p "Choose [1-2, default: 1]: " type_choice
    
    case "${type_choice:-1}" in
        2)
            cert_type="wildcard"
            config_set "wildcard" "true"
            ;;
        *)
            cert_type="single"
            config_set "wildcard" "false"
            ;;
    esac
    
    config_set "cert_type" "$cert_type"
    
    # Staging mode?
    local staging="false"
    if confirm "Use Let's Encrypt staging (for testing)?" "n"; then
        staging="true"
    fi
    config_set "staging" "$staging"
    
    # Summary
    echo ""
    info_box "Configuration Summary" \
        "Domain: $domain\nEmail: $email\nType: $cert_type\nStaging: $staging"
    
    if ! confirm "Proceed with these settings?" "y"; then
        return 1
    fi
    
    log_success "Configuration saved"
    return 0
}

# =============================================================================
# Phase 3: DEPLOY - Create certificate
# =============================================================================

module_deploy() {
    local domain=$(config_get "domain")
    local email=$(config_get "email")
    local cert_type=$(config_get "cert_type" "single")
    local staging=$(config_get "staging" "false")
    local wildcard=$(config_get "wildcard" "false")
    
    if [[ -z "$domain" ]] || [[ -z "$email" ]]; then
        log_error "Missing configuration. Run: ops cert configure"
        return 1
    fi
    
    log_info "Creating SSL certificate for $domain"
    echo ""
    
    # Build certbot command
    local certbot_cmd="certbot"
    local certbot_args=()
    
    if [[ "$wildcard" == "true" ]]; then
        certbot_args+=(certonly --manual --preferred-challenges dns)
        certbot_args+=(-d "$domain" -d "*.$domain")
        
        guidance_box "Manual DNS Validation Required" \
            "Wildcard certificates require DNS validation.\nCertbot will ask you to create TXT records.\nFollow the prompts carefully." \
            ""
    else
        certbot_args+=(--nginx -d "$domain")
    fi
    
    certbot_args+=(--email "$email" --agree-tos --non-interactive)
    
    if [[ "$staging" == "true" ]]; then
        certbot_args+=(--staging)
        log_warning "Using Let's Encrypt STAGING environment"
    fi
    
    # Execute certbot
    log_step "Running certbot..."
    echo ""
    
    if exec_with_sudo "$certbot_cmd ${certbot_args[*]}" \
        "Run manually:\n  sudo $certbot_cmd ${certbot_args[*]}" \
        "cert"; then
        
        success_box "Certificate Created!" \
            "Domain: $domain\nCertificate: /etc/letsencrypt/live/$domain/"
        
        # Setup auto-renewal check
        log_step "Setting up auto-renewal..."
        
        if crontab -l 2>/dev/null | grep -q "certbot renew"; then
            log_success "Auto-renewal already configured"
        else
            local cron_entry="0 3 * * * /usr/bin/certbot renew --quiet"
            
            if confirm "Add auto-renewal cron job?" "y"; then
                (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
                log_success "Added auto-renewal cron job"
            fi
        fi
        
        return 0
    else
        log_error "Certificate creation failed"
        
        guidance_box "Troubleshooting" \
            "1. Check domain DNS is pointing to this server\n2. Ensure ports 80/443 are open\n3. Check nginx is running\n4. Review: /var/log/letsencrypt/letsencrypt.log" \
            "ops cert deploy"
        
        return 1
    fi
}

# =============================================================================
# Additional Commands
# =============================================================================

# Override status to show certificate info
module_status() {
    local phase=$(state_get_phase "$MODULE_NAME")
    local status=$(state_get_status "$MODULE_NAME")
    local domain=$(config_get "domain" "")
    
    echo ""
    echo "Module: cert (SSL/TLS Certificates)"
    echo "======================================="
    echo "Phase:    $phase"
    echo "Status:   $status"
    
    if [[ -n "$domain" ]]; then
        echo ""
        echo "Configuration:"
        echo "  Domain:   $domain"
        echo "  Email:    $(config_get "email" "")"
        echo "  Type:     $(config_get "cert_type" "single")"
        echo "  Staging:  $(config_get "staging" "false")"
    fi
    
    # Check if certificate exists
    if [[ -n "$domain" ]] && [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        echo ""
        echo "Certificate Status:"
        local expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/cert.pem" 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry" ]]; then
            echo "  Expires:  $expiry"
        fi
    fi
    
    if state_is_blocked "$MODULE_NAME"; then
        echo ""
        echo "⚠️  BLOCKED:"
        echo "   $(state_get_blocked_on "$MODULE_NAME")"
    fi
    
    echo ""
}

# Show module-specific help
module_help() {
    cat <<EOF
Module: cert (SSL/TLS Certificate Management)
=============================================

Automates SSL/TLS certificate creation using Let's Encrypt.

Usage:
  ops cert setup       Check certbot, nginx, and permissions
  ops cert configure   Enter domain, email, and certificate options
  ops cert deploy      Create the SSL certificate
  ops cert run         Run all phases in sequence
  ops cert status      Show certificate status
  ops cert check       Full SSL health check
  ops cert renew       Test/force certificate renewal
  ops cert monitor     Setup expiration monitoring
  ops cert resume      Resume if blocked on manual step
  ops cert reset       Clear configuration and start over

Phases:
  SETUP     - Checks for certbot, nginx, and sudo access
  CONFIGURE - Collects domain, email, certificate type
  DEPLOY    - Runs certbot to create certificate

Features:
  ✓ Single domain certificates
  ✓ Wildcard certificates (requires DNS validation)
  ✓ Auto-renewal hook setup
  ✓ Expiration monitoring with alerts
  ✓ Comprehensive SSL health checks
  ✓ Staging mode for testing

Examples:
  ops cert run                    # Full flow
  ops cert check example.com      # Check SSL health
  ops cert renew --dry-run        # Test renewal
  ops cert monitor                # Setup monitoring

EOF
}

# =============================================================================
# Extended Commands: check, renew, monitor
# =============================================================================

# Comprehensive SSL health check
cert_check() {
    local domain="${1:-$(config_get "domain")}"
    
    if [[ -z "$domain" ]]; then
        log_error "Domain required. Usage: ops cert check <domain>"
        return 1
    fi
    
    echo ""
    echo "=============================================="
    echo "  SSL Certificate Check for $domain"
    echo "=============================================="
    echo ""
    
    # 1. Basic connection test
    log_step "Testing SSL connection..."
    if curl -sI "https://$domain" -o /dev/null -w '' 2>&1; then
        log_success "SSL connection successful"
    else
        log_error "Cannot connect to https://$domain"
        return 1
    fi
    
    # 2. Get certificate dates
    log_step "Checking certificate dates..."
    local cert_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null)
    local dates=$(echo "$cert_info" | openssl x509 -noout -dates 2>/dev/null)
    
    if [[ -n "$dates" ]]; then
        local not_before=$(echo "$dates" | grep "notBefore" | cut -d= -f2)
        local not_after=$(echo "$dates" | grep "notAfter" | cut -d= -f2)
        echo "  Valid from: $not_before"
        echo "  Expires:    $not_after"
        
        # Calculate days remaining
        local exp_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null || \
                         date -d "$not_after" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        local days_left=$(( (exp_epoch - now_epoch) / 86400 ))
        
        if [[ $days_left -lt 0 ]]; then
            log_error "Certificate EXPIRED $((days_left * -1)) days ago!"
        elif [[ $days_left -le 7 ]]; then
            log_error "Certificate expires in $days_left days - CRITICAL!"
        elif [[ $days_left -le 30 ]]; then
            log_warning "Certificate expires in $days_left days"
        else
            log_success "Certificate valid for $days_left more days"
        fi
    else
        log_error "Could not retrieve certificate dates"
    fi
    echo ""
    
    # 3. Certificate issuer
    log_step "Certificate issuer..."
    local issuer=$(echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
    echo "  $issuer"
    echo ""
    
    # 4. Subject Alternative Names
    log_step "Subject Alternative Names (SANs)..."
    local sans=$(echo "$cert_info" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | tr ',' '\n' | sed 's/DNS://g' | tr -d ' ')
    if [[ -n "$sans" ]]; then
        echo "$sans" | while read -r san; do
            echo "  ✓ $san"
        done
    else
        echo "  (none found)"
    fi
    echo ""
    
    # 5. TLS Protocol support
    log_step "TLS protocol support..."
    for proto in tls1.2 tls1.3; do
        if curl -s --"$proto" "https://$domain" -o /dev/null 2>&1; then
            echo "  ✓ $(echo $proto | tr '.' ' ' | tr '[:lower:]' '[:upper:]') supported"
        else
            echo "  ✗ $(echo $proto | tr '.' ' ' | tr '[:lower:]' '[:upper:]') not supported"
        fi
    done
    echo ""
    
    # 6. HTTP to HTTPS redirect
    log_step "HTTP redirect check..."
    local redirect=$(curl -sI "http://$domain" 2>&1 | grep -i "location" | head -1)
    if [[ "$redirect" == *"https"* ]]; then
        log_success "HTTP redirects to HTTPS"
    else
        log_warning "HTTP may not redirect to HTTPS"
    fi
    echo ""
    
    # 7. Local certificate check (if exists)
    if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        log_step "Local certificate files..."
        local local_cert="/etc/letsencrypt/live/$domain/fullchain.pem"
        if [[ -f "$local_cert" ]]; then
            local local_dates=$(sudo openssl x509 -in "$local_cert" -noout -dates 2>/dev/null || \
                               openssl x509 -in "$local_cert" -noout -dates 2>/dev/null)
            if [[ -n "$local_dates" ]]; then
                echo "  Local cert: $(echo "$local_dates" | grep notAfter | cut -d= -f2)"
            fi
        fi
        echo ""
    fi
    
    success_box "SSL Check Complete" "Domain: $domain"
    return 0
}

# Certificate renewal
cert_renew() {
    local dry_run=false
    local force=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --force) force=true ;;
        esac
        shift
    done
    
    log_info "Certificate Renewal"
    echo ""
    
    # Check certbot
    if ! command -v certbot &>/dev/null; then
        log_error "certbot not found"
        return 1
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_step "Testing renewal (dry run)..."
        sudo certbot renew --dry-run
    elif [[ "$force" == "true" ]]; then
        log_step "Forcing certificate renewal..."
        sudo certbot renew --force-renewal
    else
        log_step "Checking for renewals..."
        sudo certbot renew
    fi
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        success_box "Renewal Complete" "Run 'ops cert check' to verify"
    else
        log_error "Renewal failed (exit code: $result)"
    fi
    
    return $result
}

# Setup certificate monitoring
cert_monitor_setup() {
    local alert_days="${1:-30}"
    local domain=$(config_get "domain" "")
    
    if [[ -z "$domain" ]]; then
        domain=$(config_prompt "Domain to monitor" "domain" "")
    fi
    
    log_info "Setting up certificate expiration monitoring for $domain"
    echo ""
    
    # Create monitoring script
    local monitor_script="/usr/local/bin/check-cert-expiration.sh"
    
    log_step "Creating monitoring script..."
    
    cat > /tmp/check-cert-expiration.sh << MONITOR_EOF
#!/bin/bash
# Certificate Expiration Check Script
# Generated by OpsEngine

DOMAIN="$domain"
ALERT_DAYS=$alert_days
LOG_FILE="/var/log/ssl-expiration-check.log"

log() {
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$1" | tee -a "\$LOG_FILE"
}

# Get expiration from live server
exp_date=\$(echo | openssl s_client -servername "\$DOMAIN" -connect "\$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

if [[ -z "\$exp_date" ]]; then
    log "ERROR: Cannot get certificate expiration for \$DOMAIN"
    exit 1
fi

# Calculate days remaining
exp_epoch=\$(date -d "\$exp_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "\$exp_date" +%s 2>/dev/null)
now_epoch=\$(date +%s)
days_left=\$(( (exp_epoch - now_epoch) / 86400 ))

if [[ \$days_left -lt 0 ]]; then
    log "CRITICAL: Certificate for \$DOMAIN EXPIRED \$((days_left * -1)) days ago!"
    exit 2
elif [[ \$days_left -le \$ALERT_DAYS ]]; then
    log "WARNING: Certificate for \$DOMAIN expires in \$days_left days"
    exit 1
else
    log "OK: Certificate for \$DOMAIN valid for \$days_left days"
    exit 0
fi
MONITOR_EOF

    if exec_with_sudo "cp /tmp/check-cert-expiration.sh $monitor_script && chmod +x $monitor_script" \
        "Copy script: sudo cp /tmp/check-cert-expiration.sh $monitor_script" \
        "cert"; then
        log_success "Monitoring script created: $monitor_script"
    else
        log_error "Failed to create monitoring script"
        return 1
    fi
    
    # Setup cron job
    echo ""
    if confirm "Add daily cron job (9 AM) for monitoring?" "y"; then
        local cron_entry="0 9 * * * $monitor_script >> /var/log/ssl-expiration-check.log 2>&1"
        
        (crontab -l 2>/dev/null | grep -v "check-cert-expiration"; echo "$cron_entry") | crontab -
        log_success "Cron job added for daily checks"
    fi
    
    # Test the script
    echo ""
    log_step "Testing monitoring script..."
    if bash /tmp/check-cert-expiration.sh 2>/dev/null; then
        log_success "Monitoring script works correctly"
    else
        log_warning "Script returned warning (check certificate expiration)"
    fi
    
    success_box "Monitoring Setup Complete" \
        "Script: $monitor_script\nAlert: $alert_days days before expiration\nLog: /var/log/ssl-expiration-check.log"
    
    rm -f /tmp/check-cert-expiration.sh
    return 0
}

# =============================================================================
# Entry Point - Extended with new commands
# =============================================================================

# Override module_main to add new commands
module_main() {
    local action="${1:-run}"
    shift 2>/dev/null || true
    
    if ! state_exists; then
        state_init
    fi
    
    case "$action" in
        # Standard module actions
        setup) _run_phase "setup" ;;
        configure) _run_phase "configure" ;;
        deploy) _run_phase "deploy" ;;
        run) module_run "$@" ;;
        resume) module_resume ;;
        status) module_status ;;
        reset) module_reset ;;
        help|--help|-h) module_help ;;
        
        # Extended cert-specific actions
        check) cert_check "$@" ;;
        renew) cert_renew "$@" ;;
        monitor|monitor-setup) cert_monitor_setup "$@" ;;
        
        *) 
            log_error "Unknown action: $action"
            module_help
            return 1 
            ;;
    esac
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    module_main "$@"
fi
