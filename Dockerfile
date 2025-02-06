FROM alpine:3.17

RUN apk --no-cache add -f \
  openssl \
  openssh-client \
  coreutils \
  bind-tools \
  curl \
  sed \
  socat \
  tzdata \
  oath-toolkit-oathtool \
  tar \
  libidn \
  jq \
  cronie \
  nginx

# Create necessary nginx directories
RUN mkdir -p /run/nginx

ENV LE_CONFIG_HOME /acme.sh

ARG AUTO_UPGRADE=1
ARG TLD="fronts.cloud"
ARG STORENAME="smartstore"
ARG EMAIL="admin@$STORENAME.$TLD"
ARG STOREIP="192.168.0.4"
ARG ACME_PLUGIN="dns_ionos"
ENV AUTO_UPGRADE $AUTO_UPGRADE

#Install acme.sh
COPY ./ /install_acme.sh/
RUN cd /install_acme.sh && ([ -f /install_acme.sh/acme.sh ] && /install_acme.sh/acme.sh --install || curl https://get.acme.sh | sh) && rm -rf /install_acme.sh/

RUN ln -s /root/.acme.sh/acme.sh /usr/local/bin/acme.sh && crontab -l | grep acme.sh | sed 's#> /dev/null#> /proc/1/fd/1 2>/proc/1/fd/2#' | crontab -

#Issue certificates for the storename
RUN acme.sh --register-account -m $EMAIL
RUN acme.sh --force --issue --dns $ACME_PLUGIN --domain "$STORENAME.$TLD" -m "$EMAIL" \
      --fullchain-file /etc/ssl/certs/$STORENAME.$TLD.crt \
      --key-file /etc/ssl/private/$STORENAME.$TLD.key \
      --domain-alias "*.$STORENAME.$TLD"

# Create the configuration file from template
WORKDIR  /etc/nginx
COPY nginx.conf /etc/nginx/nginx.conf
RUN mkdir conf.d && cd conf.d
RUN mkdir conf.d && cd conf.d
RUN envsubst '\$STORENAME \$TLD \$STOREIP' < default.conf > ../$STORENAME.$TLD.conf.tmp && cd ..
RUN mv $STORENAME.$TLD.conf.tmp /etc/nginx/conf.d/$STORENAME.$TLD.conf
RUN mkdir -p /var/log/nginx
RUN chown -R nginx:nginx /var/log/nginx

RUN nginx -t
# Modify the entry script to handle environment variable substitution
RUN printf "%b" '#!'"/usr/bin/env sh\n \
if [ \"\$1\" = \"daemon\" ];  then \n \
 mv /etc/nginx/conf.d/default.conf.tmp /etc/nginx/conf.d/$STORENAME.$TLD.conf \n \
 nginx\n \
 exec crond -n -s -m off \n \
else \n \
 exec -- \"\$@\"\n \
fi\n" >/entry.sh && chmod +x /entry.sh

RUN for verb in help \
  version \
  install \
  uninstall \
  upgrade \
  issue \
  signcsr \
  deploy \
  install-cert \
  renew \
  renew-all \
  revoke \
  remove \
  list \
  info \
  showcsr \
  install-cronjob \
  uninstall-cronjob \
  cron \
  toPkcs \
  toPkcs8 \
  update-account \
  register-account \
  create-account-key \
  create-domain-key \
  createCSR \
  deactivate \
  deactivate-account \
  set-notify \
  set-default-ca \
  set-default-chain \
  ; do \
    printf -- "%b" "#!/usr/bin/env sh\n/root/.acme.sh/acme.sh --${verb} --config-home /acme.sh \"\$@\"" >/usr/local/bin/--${verb} && chmod +x /usr/local/bin/--${verb} \
  ; done

# Expose HTTP and HTTPS ports
EXPOSE 80 443

VOLUME /acme.sh

ENTRYPOINT ["/entry.sh"]
CMD ["daemon"]