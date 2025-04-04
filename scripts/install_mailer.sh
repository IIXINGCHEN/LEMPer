#!/usr/bin/env bash

# Mail Installer
# Min. Requirement  : GNU/Linux Ubuntu 18.04
# Last Build        : 14/02/2022
# Author            : MasEDI.Net (me@masedi.net)
# Since Version     : 1.0.0

# Include helper functions.
if [[ "$(type -t run)" != "function" ]]; then
    BASE_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )
    # shellcheck disable=SC1091
    . "${BASE_DIR}/utils.sh"

    # Make sure only root can run this installer script.
    requires_root "$@"

    # Make sure only supported distribution can run this installer script.
    preflight_system_check
fi

##
# Install Postfix Mail Transfer Agent.
##
function install_postfix() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MAILER}" == true ]]; then
            DO_INSTALL_POSTFIX="y"
            #SELECTED_INSTALLER=${POSTFIX_INSTALLER:-"repo"}
        else
            DO_INSTALL_POSTFIX="n"
        fi
    else
        while [[ "${DO_INSTALL_POSTFIX}" != "y" && "${DO_INSTALL_POSTFIX}" != "n" ]]; do
            read -rp "Do you want to install Postfix Mail Transfer Agent? [y/n]: " -i y -e DO_INSTALL_POSTFIX
        done
    fi

    if [[ "${DO_INSTALL_POSTFIX}" == y* || "${DO_INSTALL_POSTFIX}" == Y* ]]; then
        echo "Installing Postfix Mail-Transfer Agent..."

        #if [[ -n $(command -v sendmail) ]]; then
        #    echo "Remove existing sendmail install..."
        #    run service sendmail stop && \
        #    run update-rc.d -f sendmail remove && \
        #    run apt-get remove -q -y sendmail
        #fi

        run apt-get install -q -y mailutils postfix

        # Configure Postfix.
        echo "Configuring Postfix Mail-Transfer Agent..."

        run postconf -e "inet_interfaces=all"
        run postconf -e "inet_protocols=all"
        run postconf -e "alias_maps=hash:/etc/aliases"
        run postconf -e "alias_database=hash:/etc/aliases"
        run postconf -e "home_mailbox=Maildir/"
        run postconf -e "myhostname=${HOSTNAME}"
        run postconf -e "mydomain=${HOSTNAME}"
        run postconf -e "myorigin=${HOSTNAME}"
        run postconf -e "mydestination=\$myhostname, localhost, localhost.localdomain"
        #run postconf -e "relayhost="  [smtp.gmail.com]:587 require login

        # Setting up SMTP authentication.
        run postconf -e "smtpd_sasl_type=dovecot"
        run postconf -e "smtpd_sasl_path=private/auth"
        run postconf -e "smtpd_sasl_local_domain=localhost.localdomain"
        run postconf -e "smtpd_sasl_security_options=noanonymous"
        run postconf -e "broken_sasl_auth_clients=yes"
        run postconf -e "smtpd_sasl_auth_enable=yes"
        run postconf -e "smtpd_recipient_restrictions=permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination,reject_invalid_hostname,reject_non_fqdn_hostname,reject_non_fqdn_sender,reject_non_fqdn_recipient,reject_unknown_sender_domain,reject_rbl_client sbl.spamhaus.org,reject_rbl_client cbl.abuseat.org"

        # Enable secure Postfix.
        if [[ -n "${MAILER_CERT_PATH}" ]]; then
            run postconf -e "smtpd_tls_cert_file=${MAILER_CERT_PATH}/fullchain.pem"
            run postconf -e "smtpd_tls_key_file=${MAILER_CERT_PATH}/privkey.pem"
            run postconf -e "smtp_tls_security_level=may"
            run postconf -e "smtpd_tls_security_level=may"
            run postconf -e "smtp_tls_note_starttls_offer=yes"
            run postconf -e "smtpd_tls_loglevel=1"
            run postconf -e "smtpd_tls_received_header=yes"
        fi

        # TODO: Multiple domain, multiple user settings.
        # Ref: https://debian-administration.org/article/243/Handling_mail_for_multiple_virtual_domains_with_postfix

        # Virtual alias mapping.
        [ ! -d /etc/postfix/virtual ] && run mkdir -p /etc/postfix/virtual
        [ ! -f /etc/postfix/virtual/addresses ] && run touch /etc/postfix/virtual/addresses

        if [[ "${DRYRUN}" != true ]]; then
            cat > /etc/postfix/virtual/addresses <<EOL
