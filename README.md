# DigiSanté FHIR Test Kit

A disposable, versioned HAPI FHIR server bundled with two web UIs:

1. **Generic tester** — the built-in HAPI UI (a clone of [hapi.fhir.org](https://hapi.fhir.org/)) for unrestricted CRUD, served by the FHIR server itself.
2. **Per-IG profile UI** — a custom single-page app that generates, for every installed Implementation Guide, profile-restricted CRUD pages with form validation driven by each profile's `StructureDefinition` (cardinality, datatypes, bindings, slicing, extensions) and backed by the server's `$validate` operation.

Implementation Guides are loaded into the server **from a URL at container startup**.

## Architecture

| Service | Image | Port | Purpose |
| --- | --- | --- | --- |
| `db` | `postgres:16-alpine` | — | Persistence |
| `fhir` | `…-hapi-<HAPI_VERSION>:<IMAGE_VERSION>` (from `hapiproject/hapi`) | 8080 | FHIR REST API + generic tester |
| `ui` | `…-ui:<IMAGE_VERSION>` (`nginx:alpine`) | 8888 | Custom per-IG profile UI; reverse-proxies `/fhir` to the server |

> **Base-image note:** the FHIR image is built `FROM hapiproject/hapi:<version>`, which is a distroless/Debian image — *not* Alpine. The UI image is Alpine-based (`node:alpine` build → `nginx:alpine`). To make the FHIR image Alpine too, switch to a from-source multi-stage build.

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
./build.sh                    # builds both images
docker compose up -d          # or: podman compose up -d
```

- Generic tester + API: <http://localhost:8080>
- Per-IG profile UI: <http://localhost:8888>

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

## The per-IG profile UI

- The home page lists installed IGs (discovered from `ImplementationGuide` resources, or grouped by their canonical base — e.g. `http://fhir.ch/ig/ch-emr` — as a fallback, since HAPI does not persist `ImplementationGuide` resources for installed packages).
- Each IG has a page listing its profiles; each profile has a CRUD page.
- Properties are **collapsible** (`<details>`), collapsed by default at the top level.
- Forms are generated from the profile's snapshot: required/repeating fields follow `min..max` (e.g. a `HumanName 1..1` renders exactly one required name); **optional elements and slices are added on demand via "+ Add"** (so a `0..1` slice like a Device's `mriSafety` is opt-in); `fixed`/`pattern` values are prefilled/locked; slices and extensions render as constrained groups.
- **Bound codes are selectable from their value set.** The server's terminology service expands the value set (`ValueSet/$expand`) to populate a dropdown. If a set can't be expanded (e.g. a SNOMED-filter set with no loaded code system), the field falls back to the value set's `compose` — explicit codes as a dropdown, or the single coding system pre-filled for manual code entry.
- **Validate** runs client-side cardinality checks plus the server's `$validate` against the profile and shows the `OperationOutcome`. **Create/Update** is blocked on profile-validation errors.

> Terminology expansion requires the server's Hibernate Search (Lucene) index, which is enabled in `fhir-server/application.yaml`. The index directory defaults to `/tmp/lucenefiles` (override with `HSEARCH_DIR`). Value sets are pre-expanded at IG install time, so codes are available without loading external terminologies like SNOMED (only sets that *filter* an unloaded system, such as full SNOMED subsets, can't be expanded).

## Testing

Integration tests load the [CH EMR IG](https://hl7ch.github.io/ch-emr) and assert that
the IG loads, profile validation rejects an invalid resource, and the UI serves and
proxies the API. The test logic is provider-agnostic; there are two entrypoints.

**Locally, inside a multipass VM (podman):**

```bash
./tests/multipass.sh          # creates the VM if missing, installs podman, runs everything
```

**In CI** (`.github/workflows/ci.yml`) the same `tests/provision.sh` + `tests/run-tests.sh`
run directly on the runner with podman.

To run the assertions against an already-running stack:

```bash
./tests/provision.sh          # build + up + wait (COMPOSE=podman-compose|docker compose)
./tests/run-tests.sh          # FHIR_BASE / UI_BASE configurable
```

## Repository layout

```
build.sh                 # builds versioned images
docker-compose.yml       # db + fhir + ui
fhir-server/             # Dockerfile, entrypoint (IG_URLS expansion), application.yaml
ui/                      # Vite + TypeScript SPA, nginx Dockerfile/conf
tests/                   # provision.sh, run-tests.sh, multipass.sh
.github/workflows/ci.yml
```
