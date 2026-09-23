FROM freeradius/freeradius-server:3.2.7

COPY freeradius/clients.conf /etc/freeradius/clients.conf
COPY freeradius/mods-available/wasel_rest /etc/freeradius/mods-available/wasel_rest
COPY freeradius/sites-available/wasel /etc/freeradius/sites-available/wasel
COPY docker-entrypoint-wasel.sh /usr/local/bin/docker-entrypoint-wasel

RUN chmod 0555 /usr/local/bin/docker-entrypoint-wasel \
    && ln -sf /etc/freeradius/mods-available/wasel_rest /etc/freeradius/mods-enabled/wasel_rest \
    && rm -f /etc/freeradius/mods-enabled/eap \
    && rm -f /etc/freeradius/sites-enabled/default /etc/freeradius/sites-enabled/inner-tunnel \
    && ln -sf /etc/freeradius/sites-available/wasel /etc/freeradius/sites-enabled/wasel \
    && chgrp -R freerad /etc/freeradius \
    && chmod -R g+rX,o-rwx /etc/freeradius

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wasel"]
CMD ["freeradius", "-f"]
