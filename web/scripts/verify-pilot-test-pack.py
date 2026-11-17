"""Check generated workbook XML, source templates, references and package bytes."""
from pathlib import Path
import csv
import io
import json
import re
import zipfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
folder = root / "public/templates/pilot-testing-2026-11-17-v2"
cases = json.loads((folder / "test-cases.json").read_text(encoding="utf-8"))
assert len(cases) == 84 and len({c["id"] for c in cases}) == 84
ids = {c["id"] for c in cases}
for case in cases:
    for reference in re.findall(r"(?:SET|REC|MOV|BUY|FIN|ACC|SAFE|UX)-\d{2}", case["prerequisite"]):
        assert reference in ids, reference
ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
with zipfile.ZipFile(folder / "ProfitPlate-Full-Test-Sheet-v2.xlsx") as book:
    assert book.testzip() is None
    assert not any("vbaProject" in name or "externalLinks" in name for name in book.namelist())
    for name in book.namelist():
        if name.endswith((".xml", ".rels")):
            ET.fromstring(book.read(name))
    workbook = ET.fromstring(book.read("xl/workbook.xml"))
    sheets = workbook.findall("m:sheets/m:sheet", ns)
    assert len(sheets) == 16
    assert len({s.attrib["name"] for s in sheets}) == 16
    not_run = 0
    for index, spec in enumerate(sheets, 1):
        sheet = ET.fromstring(book.read(f"xl/worksheets/sheet{index}.xml"))
        rows = sheet.findall("m:sheetData/m:row", ns)
        assert all(float(row.attrib.get("ht", "22")) <= 409 for row in rows)
        if re.match(r"^[1-8] ", spec.attrib["name"]):
            entries = sheet.findall("m:sheetData/m:row", ns)[3:]
            expected = [c for c in cases if c["sheet"] == spec.attrib["name"]]
            assert len(entries) == len(expected)
            for row, case in zip(entries, expected):
                cells = row.findall("m:c", ns)
                assert "".join(cells[0].itertext()) == case["id"]
                status = next(c for c in cells if c.attrib["r"].startswith("I"))
                assert "".join(status.itertext()) == "Not run"
                assert len(cells) == 13
                not_run += 1
            assert sheet.find("m:dataValidations/m:dataValidation", ns) is not None
    assert not_run == 84
for name, official in [("example-initial-prices.csv", "initial-material-prices.csv"), ("example-sales.csv", "sales-import.csv"), ("example-expenses.csv", "expense-import.csv")]:
    rows = list(csv.reader(io.StringIO((folder / name).read_text(encoding="utf-8-sig"))))
    headers = next(csv.reader(io.StringIO((root / "public/templates" / official).read_text(encoding="utf-8-sig"))))
    assert rows[0] == headers
    assert all(len(r) == len(headers) for r in rows)
    assert "TEST_DATE" in (folder / name).read_text(encoding="utf-8-sig")
pdf = (folder / "Full-Test-Guide.pdf").read_bytes()
assert pdf.startswith(b"%PDF-") and len(pdf) > 10000
archive = folder.parent / "profitplate-full-test-pack-2026-11-17-v2.zip"
files = sorted(p for p in folder.iterdir() if p.is_file())
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as pack:
    for file in files:
        pack.write(file, file.name)
with zipfile.ZipFile(archive) as pack:
    assert pack.testzip() is None and len(pack.namelist()) == len(files)
    for file in files:
        assert pack.read(file.name) == file.read_bytes()
print("Verified 16 workbook sheets, 84 Not run cases, case references, CSV header/column contracts, PDF and complete ZIP contents.")
