# StockCheck

**Your system says five. The shelf says four. Find the difference.**

An offline inventory reconciliation tool written in Haskell. Compare a stock-system export with a physical count and get a sorted CSV report with shortages, overages, missing counts and unknown SKUs.

No network calls, API keys, accounts or paid services. Sample data is fictional. This is a command-line project, not a hosted website.

## Quick start

Requires GHC 8.8 or newer with the standard `base`, `containers` and `directory` packages.

```sh
ghc -O2 -Wall -Werror Main.hs -o stockcheck
./stockcheck expected.csv counted.csv --output report.csv
```

Or with Cabal:

```sh
cabal build --offline
cabal run --offline stockcheck -- expected.csv counted.csv --output report.csv
cabal test --offline
```

If your package index is not initialized, use the direct GHC command above. No third-party package download is needed for that route.

CSV goes to standard output when `--output` is omitted. A readable summary always goes to standard error. Existing output files and input files are not overwritten. Choose a fresh report filename for each run. Do not run simultaneous processes writing the same output path.

## Input files

`expected.csv`:

```csv
sku,name,quantity,unit_price
FRIDGE-01,Double Door Refrigerator,5,24999.50
FAN-02,Ceiling Fan,12,1599.00
TV-03,Smart TV,3,32999.00
IRON-04,Steam Iron,8,1299.25
```

`counted.csv`:

```csv
sku,quantity
FRIDGE-01,4
FAN-02,12
IRON-04,9
EXTRA-05,2
```

Column order can vary. Additional columns are allowed. Header names are case-sensitive. Outer spaces in headers, SKUs and numeric fields are trimmed. SKUs remain case-sensitive; `abc` and `ABC` are different. Names preserve their original text, including Malayalam.

- Quantities: non-negative whole numbers only.
- Prices: non-negative decimal values with at most two decimal places, no currency symbols or thousands separators.
- All prices must use one currency with two decimal places. No currency conversion or tax calculation is performed.
- One row per SKU in each file. Duplicate SKUs are rejected, not silently combined.
- Use an explicit count of `0` for an item that was checked and not found. An absent row means it has **not been counted**.
- CSV supports UTF-8 BOM, quoted commas, doubled quotes, quoted newlines and LF/CRLF endings. Malformed quoting, blank records and inconsistent row widths fail validation.

## Results

| Status | Meaning |
| --- | --- |
| `MATCH` | Explicit count equals expected quantity |
| `SHORTAGE` | Count is below expected quantity |
| `OVERAGE` | Count is above expected quantity |
| `NOT_COUNTED` | Known SKU has no physical-count row |
| `UNKNOWN_SKU` | Counted SKU does not exist in expected stock |

`delta_qty = counted_qty - expected_qty`

`variance_value = delta_qty * unit_price`

Money uses arbitrary-precision integer minor units, not floating-point arithmetic. The included example produces a known-price net variance of **-23700.25**. Missing counts and unknown SKUs are excluded from this total, and their counts are shown separately. An unknown SKU has no trusted price, so its value stays blank rather than becoming zero.

The net total can hide offsetting shortages and overages. Review individual rows, not only the total. This tool does not change your stock system or make accounting entries.

## Tests

```sh
ghc -Wall -Werror Test.hs -o stockcheck-tests
./stockcheck-tests
```

28 automated checks cover CSV edge cases, all reconciliation statuses, invalid data, Unicode, exact large-integer arithmetic and CSV round trips. The source was compiled and tested with GHC 8.8.4. CLI checks also verified the sample report, missing-file errors and refusal to overwrite inputs or existing reports.

## Data safety and limits

- Files stay on the computer running the command. No telemetry or uploads.
- Input is read into memory, so this is intended for ordinary shop-sized CSV exports, not multi-gigabyte datasets.
- Only whole-unit inventory is supported. Weighted goods and fractional quantities are rejected.
- Open reports as text, or import text columns explicitly as text in a spreadsheet. Untrusted product names or SKUs can contain spreadsheet formula syntax; CSV quoting does not neutralize formulas.
- No database, barcode scanning, automatic ERP import, valuation for unknown items or graphical interface is included.

## License

MIT License. Copyright (c) 2026 shamilhabeebnelli. See [LICENSE](LICENSE). The license covers this original code and documentation. It does not grant trademark rights or override licenses on separately installed dependencies or imported third-party content.