${HOSTNAME} DOMAIN
${LEMPER_USERNAME}@${HOSTNAME}  ${LEMPER_USERNAME}
postmaster@${HOSTNAME}  ${LEMPER_USERNAME}
root@${HOSTNAME}    ${LEMPER_USERNAME}
wordpress@${HOSTNAME}   ${LEMPER_USERNAME}
EOL

            if [[ "${SENDER_DOMAIN}" == "${HOSTNAME}" ]]; then
                run bash -c "echo '@${SENDER_DOMAIN}   ${LEMPER_USERNAME}' >> /etc/postfix/virtual/addresses"
            else
                cat >> /etc/postfix/virtual/addresses <<EOL
${SENDER_DOMAIN}    DOMAIN
@${SENDER_DOMAIN}   ${LEMPER_USERNAME}
EOL
            fi
        else
            info "Configure Postfix virtual addresses in dry run mode."
        fi

        run postmap /etc/postfix/virtual/addresses
        run postconf -e "virtual_alias_maps=hash:/etc/postfix/virtual/addresses"

        # Virtual domain mapping.
        [ ! -f /etc/postfix/virtual/domains ] && run touch /etc/postfix/virtual/domains

        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true && "${SENDER_DOMAIN}" != "${HOSTNAME}" ]]; then
            run bash -c "echo '${SENDER_DOMAIN}' >> /etc/postfix/virtual/domains"
        fi

        run postconf -e "virtual_alias_domains=/etc/postfix/virtual/domains"

        # Enable Postfix on startup.
        run systemctl enable postfix.service
        run systemctl enable postfix@-.service

        # Installation status.
        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(systemctl is-active postfix) == "active" ]]; then
                run systemctl reload postfix.service
                success "Postfix reloaded successfully."
            elif [[ -n $(command -v postfix) ]]; then
                run systemctl start postfix.service

                if [[ $(systemctl is-active postfix) == "active" ]]; then
                    success "Postfix started successfully."
                else
                    error "Something goes wrong with Postfix installation."
                fi
            fi
        else
            info "Postfix reloaded in dry run mode."
        fi
    else
        info "Postfix installation skipped."
    fi
}

