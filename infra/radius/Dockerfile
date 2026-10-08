# Base image. The default is a version TAG, which is mutable: the registry owner
# can repoint it. For any deployment outside local development, resolve the tag
# to a digest yourself, verify it, and build with an immutable reference:
#
#   docker pull freeradius/freeradius-server:3.2.7
#   docker inspect --format '{{index .RepoDigests 0}}' freeradius/freeradius-server:3.2.7
#   docker build --build-arg FREERADIUS_IMAGE=freeradius/freeradius-server@sha256:<digest> .
#
# (docker compose: set WASEL_FREERADIUS_IMAGE in .env.) No digest is committed
# here on purpose: it must be obtained and verified by the operator, not guessed.
ARG FREERADIUS_IMAGE=freeradius/freeradius-server:3.2.7
FROM ${FREERADIUS_IMAGE}

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
    && chmod -R a+rX,go-w /etc/freeradius

# Privilege drop. The entrypoint and the config parser start as root (the
# read-only container needs CHOWN/SETGID/SETUID to prepare its run directories),
# then radiusd switches to the unprivileged user named by `user`/`group` in the
# `security` section of radiusd.conf. That directive comes from the base image,
# so the build FAILS here if a (future or substituted) base image does not set
# it to freerad -- the daemon must never keep serving packets as root.
# infra/radius/test/run-radius-e2e.sh additionally asserts at run time that
# PID 1 is not uid 0.
RUN grep -Eq '^[[:space:]]*user[[:space:]]*=[[:space:]]*freerad' /etc/freeradius/radiusd.conf \
    && grep -Eq '^[[:space:]]*group[[:space:]]*=[[:space:]]*freerad' /etc/freeradius/radiusd.conf \
    || { echo "ERROR: radiusd.conf does not drop privileges to freerad (security { user/group })." >&2; exit 1; }

USER root
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wasel"]
CMD ["freeradius", "-f"]
