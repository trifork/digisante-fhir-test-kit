# DigiSanté FHIR Test Kit

A disposable, versioned HAPI FHIR server with the built-in **hapi.fhir.org-style
tester** (a clone of [hapi.fhir.org](https://hapi.fhir.org/)) for unrestricted CRUD.
Implementation Guides are loaded into the server **from a URL at container startup**,
and the tester is branded for HL7 Switzerland.

> The profile-restricted, per-IG CRUD UI (dynamic forms generated from each
> profile's `StructureDefinition`) lives on the **`feat/ig-profile-ui`** branch,
> which builds on top of this one.

## Architecture

| Service | Image | Port | Purpose |
| --- | --- | --- | --- |
| `db` | `postgres:16-alpine` | — | Persistence |
| `fhir` | `…-hapi-<HAPI_VERSION>:<IMAGE_VERSION>` (from `hapiproject/hapi`) | 8080 | FHIR REST API + generic tester |

> **Base-image note:** the FHIR image is built `FROM hapiproject/hapi:<version>`,
> which is a distroless/Debian image — *not* Alpine. To make it Alpine, switch to a
> from-source multi-stage build.

## Versioning

The selected HAPI version is baked into the image **name**; the kit's own release is a separate image **tag**:

```
digisante-fhir-test-kit-hapi-v8.4.0-3 : 0.1.0
          └── HAPI version (name) ──┘   └ IMAGE_VERSION (tag)
```

Both are configurable via `HAPI_VERSION` and `IMAGE_VERSION` (build args / `.env`).

## Quick start

```bash
cp .env.example .env          # then edit IG_URLS, versions, ports
./build.sh                    # builds the versioned FHIR image
docker compose up -d          # or: podman compose up -d
```

- Generic tester + API: <http://localhost:8080>

## Loading Implementation Guides

Set `IG_URLS` (a startup parameter, comma-separated). Each item is either a package
`.tgz` URL, or explicit coordinates `name@version=url`:

```bash
IG_URLS=ch.fhir.ig.ch-emr@1.0.0-ballot=https://hl7ch.github.io/ch-emr/package.tgz
# multiple:
IG_URLS=https://example.org/a/package.tgz,my.ig@1.0.0=https://example.org/b/package.tgz
```

The container entrypoint expands `IG_URLS` into the native HAPI
`hapi.fhir.implementationguides.*` settings. Those native
`HAPI_FHIR_IMPLEMENTATIONGUIDES_*` environment variables also work directly if you
prefer to bypass `IG_URLS`.

### Dependencies

Each loaded IG's declared dependency packages are fetched and installed
transitively (`fetchDependencies`), so the base IGs it builds on — and profiles it
references via the `structuredefinition-imposeProfile` extension — are present for
snapshot generation and `$validate`. For example, loading CH EMR also installs
ch-core, ch-term, ch-ips, ch-emed, the HL7 extensions and **hl7.fhir.uv.ips** (the
source of CH EMR's imposed IPS profiles), and validating a resource against a
CH EMR profile then also enforces the imposed IPS profile.

A few HL7 "infrastructure" packages cannot be ingested by HAPI's package installer
and would abort startup (`hl7.terminology.r4` → `HAPI-1764`; `hl7.fhir.uv.xver-r5.r4`
→ over-long resource ids). These are **excluded by default** (they provide
terminology/cross-version helpers, not profiles). Adjust with
`IG_DEPENDENCY_EXCLUDES` (comma-separated regexes on package id; set empty to attempt
everything).

## Branding the built-in tester

The tester's **logo, name and welcome/sample text** default to HL7 Switzerland and
are overridable via a container mount. The image ships defaults under `/branding`:

```
/branding/custom/logo.jpg      # logo in the tester banner
/branding/custom/welcome.html  # welcome / sample text on the home page
/branding/name.txt             # server name shown in the navbar
```

To customise, mount a host directory (same layout) over `/branding` — uncomment the
`volumes` block on the `fhir` service in `docker-compose.yml` and set `BRANDING_DIR`,
or with plain Docker:

```bash
docker run -v /path/to/branding:/branding:ro …
```

The name can also be set with `HAPI_FHIR_TESTER_HOME_NAME`; the content path with
`HAPI_FHIR_CUSTOM_CONTENT_PATH` (defaults to the mounted `/branding`).

## Terminology

Hibernate Search (Lucene) is enabled in `fhir-server/application.yaml` so the
terminology service can expand ValueSets (`$expand`) and validate coded values.
The index directory defaults to `/tmp/lucenefiles` (override with `HSEARCH_DIR`).
Value sets are pre-expanded at IG install time, so codes are available without
loading external terminologies like SNOMED (only sets that *filter* an unloaded
system, such as full SNOMED subsets, can't be expanded).

## Testing

Integration tests load the [CH EMR IG](https://hl7ch.github.io/ch-emr) and assert
that the IG loads and profile validation rejects an invalid resource. The test
logic is provider-agnostic; there are two entrypoints.

**Locally, inside a multipass VM (podman):**

```bash
./tests/multipass.sh          # creates the VM if missing, installs podman, runs everything
```

**In CI** (`.github/workflows/ci.yml`) the same `tests/provision.sh` + `tests/run-tests.sh`
run directly on the runner with podman.

To run the assertions against an already-running stack:

```bash
./tests/provision.sh          # build + up + wait (COMPOSE=podman-compose|docker compose)
./tests/run-tests.sh          # FHIR_BASE configurable
```

## Repository layout

```
build.sh                 # builds the versioned FHIR image
docker-compose.yml       # db + fhir
fhir-server/             # Dockerfile, entrypoint (IG_URLS expansion), application.yaml
tests/                   # provision.sh, run-tests.sh, multipass.sh
.github/workflows/ci.yml
```
