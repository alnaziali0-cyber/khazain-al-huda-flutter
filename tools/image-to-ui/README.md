# README — tools/image-to-ui

The optional external half of the Khazain Al-Huda Image→UI engine.

The **in-app** engine (`apps/mobile/lib/devpanel/image_to_ui/extractor.dart`)
extracts colours, a type-scale estimate and a grid estimate from a reference
image **on the device**, maps every colour to the nearest existing design
token (ΔE < 6 updates the token, otherwise a new token is proposed) and emits
a `UIPatch` that the developer panel applies with undo.

This CLI does the same extraction **outside the phone** and writes the patch
as JSON, which is useful for CI, design review and bulk presets. It has no
third-party dependencies — the PNG decoder below uses `zlib` from the
standard library.

## Usage

```bash
python3 tools/image-to-ui/image_to_ui.py reference.png \
    --tokens apps/mobile/lib/design/tokens/app_tokens.dart \
    --out patch.json \
    --report report.json
```

* `--tokens` — the Dart token file whose palette is matched (default:
  `apps/mobile/lib/design/tokens/app_tokens.dart`).
* `--out` — where the `UIPatch` JSON is written (default `patch.json`).
* `--report` — optional raw analysis report (clusters, weights, ΔE values).

## Output

```json
{
  "version": 1,
  "tokens": {
    "colors": { "green": "#174940" },
    "typography": { "display": { "size": 26.0, "weight": 700, "lineHeight": 1.35, "family": "NotoNaskhArabicUI" } },
    "grid": { "columns": 4.0, "gutter": 0.35, "sidePadding": 16.0, "tileAspect": 1.0 }
  }
}
```

The document is accepted verbatim by
`DevStoreController.applyPatch(UIPatch)` — the same entry point the in-app
panel uses — so a CLI-generated patch and a device-generated patch are the
same artefact.

## Honest scope

The pipeline extracts **colour, typography and grid hints** and maps them onto
the existing token set. It does not generate Dart/Flutter source code for the
reconstructed layout: the relative layout tree (`LayoutNode`) remains a
developer-panel structure, and the screens themselves are hand-built.
