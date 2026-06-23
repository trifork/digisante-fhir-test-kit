# Versioned DigiSanté FHIR Test Kit server image.
# The specific HAPI FHIR version is selected at build time via HAPI_VERSION and
# is baked into the published image NAME (see build.sh), while IMAGE_VERSION is
# carried as a separate image tag.
ARG HAPI_VERSION=v8.4.0-3

# The upstream hapiproject/hapi image is distroless (no shell). We pull a static
# busybox so our entrypoint wrapper can translate the IG_URLS startup parameter.
FROM busybox:1.36.1-musl AS busybox

FROM hapiproject/hapi:${HAPI_VERSION}

COPY --from=busybox /bin/busybox /busybox/busybox

# Spring Boot loads file:./config/application.yaml (workdir is /app) and lets it
# override the packaged defaults.
COPY application.yaml /app/config/application.yaml
COPY entrypoint.sh /entrypoint.sh

# Default branding (HL7 Switzerland). Served via the /branding resource location;
# mount a host directory at /branding to override the logo, welcome text, or name.
COPY branding/ /branding/

ENTRYPOINT ["/busybox/busybox", "sh", "/entrypoint.sh"]
