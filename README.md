# Parqs: Parquet as OCI images

_Open data you can query, verify, and mirror on any OCI registry._

The goal is to make the authoritative source of the data the easiest source to use. 

We have to make it much less expensive to [refute bullshit](https://en.wikipedia.org/wiki/Brandolini%27s_law), 
and much easier to publish insights from open data in a way that anyone can check with a single command.

## Patterns not platforms

There are two ideas here. Adopting either is a win.
- Publish open data in any format as an OCI image. Normalising the shape of the distribution channel so generic tools can fetch and verify any release.
- Publish open data as Parquet. It's a better CSV with typed columns you don't have to guess from the values, designed to be easy to query. Open data should aim to be queried more often than it is published. For many datasets this is not yet true.

A parq is a set of parquet files published as an OCI image: one Parquet file per table, each a layer, named by its
digest, with the publisher's original wild source files saved as an image of their own. 

Anything that can write Parquet and push to an OCI registry can make one. Anything that can read Parquet can use it. Join across open datasets over http in a single query.

## Example

Every organisation in NHS England's Organisation Data Service, read from the registry by its digest:

```console
$ duckdb -c "SELECT status, count(*) AS organisations
  FROM read_parquet('https://ods.fyi/v2/ods-data/blobs/sha256:2cd9c8924ab419845c5f1426997af8eabeac9c9579d6e09cbf13380d21826651')
  GROUP BY 1 ORDER BY 1"
┌──────────┬───────────────┐
│  status  │ organisations │
│ varchar  │     int64     │
├──────────┼───────────────┤
│ active   │        217091 │
│ inactive │        154478 │
└──────────┴───────────────┘
```

## Why?

Open datasets are often published on bespoke download sites. They move, change and disappear. 
There's no standard way to say which file you used, or verify you got the same one a second time.

OCI registries solve that for software. A container image is content-addressed, mirrored,
cached, signed, and served by standard infrastructure already in use at scale by docker and homebrew.

Parq reuses those standard registries for publishing data: an OCI image layer for each parquet file, stored in any registry, fetched over http by the hash of its bytes.

- Parquet allows efficient querying via http range requests and SQL
- OCI registries can be implemented as flat file layouts, serve image layers by their hash, and already work at scale.

The properties knit together to let us run queries that join **across** open datasets in milliseconds,
that can be automatically verified.

## The shape of a parq

The **source** image is the publisher's files in the original format, to get them a stable content-address.

The **parquet** image holds the tables derived from the source image.

```bash
# source image
https://ghcr.io/parq-fyi/gp-regions-source:2026-09-10    # a source saved from the wild
└── gp-reg-pat-prac-quin-age.zip                         # the source file as published

# parquet image
https://ghcr.io/parq-fyi/gp-regions:2026-09-10           # the derived parquet image
└── regions.parquet                                      # one layer per table
```

- Each parquet _file_ points to the hash of the source _file_, stored in the parquet metadata.
- The parquet image manifest points to the hash of the source image manifest it was derived from, stored in the standard `base.digest` annotation, the same way a container image names the image it was built on.

Files point to files. Images point to images.

The parquet files should be deterministically derived from the source file so anyone can verify your work.

The image manifest is a small json file that you can annotate freely so others can find your work.

## What a parq can tell you

A parq gives you claims you can verify about the dataset.

| Claim | Feature | Check |
| :--- | :--- | :--- |
| **Traceable** | `base.digest` identifies the source image. Each parquet holds the source file hash it was made from. | Pull the source image. Compare the layer hashes |
| **Reproducible** | `source` and `revision` annotations naming the git repository and commit that hold its recipe | Run the recipe. Compare the output hashes |
| **Attested** | A public [sigstore] record of how the image was built | Check the signature and its subjects |

## Using parqs

- **Reuse existing ones freely.** Query them over http, save them locally, join across them with wild abandon.
- **Keep your own copy if you depend on it.** Copy the parquet image (`oras cp -r`, which brings its attestation) and the source image its `base.name` names. A copy keeps its original's references, so it says where it came from, and the registry keeps every blob a manifest names, so it can't vanish under you.
- **Create your own.** Save the wild sources you care about. Anyone can wrap a source in an OCI image.

## Making parqs

You can make one with existing tools. [`example.sh`](example.sh) makes a one-table
parq from NHS England's GP registrations with DuckDB, `oras`, `jq` and `curl`, in a few lines of bash. 

It saves the publisher's zip as a source image, writes a table with the licence and the zip's hash inside,
and pushes the table as a parquet image that names its source. We run it to test this spec, and it made
every example below. The [`Dockerfile`](Dockerfile) runs the same script with each tool pinned by checksum:
run either way, it makes the same table.

Or use `parq`, the tool we're building alongside this spec, to do each step for you and check the result.

## Specification

The key words **MUST**, **SHOULD** and **MAY** mean what [RFC 2119][rfc2119] says, and only in capitals,
as [RFC 8174][rfc8174] clarifies. The `v1` in each `artifactType` names this version.

A parq makes a [claim](#what-a-parq-can-tell-you) by carrying its feature: `base.digest` for traceable,
`revision` for reproducible, and an attached signature for attested. Each claim is defined below, and a
parq that makes one **MUST** meet its definition. Each section ends with what `example.sh` made, published
at `ghcr.io/parq-fyi`.

### The source image

- It **MUST** be an [OCI image manifest][oci-manifest] (image spec v1.1) with the empty config, whose only
  layers are the publisher's files, unmodified, each annotated `org.opencontainers.image.title` with its
  file name.
- `artifactType` **MUST** be set, as OCI requires with the empty config, and **SHOULD** be
  `application/vnd.fyi.parq.source.v1`.
- Annotations **SHOULD** be OCI's [standard ones][oci-annotations]: `title` and `version` (the publisher's
  release), `vendor` (the publisher), `url` (the publisher's page for the release), `licenses`, and
  `created`. OCI means `created` to be the build time; here it's when the publisher released it, in UTC,
  as `2026-09-10T00:00:00Z` where they give only a date, so saving the same files again makes the same
  image.
- `source` and `revision` **MAY** name the repository and commit that saved it. Anyone can check a source
  image against the publisher's own files, so the repository needn't be public, or exist at all.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.fyi.parq.source.v1",
  "config": {
    "mediaType": "application/vnd.oci.empty.v1+json",
    "digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    "size": 2
  },
  "layers": [
    {
      "mediaType": "application/zip",
      "digest": "sha256:a707832a2d308f97541e8a2a0654c9322dd9014e8454047897015904eac62f95",
      "size": 1912888,
      "annotations": {
        "org.opencontainers.image.title": "gp-reg-pat-prac-quin-age.zip"
      }
    }
  ],
  "annotations": {
    "org.opencontainers.image.created": "2026-09-10T00:00:00Z",
    "org.opencontainers.image.licenses": "OGL-UK-3.0",
    "org.opencontainers.image.title": "Patients Registered at a GP Practice, September 2026",
    "org.opencontainers.image.url": "https://digital.nhs.uk/data-and-information/publications/statistical/patients-registered-at-a-gp-practice/september-2026",
    "org.opencontainers.image.vendor": "NHS England",
    "org.opencontainers.image.version": "2026-09-10"
  }
}
```

`ghcr.io/parq-fyi/gp-regions-source:2026-09-10`, digest
`sha256:3e640dfadc3dee2fdc7886b6afa48730b8fd6711475ec33f55e8063f20a60d20`.

### The parquet image

- It **MUST** be an OCI image manifest with the empty config, whose only layers are the tables: one
  Parquet file per table, media type `application/vnd.apache.parquet`, annotated
  `org.opencontainers.image.title` with `<table>.parquet`. Table names **MUST** be unique, lowercase
  `a-z`, `0-9` and `_`, starting with a letter.
- `artifactType` **MUST** be set and **SHOULD** be `application/vnd.fyi.parq.v1`. A reader **MAY**
  read any image whose layers are Parquet, whatever its `artifactType`.
- `org.opencontainers.image.base.name` and `org.opencontainers.image.base.digest` **SHOULD** name the source
  image the tables were made from: its full reference, and its manifest digest. Where the tables were read
  from several source images, they name an [OCI image index][oci-index] whose manifests are those images,
  copied into the index's repository, where registries expect an index's images to be.
  That stretches OCI's meaning: OCI expects a base to share the image's first layers, as a `FROM` does,
  and a parquet image shares none. It names the image it was derived from, so tools that treat `base.*` as a
  `FROM`, like `crane rebase`, don't apply.
- It **SHOULD** also set OCI's `created` (the source's `created`, the latest where there are several),
  `licenses` (the tables' licence names joined with ` AND `, left out where one is `NOASSERTION`), and
  `source` and `revision` (the repository and commit that build it). Any other annotation **MAY** be added.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.fyi.parq.v1",
  "config": {
    "mediaType": "application/vnd.oci.empty.v1+json",
    "digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    "size": 2
  },
  "layers": [
    {
      "mediaType": "application/vnd.apache.parquet",
      "digest": "sha256:d393bdd0dd45880fe5d9f64171df01d598e167912b2d9ee596bc45c4d4b6ec5c",
      "size": 798,
      "annotations": {
        "org.opencontainers.image.title": "regions.parquet"
      }
    }
  ],
  "annotations": {
    "org.opencontainers.image.base.digest": "sha256:3e640dfadc3dee2fdc7886b6afa48730b8fd6711475ec33f55e8063f20a60d20",
    "org.opencontainers.image.base.name": "ghcr.io/parq-fyi/gp-regions-source:2026-09-10",
    "org.opencontainers.image.created": "2026-09-10T00:00:00Z",
    "org.opencontainers.image.licenses": "OGL-UK-3.0",
    "org.opencontainers.image.revision": "54c7a7d8e17a0f7db8999b11caa3dc56137c754b",
    "org.opencontainers.image.source": "https://github.com/parq-fyi/spec"
  }
}
```

`ghcr.io/parq-fyi/gp-regions:2026-09-10`, digest
`sha256:e4661fed27c6ebfa849acd1375947b370d8b3be04fc56554e51b46492f24b6dd`, published by this repository's
[workflow](.github/workflows/example.yml) from commit `54c7a7d`.

### The parquet files

- Each file **SHOULD** carry a key-value metadata entry named `datapackage`: a JSON object in the
  [JSON Canonicalization Scheme][jcs], using [Data Package][dp]'s property names, though it isn't a whole
  Data Package. It holds:
  - `licenses`: the licence the publisher states, as entries sorted by `name`. Each `name` is an
    [SPDX][spdx] identifier, `LicenseRef-…` or `NOASSERTION`. Each `path` is the URL of its text:
    `https://spdx.org/licenses/<name>.html` for an SPDX identifier, and the terms' own URL for
    `LicenseRef-…`. `NOASSERTION` has none.
  - `sources`: an entry for each publisher file the table was read from, sorted by `hash`. Its `hash` is
    the file's SHA-256 digest, as `sha256:` and lowercase hex, and its `bytes` is the file's size. Data
    Package defines both on resources; here they describe a source. Empty where nothing upstream was read.
- The entry is part of the table's bytes, so it holds only what changes when they do: no location other
  than where a licence's text lives, and no prose that might be corrected. Those belong beside the
  tables, in the repository. A producer **MAY** add other Data Package properties on those terms, like the
  dataset's `name` and `version`, or a source's `title` and `version`, though each ties the tables to that
  producer's names. A reader **MUST** ignore properties it doesn't know.
- Rows **SHOULD** be in a total order, so the same recipe always writes the same bytes: sorted by every
  column of the table's primary key, or by all its columns where it has none. Lead with the column people
  filter on most, even if it isn't in the key: Parquet readers skip any row group whose minimum and
  maximum for it can't match, so a sorted lookup reads a fraction of the file.

```console
$ duckdb -list -noheader -c "SELECT decode(value) FROM parquet_kv_metadata('regions.parquet') WHERE decode(key) = 'datapackage'"
{"licenses":[{"name":"OGL-UK-3.0","path":"https://spdx.org/licenses/OGL-UK-3.0.html"}],"sources":[{"bytes":1912888,"hash":"sha256:a707832a2d308f97541e8a2a0654c9322dd9014e8454047897015904eac62f95"}]}
```

`regions` is sorted by `region_code`, its primary key.

### Tracing

- A parq is **traceable** when its tables lead back to the publisher's files: `base.name` and
  `base.digest` name its source, every table carries a `datapackage` entry, at least one table names a
  source file, and each `hash` in `sources` is a layer of the image `base.digest` names, or of one of its
  images where it's an index, with that layer's size as `bytes`.
- A checker fetches `base.digest` from `base.name`'s repository. The digest is what must match, so the tag
  may since have moved, and a checker **MAY** look for the same digest in any registry it trusts, like the
  one beside the parquet image.

```console
$ oras manifest fetch ghcr.io/parq-fyi/gp-regions-source@sha256:3e640dfadc3dee2fdc7886b6afa48730b8fd6711475ec33f55e8063f20a60d20 | jq -r '.layers[].digest'
sha256:a707832a2d308f97541e8a2a0654c9322dd9014e8454047897015904eac62f95
```

### Reproducing

- The files are shared; the packaging is yours. A rebuild reproduces a parq when its tables have the same
  digests as the parquet image's layers, whatever its manifests say.
- A parq is **reproducible** when the parquet image's `org.opencontainers.image.source` and
  `org.opencontainers.image.revision` name a git repository and a commit in it that holds the recipe, with
  instructions for running it and the versions of the tools it runs: another Parquet writer, or another
  version of one, can make different bytes from the same rows. The recipe is the producing tool's own.
- The recipe **SHOULD** read the publisher's files from the source image, by `base.digest`, so a rebuild
  still works once the publisher has moved them.
- A producer **SHOULD** take every annotation from the source and the recipe, never from the build's
  machine or clock, so they can rebuild their own manifests exactly too. Set `created` yourself: `oras
  push`, for one, stamps the current time if you don't.
- The repository **MAY** hold a `Dockerfile` that runs the recipe with its tools pinned, so people and
  tools have a standard way to run it. Running the recipe both directly and through the `Dockerfile` is a
  good test: the tables should match.
- The repository **SHOULD** say where its images are published, so people and agents can find them from
  it.

`example.sh` has made `regions.parquet` as
`sha256:d393bdd0dd45880fe5d9f64171df01d598e167912b2d9ee596bc45c4d4b6ec5c` every time it's run: directly on
macOS and on GitHub's Linux runner, and through its `Dockerfile` on both. Its manifests differed only where
they name a registry or a commit. Given a registry that already holds the source image, copied in with
`oras cp`, it rebuilds without the publisher's URL.

### Attesting

- A parq is **attested** when a [Sigstore][sigstore] bundle, a signed statement of how the dataset was
  built, is attached to the parquet image as an OCI referrer, with the bundle's media type
  (`application/vnd.dev.sigstore.bundle.v0.3+json`) as its `artifactType` and as its one layer's. Its
  subjects **MUST** include the parquet image's manifest digest, and **SHOULD** include every table, so a table
  can be checked on its own.
- Checking a signature means checking who signed it. Where the signing identity names a repository and a
  commit, they **MUST** be the parquet image's `source` and `revision`.

The workflow signs the image and its table together, then attaches the bundle:

```console
$ gh attestation verify oci://ghcr.io/parq-fyi/gp-regions:2026-09-10 --bundle-from-oci --owner parq-fyi --format json \
    | jq -r '.[].verificationResult | (.statement.subject[] | .digest.sha256 + "  " + .name), .signature.certificate.sourceRepositoryDigest'
e4661fed27c6ebfa849acd1375947b370d8b3be04fc56554e51b46492f24b6dd  ghcr.io/parq-fyi/gp-regions
d393bdd0dd45880fe5d9f64171df01d598e167912b2d9ee596bc45c4d4b6ec5c  regions.parquet
54c7a7d8e17a0f7db8999b11caa3dc56137c754b
$ gh attestation verify regions.parquet --owner parq-fyi --format json --jq '.[].verificationResult.signature.certificate.subjectAlternativeName'
https://github.com/parq-fyi/spec/.github/workflows/example.yml@refs/heads/main
https://github.com/parq-fyi/spec/.github/workflows/example.yml@refs/heads/main
```

The signed commit is the parquet image's `revision`. The table checks out on its own, with a record from
each run that made it.

## Naming

The spec doesn't require names. As a guide:

- A publisher names their source images as they like.
- Name a parquet image after what it holds, `<namespace>/<dataset name>`. Where you save a source yourself,
  name it `<dataset name>-source`, beside the parquet image: every registry accepts `<namespace>/<name>`, and
  some, Docker Hub among them, accept nothing deeper.
- Tag both with the publisher's version, plus a revision of your own when you rebuild the dataset from the
  same release (ods-data's are like `2026-09-25_0.2.0`), so tags line up and sort by date.
- `base.name` links the two, so nobody has to guess one name from the other.

## Not yet specified

- **Joins to other parqs:** how a dataset recommends joining one of its columns to another parq.
- **Discovery:** how people find parqs they don't already know about, and a list tools can read of what a
  repository has published, each release pointing to the next.
- **Signing outside CI,** and where a publisher's key lives.
- **Rebuild records:** signed statements from people who rebuilt a parq and got the same tables, so a
  parq can show it was reproduced, not just say how.
- **Registry-only publishing:** the recipe attached to the parquet image, so a registry alone holds the
  whole publication. It needs a recipe any tool can run, so anyone can rebuild and check it.
- **Descriptions:** what the columns mean, keys between tables, a README. For now they're the producing
  tool's to write; `parq` writes a [Data Package][dp] `datapackage.json`.
- **A publisher's own parqs:** a parq with no base reads the same whether it's a publisher's own data or
  one nobody traced. How to tell them apart, without seeming to rate a publisher's own lower, is open.

## Licence

The spec's text is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `example.sh`,
the `Dockerfile` and the workflow that runs them are licensed under [MIT](LICENSE).


`░▒▓█ parquets & recommendations`


[rfc2119]: https://www.rfc-editor.org/rfc/rfc2119
[rfc8174]: https://www.rfc-editor.org/rfc/rfc8174
[oci-manifest]: https://github.com/opencontainers/image-spec/blob/main/manifest.md
[oci-annotations]: https://github.com/opencontainers/image-spec/blob/main/annotations.md
[oci-index]: https://github.com/opencontainers/image-spec/blob/main/image-index.md
[dp]: https://datapackage.org/standard/data-package/
[jcs]: https://www.rfc-editor.org/rfc/rfc8785
[spdx]: https://spdx.org/licenses/
[sigstore]: https://www.sigstore.dev/