##
# Install Dovecot
##
function install_dovecot() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_MAILER}" == true ]]; then
            DO_INSTALL_DOVECOT="y"
            #SELECTED_INSTALLER=${DOVECOT_INSTALLER:-"repo"}
        else
            DO_INSTALL_DOVECOT="n"
        fi
    else
        while [[ "${DO_INSTALL_DOVECOT}" != "y" && "${DO_INSTALL_DOVECOT}" != "n" ]]; do
            read -rp "Do you want to install Dovecot IMAP & POP3 server? [y/n]: " -i y -e DO_INSTALL_DOVECOT
        done
    fi

    if [[ "${DO_INSTALL_DOVECOT}" == y* || "${DO_INSTALL_DOVECOT}" == Y* ]]; then
        echo "Installing Dovecot IMAP & POP3 Server..."

        run apt-get install -q -y dovecot-core dovecot-common dovecot-imapd dovecot-pop3d

        # Configure Dovecot.
        echo "Configuring Dovecot IMAP & POP3 Server..."

        run maildirmake.dovecot /etc/skel/Maildir
        run maildirmake.dovecot /etc/skel/Maildir/.Drafts
        run maildirmake.dovecot /etc/skel/Maildir/.Sent
        run maildirmake.dovecot /etc/skel/Maildir/.Trash
        run maildirmake.dovecot /etc/skel/Maildir/.Templates
        run cp -r /etc/skel/Maildir "/home/${LEMPER_USERNAME}"
        run chown -R "${LEMPER_USERNAME}:${LEMPER_USERNAME}" "/home/${LEMPER_USERNAME}/Maildir"
        run chmod -R 700 "/home/${LEMPER_USERNAME}/Maildir"

        # Add LEMPer default user to mail group.
        run adduser "${LEMPER_USERNAME}" mail

        # Include the Maildir location in terminal and mail profiles.
        #run bash -c "echo -e '\nexport MAIL=~/Maildir' >> /etc/bash.bashrc"
        #run bash -c "echo -e '\nexport MAIL=~/Maildir' >> /etc/profile.d/mail.sh"

        if grep -q "MAIL=~/Maildir" /etc/bash.bashrc; then
            run sed -i".bak" "/export\ MAIL=~\/Maildir/d" /etc/bash.bashrc
            run bash -c "echo -e 'export MAIL=~/Maildir' >> /etc/bash.bashrc"
        else
            run bash -c "echo -e '\n# LEMPer Mailer\nexport MAIL=~/Maildir' >> /etc/bash.bashrc"
        fi

        if grep -q "MAIL=~/Maildir" /etc/profile.d/mail.sh; then
            run sed -i".bak" "/export\ MAIL=~\/Maildir/d" /etc/profile.d/mail.sh
            run bash -c "echo -e 'export MAIL=~/Maildir' >> /etc/profile.d/mail.sh"
        else
            run bash -c "echo -e '\n# LEMPer Mailer\nexport MAIL=~/Maildir' >> /etc/profile.d/mail.sh"
        fi

        # User authentication (with SASL).
        if [[ -f /etc/dovecot/conf.d/10-auth.conf ]]; then
            # Disabling the plaintext authentication.
            if grep -qwE "^#disable_plaintext_auth\ =\ [a-zA-Z]*" /etc/dovecot/conf.d/10-auth.conf; then
                run sed -i "/^#disable_plaintext_auth/a disable_plaintext_auth\ =\ yes" \
                    /etc/dovecot/conf.d/10-auth.conf
            else
                run sed -i "s/disable_plaintext_auth\ =\ [a-zA-Z]*/disable_plaintext_auth\ =\ yes/g" \
                    /etc/dovecot/conf.d/10-auth.conf
            fi

            # Enabling login authentication mechanism.
            if grep -qwE "^#auth_mechanisms\ =\ [a-zA-Z]*" /etc/dovecot/conf.d/10-auth.conf; then
                run sed -i "/^#auth_mechanisms/a auth_mechanisms = plain login" \
                    /etc/dovecot/conf.d/10-auth.conf
            else
                run sed -i "s/auth_mechanisms\ =\ [a-zA-Z]*/auth_mechanisms\ =\ plain\ login/g" \
                    /etc/dovecot/conf.d/10-auth.conf
            fi
        fi

        # Set the mail directory to use the same format as Postfix.
        if [[ -f /etc/dovecot/conf.d/10-mail.conf ]]; then
            # Maildir.
            if grep -qwE "^mail_location\ =\ [^[:digit:]]*$" /etc/dovecot/conf.d/10-mail.conf; then
                run sed -i "s/^mail_location\ =\ [^[:digit:]]*$/mail_location\ =\ maildir:~\/Maildir/g" \
                    /etc/dovecot/conf.d/10-mail.conf
            else
                run sed -iE "/^#mail_location\ =\ [^[:digit:]]*$/a mail_location\ =\ maildir:~\/Maildir" \
                    /etc/dovecot/conf.d/10-mail.conf
            fi
        fi

        # Enable IMAP and POP3 protocols for email clients.
        if [[ -f /etc/dovecot/conf.d/10-master.conf ]]; then
            # IMAP
            run sed -i "s/#port\ =\ 143/port\ =\ 143/g" /etc/dovecot/conf.d/10-master.conf
            # IMAPS
            run sed -i "s/#port\ =\ 993/port\ =\ 993/g" /etc/dovecot/conf.d/10-master.conf
            run sed -i "s/#ssl\ =\ yes/ssl\ =\ yes/g" /etc/dovecot/conf.d/10-master.conf

            # POP3
            run sed -i "s/#port\ =\ 110/port\ =\ 110/g" /etc/dovecot/conf.d/10-master.conf
            # POP3S
            run sed -i "s/#port\ =\ 995/port\ =\ 995/g" /etc/dovecot/conf.d/10-master.conf
            run sed -i "s/#ssl\ =\ yes/ssl\ =\ yes/g" /etc/dovecot/conf.d/10-master.conf

            # Postfix SMTP auth.
            run sed -i "s/#mode\ =\ 0666/mode\ =\ 0666/g" /etc/dovecot/conf.d/10-master.conf
            run sed -i "s/#user\ =\ postfix/user\ =\ postfix/g" /etc/dovecot/conf.d/10-master.conf
            run sed -i "s/#group\ =\ postfix/group\ =\ postfix/g" /etc/dovecot/conf.d/10-master.conf
        fi

        # Let's Encrypt SSL certs.
        if [[ -n "${MAILER_CERT_PATH}" && -f /etc/dovecot/conf.d/10-ssl.conf ]]; then
            # SSL cert.
            if grep -qwE "^ssl_cert\ =\ [^[:digit:]]*$" /etc/dovecot/conf.d/10-ssl.conf; then
                run sed -i "s|^ssl_cert\ =\ [^[:digit:]]*$|ssl_cert\ =\ <${MAILER_CERT_PATH}/fullchain.pem|g" \
                    /etc/dovecot/conf.d/10-ssl.conf
            else
                run sed -iE "/^#ssl_cert\ =\ [^[:digit:]]*$/a ssl_cert\ =\ <${MAILER_CERT_PATH}/fullchain.pem" \
                    /etc/dovecot/conf.d/10-ssl.conf
            fi

            # SSL key.
            if grep -qwE "^ssl_key\ =\ [^[:digit:]]*$" /etc/dovecot/conf.d/10-ssl.conf; then
                run sed -i "s|^ssl_key\ =\ [^[:digit:]]*$|ssl_key\ =\ ${MAILER_CERT_PATH}/privkey.pem|g" \
                    /etc/dovecot/conf.d/10-ssl.conf
            else
                run sed -iE "/^#ssl_key\ =\ [^[:digit:]]*$/a ssl_key\ =\ ${MAILER_CERT_PATH}/privkey.pem" \
                    /etc/dovecot/conf.d/10-ssl.conf
            fi
        fi

        # Enable Dovecot on startup.
        run systemctl enable dovecot.service

        # Installation status.
        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c dovecot) -gt 0 ]]; then
                run systemctl reload dovecot
                success "Dovecot reloaded successfully."
            elif [[ -n $(command -v dovecot) ]]; then
                run systemctl start dovecot

                if [[ $(pgrep -c dovecot) -gt 0 ]]; then
                    success "Dovecot started successfully."
                else
                    error "Something goes wrong with Dovecot installation."
                fi
            fi
        else
            info "Dovecot installed in dry run mode."
        fi
    else
        info "Dovecot installation skipped."
    fi
}

