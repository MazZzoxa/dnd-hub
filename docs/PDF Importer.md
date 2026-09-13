# PDF Importer

## Current implementation (AcroForm)

The PDF importer currently uses **AcroForm only** as its source extraction mechanism:

```text
PDF
 └─ AcroForm extractor → semantic field mapping → import draft → CharacterModel
```

### Supported PDF shapes

- Interactive AcroForm character sheets with populated text fields.
- AcroForm checkbox fields whose semantic names identify the corresponding proficiency/boolean value.
- Attack fields using explicit `Wpn Name`, `Wpn Name 2`, `Wpn Name 3`, `Wpn1 AtkBonus`, `Wpn2 Damage`, etc. naming variants.
- Spell fields with an explicit level in the field name.
- Generated spell fields such as `Spells 1014`, `Spells 1023`, `Spells 1046`, etc. are supported by their AcroForm field-id ranges; these ranges map to spell levels 0–9 without using page coordinates.

### Current behavior

- Field values are extracted locally with `syncfusion_flutter_pdf`.
- Field matching uses field `name` and `mappingName` only.
- PDF page geometry is not used for semantic mapping.
- OCR is a separate future extractor for image-only/scanned PDFs and is not part of this AcroForm path.
- Documents without readable AcroForm fields fail explicitly instead of being guessed from visual layout.
- Long equipment/feature blocks remain source text and are not yet split into individual `ItemModel`/ability records.

### Known limitations

- Checkbox fields without semantic names cannot be reliably mapped; they are intentionally ignored.
- For generated spell fields whose names follow the known interactive-sheet numbering scheme, spell level is recovered from the field name alone. Unknown spell naming schemes are not guessed.
- Some PDFs expose fields only through non-text widgets or unusual AcroForm structures outside the current extractor's supported field types.

## Architecture boundary

The PDF importer follows this boundary:

```text
PDF
 ↓
AcroForm extraction
 ↓
Semantic mapping
 ↓
CharacterImportDraft
 ↓
Validation / preview
 ↓
CharacterModel
```

The parser is intentionally **source-specific only at the extraction boundary**. Semantic aliases remain independent from any one PDF template.

## Next steps

1. Add a dedicated import preview showing field values and confidence/issues.
2. Expand semantic field dictionaries for more AcroForm character-sheet variants.
3. Improve support for explicitly named proficiency and checkbox fields.
4. Add structured parsing for equipment and feature blocks exposed as AcroForm text fields.
5. Add OCR as a separate source extractor for image-only PDFs.
6. ~~Add URL importer over the same semantic-draft layer.~~ Done — see below.

## URL importer (`data/import/url/`)

`UrlImporter` implements "Импорт по ссылке" (docs/D&D Hub.md, п.25): the user
pastes one URL; there are no per-site buttons. It fetches the URL and
classifies the response, in order:

1. **Direct PDF link** — bytes start with `%PDF` → handed to the existing
   `PdfImporter.parseAdaptive`, unchanged.
2. **D&D Hub's own JSON export** (`schema: "dnd-hub"`) → handed to
   `ImportManager`'s existing JSON pipeline, unchanged.
3. **Character-shaped JSON**, either as the whole response or embedded in an
   HTML page's inline script data (`__NEXT_DATA__`, `__NUXT__`,
   `__INITIAL_STATE__`, or a generic `application/json` script block) →
   mapped via `GenericCharacterExtractor`, an alias-based mapper analogous to
   the AcroForm field-alias matching above, producing the same
   `PdfImportDraft`.

Anything else fails explicitly (`UrlImportException`) rather than guessing,
matching the "fail rather than guess" rule already used for unreadable
AcroForm PDFs.

## Remote character-sheet importer

The URL import layer contains a dedicated character-sheet adapter for a supported remote sheet format. It reads the sheet UUID and CSRF token from the page, follows redirects while preserving cookies, requests the structured character data, and maps the resulting tree into the common `PdfImportDraft` model.

The adapter is kept separate from the generic URL extractor because its data contract is structured and deterministic rather than heuristic.

## URL importer known limitation — generic (non-remote sheet service) sites

`GenericCharacterExtractor` (the fallback for URLs that aren't remote sheet service and
aren't D&D Hub's own JSON/PDF formats) is alias-based guessing, written
without a captured real-world sample to test against. Treat it as unverified
until it's been run against a real third-party URL. If it fails to detect a
character, or detects one with wrong/missing fields, capture the actual JSON
the site returns (browser dev tools → Network tab) and extend the alias
lists in `generic_character_extractor.dart` accordingly.
