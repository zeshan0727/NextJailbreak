"""Refresh legacy v1.3 assertions for v1.4 descriptive names and review status."""
from pathlib import Path
replacements = {
  'tests/test_ai_intake.py': [
    ("'Barjous_INV-9902_2026-10-19.txt'", "'Barjous_Invoice_Acme-invoice_INV-9902_2026-10-19.txt'"),
    ("'Barjous_INV-47471_2026-10-19.png'", "'Barjous_Invoice_INV-47471_2026-10-19.png'"),
  ],
  'tests/test_core.py': [
    ('self.assertEqual(item["status"], "filed")', 'self.assertEqual(item["status"], "review")'),
    ('"Barjous_INV-0140_2026-09-10.txt"', '"Barjous_Invoice_INV-0140_2026-09-10.txt"'),
  ],
}
for filename, changes in replacements.items():
    path = Path(__file__).resolve().parent / filename
    source = path.read_text(encoding='utf-8')
    for before, after in changes:
        count = source.count(before)
        if count != 1:
            raise RuntimeError(f'Expected exactly one old assertion {filename}: {before}; found {count}')
        source = source.replace(before, after)
    path.write_text(source, encoding='utf-8')
print('Legacy v1.3 tests updated to v1.4 behavior.')