## TODO: Postfix and Dovecot default configuration
# https://www.linode.com/docs/email/postfix/email-with-postfix-dovecot-and-mysql/

## 
# Install SPF + DKIM
# Ref: https://www.linuxbabe.com/mail-server/setting-up-dkim-and-spf
##
function install_spf_dkim() {
    if [[ "${AUTO_INSTALL}" == true ]]; then
        if [[ "${INSTALL_SPFDKIM}" == true ]]; then
            DO_INSTALL_SPFDKIM="y"
        else
            DO_INSTALL_SPFDKIM="n"
        fi
    else
        while [[ "${DO_INSTALL_SPFDKIM}" != "y" && "${DO_INSTALL_SPFDKIM}" != "n" ]]; do
            read -rp "Do you want to install Postfix Policy Agent and OpenDKIM? [y/n]: " -i y -e DO_INSTALL_SPFDKIM
        done
    fi

    if [[ "${DO_INSTALL_SPFDKIM}" == y* || "${DO_INSTALL_SPFDKIM}" == Y* ]]; then
        echo "Installing Postfix Policy Agent and OpenDKIM..."

        run apt-get install -q -y postfix-policyd-spf-python opendkim opendkim-tools

        echo "Configuring SPF + DKIM..."

        # Update postfix master conf.
        if ! grep -qwE "^policyd-spf\  unix" /etc/postfix/master.cf; then
            run bash -c "echo 'policyd-spf  unix  -       n       n       -       0       spawn
  user=policyd-spf argv=/usr/bin/policyd-spf' >> /etc/postfix/master.cf"
        fi

        # Update postfix main conf.
        run postconf -e 'policyd-spf_time_limit = 3600'
        run postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated,permit_mynetworks,reject_unauth_destination,reject_invalid_hostname,reject_non_fqdn_hostname,reject_non_fqdn_sender,reject_non_fqdn_recipient,reject_unknown_sender_domain,reject_rbl_client sbl.spamhaus.org,reject_rbl_client cbl.abuseat.org,check_policy_service unix:private/policyd-spf'

        # Add postfix user to opendkim group.
        run adduser postfix opendkim

        # Connect Postfix to OpenDKIM.
        # Ubuntu ships Postfix in chrooted jail, 
        # need to update OpenDKIM socket to be able to communicate with OpenDKIM.
        # Create a directory to hold the OpenDKIM socket file and only allow opendkim user and postfix group to access it.
        run mkdir -p /var/spool/postfix/opendkim
        run chown opendkim:postfix /var/spool/postfix/opendkim

        # Update OpenDKIM default socket configuration file.
        if [[ -f /etc/default/opendkim ]]; then
            run sed -i "s/^RUNDIR=\/var\/run\/opendkim/#RUNDIR=\/var\/run\/opendkim/g" /etc/default/opendkim
            run sed -i "/^#RUNDIR=\/var\/spool\/postfix\/var\/run\/opendkim/s/^#//" /etc/default/opendkim
        fi

        # Update OpenDKIM socket config.
        local OPENDKIM_SOCKET="local:/var/spool/postfix/opendkim/opendkim.sock"
        run sed -i "/^Socket\s[^[:digit:]]*$/s//#&/" /etc/opendkim.conf
        run sed -i "/^#Socket\s[^[:digit:]]*$/a Socket\    ${OPENDKIM_SOCKET}" /etc/opendkim.conf

        # Postfix Milter configuration.
        run postconf -e "milter_default_action = accept"
        run postconf -e "milter_protocol = 6"
        run postconf -e "smtpd_milters = local:/opendkim/opendkim.sock"
        run postconf -e "non_smtpd_milters = \$smtpd_milters"

        # Adjusts OpenDKIM config.
        #run sed -i "/^#Canonicalization/a Canonicalization\       relaxed\/simple" /etc/opendkim.conf
        run sed -i "/^#Canonicalization/a Canonicalization\       relaxed\/relaxed" /etc/opendkim.conf
        run sed -i "/^#Mode/a Mode\                   sv" /etc/opendkim.conf
        run sed -i "/^#SubDomains/a SubDomains\             no" /etc/opendkim.conf
        run sed -i "/^SubDomains/a #ADSPAction\ continue\nAutoRestart\         yes\nAutoRestartRate\     10\/1M\nBackground\          yes\nDNSTimeout\          5\nSignatureAlgorithm\  rsa-sha256" /etc/opendkim.conf

        # Add opendkim user id.
        if ! grep -qwE "^UserID\                opendkim" /etc/opendkim.conf; then
            run bash -c "echo 'UserID                opendkim' >> /etc/opendkim.conf"
        fi

        # Add domains keys.
        if [[ "${DRYRUN}" != true ]]; then 
            cat >> /etc/opendkim.conf <<EOL
# Map domains in From addresses to keys used to sign messages
KeyTable           refile:/etc/opendkim/key.table
SigningTable       refile:/etc/opendkim/signing.table

# Hosts to ignore when verifying signatures
ExternalIgnoreList  /etc/opendkim/trusted.hosts

# A set of internal hosts whose mail should be signed
InternalHosts       /etc/opendkim/trusted.hosts
EOL
        fi

        # Create a directory structure for OpenDKIM.
        [ ! -d /etc/opendkim ] && \
        run mkdir -p /etc/opendkim && \
        run chown -hR opendkim:opendkim /etc/opendkim

        if [[ ! -d /etc/opendkim/keys ]]; then
            run mkdir -p /etc/opendkim/keys && \
            run chmod go-rw /etc/opendkim/keys
        fi

        # Create the signing table.
        [ ! -f /etc/opendkim/signing.table ] && run touch /etc/opendkim/signing.table

        #DOMAIN_SIGNING="*@your-domain.com    default._domainkey.your-domain.com"
        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true ]]; then
            DOMAIN_SIGNING="*@${SENDER_DOMAIN}    lemper._domainkey.${SENDER_DOMAIN}"
            run bash -c "echo '${DOMAIN_SIGNING}' > /etc/opendkim/signing.table"
        fi

        # Create the key table.
        [ ! -f /etc/opendkim/key.table ] && run touch /etc/opendkim/key.table

        #DOMAIN_KEY_TABLE="default._domainkey.your-domain.com     your-domain.com:default:/etc/opendkim/keys/your-domain.com/default.private"
        DOMAIN_KEY="lemper._domainkey.${SENDER_DOMAIN}"

        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true ]]; then
            DOMAIN_KEY_TABLE="${DOMAIN_KEY}    ${SENDER_DOMAIN}:lemper:/etc/opendkim/keys/${SENDER_DOMAIN}/lemper.private"
            run bash -c "echo '${DOMAIN_KEY_TABLE}' > /etc/opendkim/key.table"
        fi

        # Create trusted hosts.
        [ ! -f /etc/opendkim/trusted.hosts ] && run touch /etc/opendkim/trusted.hosts
        run bash -c "echo -e '127.0.0.1\nlocalhost' > /etc/opendkim/trusted.hosts"

        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true ]]; then
            run bash -c "echo -e '\n*.${SENDER_DOMAIN}' >> /etc/opendkim/trusted.hosts"
        fi

        # Generate Private/Public Keypair for sender domain.
        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true ]]; then
            # Create a separate folder for the domain.
            run mkdir -p "/etc/opendkim/keys/${SENDER_DOMAIN}"

            # Generate keys using opendkim-genkey tool.
            local KEY_HASH_LENGTH=${KEY_HASH_LENGTH:-2048}
            run opendkim-genkey -b "${KEY_HASH_LENGTH}" -d "${SENDER_DOMAIN}" -D "/etc/opendkim/keys/${SENDER_DOMAIN}" -s lemper -v

            # Make opendkim as the owner of the private key.
            run chown opendkim:opendkim "/etc/opendkim/keys/${SENDER_DOMAIN}/lemper.private"

            # Publish Your Public Key in DNS Records.
            if [[ "${DRYRUN}" != true ]]; then
                DKIM_KEY=$(cat "/etc/opendkim/keys/${SENDER_DOMAIN}/lemper.txt")
            else
                DKIM_KEY="Example DKIM Key"
            fi

            SPF_RECORD="v=spf1 ip4:${SERVER_IP} include:${SENDER_DOMAIN} mx ~all"
            
            export DOMAIN_KEY
            export DKIM_KEY
            export SPF_RECORD

            echo -e "Add this DKIM & SPF key to your DNS TXT record!\nDOMAIN_Key: ${DOMAIN_KEY}\nDKIM Record: ${DKIM_KEY}\nSPF Record: ${SPF_RECORD}"

            # Save log.
            save_log -e "Domain Key for ${SENDER_DOMAIN}: ${DOMAIN_KEY}\nDKIM Key for ${SENDER_DOMAIN}: ${DKIM_KEY}\nSPF Record for ${SENDER_DOMAIN}: ${SPF_RECORD}"

            # Test DKIM Key.
            #run opendkim-testkey -d "${SENDER_DOMAIN}" -s lemper -vvv
            echo -e "\nAfter then run this command to check your DNS record"
            echo "opendkim-testkey -d ${SENDER_DOMAIN} -s lemper -vvv"
            sleep 3
        fi

        # Enable OpenDKIM on startup.
        run systemctl enable opendkim

        # Installation status.
        if [[ "${DRYRUN}" != true ]]; then
            if [[ $(pgrep -c opendkim) -gt 0 ]]; then
                run systemctl reload opendkim
                success "OpenDKIM reloaded successfully."
            elif [[ -n $(command -v opendkim) ]]; then
                run systemctl start opendkim

                if [[ $(pgrep -c opendkim) -gt 0 ]]; then
                    success "OpenDKIM started successfully."
                else
                    error "Something goes wrong with OpenDKIM + SPF installation."
                fi
            fi
        else
            info "OpenDKIM + SPF installed in dry run mode."
        fi
    fi
}

##
# Initialize the mail server installation.
##
function init_mailer_install() {
    if [[ $(validate_fqdn "${SENDER_DOMAIN}") == false || "${SENDER_DOMAIN}" == "mail.example.com" || -z "${SENDER_DOMAIN}" ]]; then
        # Hostname TLD.
        #SENDER_DOMAIN=$(echo "${HOSTNAME}" | rev | cut -d "." -f1-2 | rev)
        SENDER_DOMAIN="${SERVER_HOSTNAME}"
    fi

    # Generating Let's Encrypt certificates.
    export MAILER_CERT_PATH

    if [[ "${ENVIRONMENT}" == prod* && "${DRYRUN}" != true ]]; then
        # Stop webserver first.
        run systemctl stop nginx

        if [[ $(validate_fqdn "${SENDER_DOMAIN}") == true && $(dig "${SENDER_DOMAIN}" +short) == "${SERVER_IP}" ]]; then
            echo "Generating LE certificates for sender domain '${SENDER_DOMAIN}'..."

            if [[ ! -d "/etc/letsencrypt/live/${SENDER_DOMAIN}" ]]; then
                run certbot certonly --standalone --agree-tos --preferred-challenges http -d "${SENDER_DOMAIN}"
            fi

            MAILER_CERT_PATH="/etc/letsencrypt/live/${SENDER_DOMAIN}"
        elif [[ $(dig "${HOSTNAME}" +short) == $(get_ip_private) ]]; then
            echo "Generating LE certificates for sender domain '${HOSTNAME}'..."

            if [[ ! -d "/etc/letsencrypt/live/${HOSTNAME}" ]]; then
                run certbot certonly --standalone --agree-tos --preferred-challenges http --webroot-path=/usr/share/nginx/html -d "${HOSTNAME}"
            fi

            MAILER_CERT_PATH="/etc/letsencrypt/live/${HOSTNAME}"
        else
            MAILER_CERT_PATH="${HOSTNAME_CERT_PATH}"
        fi

        # Re-start webserver.
        run systemctl start nginx
    fi

    if [[ -n $(command -v postfix) && "${FORCE_INSTALL}" != true ]]; then
        info "Postfix already exists, installation skipped."
    else
        install_postfix "$@"
    fi

    if [[ -n $(command -v dovecot) && "${FORCE_INSTALL}" != true ]]; then
        info "Dovecot already exists, installation skipped."
    else
        install_dovecot "$@"
    fi

    install_spf_dkim
}

echo "[Mail Server Installation]"

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_mailer_install "$@"
