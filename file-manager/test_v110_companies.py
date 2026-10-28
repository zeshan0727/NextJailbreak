"""Regression tests: deleting a company must never erase documents."""
from pathlib import Path
import tempfile
import unittest
from filemanager.core import FileManagerCore

class CompanyDeletionTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.core=FileManagerCore(self.root/'library',seed_companies=False)
        self.addCleanup(self.core.close)
        self.cid=self.core.add_company('Stone Café','stone')
        self.other=self.core.add_company('Graphitees WLL','graphitees')
        p=self.root/'Stone invoice.txt'
        p.write_text('Stone Cafe payment voucher office invoice 2026')
        self.doc=self.core.import_file(p,ai=lambda *_:{
            'company_id':self.cid,'category':'Invoices & Bills','confidence':.99,'needs_review':False})
        self.assertEqual(self.doc['status'],'filed')

    def test_archive_keeps_managed_file_and_search(self):
        before=self.core.document(self.doc['id'])
        f=Path(before['absolute_path'])
        payload=f.read_bytes()
        self.core.archive_company(self.cid)
        self.assertEqual([x['name'] for x in self.core.companies()],['Graphitees WLL'])
        self.assertEqual(self.core.archived_companies()[0]['file_count'],1)
        after=self.core.document(self.doc['id'])
        self.assertEqual(after['company_name'],'Stone Café')
        self.assertEqual(after['relative_path'],before['relative_path'])
        self.assertEqual(f.read_bytes(),payload)
        self.assertTrue(self.core.search('Stone invoice'))
        self.assertEqual(self.core.summary()['total'],1)

    def test_restore_after_restart(self):
        self.core.archive_company(self.cid)
        self.core.close()
        self.core=FileManagerCore(self.root/'library',seed_companies=False)
        self.assertNotIn('Stone Café',[x['name'] for x in self.core.companies()])
        self.core.restore_company(self.cid)
        self.assertIn('Stone Café',[x['name'] for x in self.core.companies()])
        self.assertEqual(self.core.document(self.doc['id'])['state'],'filed')

    def test_delete_empty_and_restore(self):
        self.core.archive_company(self.other)
        self.assertEqual(len(self.core.archived_companies()),1)
        self.core.restore_company(self.other)
        self.assertEqual(len(self.core.companies()),2)

    def test_existing_name_cannot_be_recreated(self):
        self.core.archive_company(self.cid)
        with self.assertRaises(ValueError):self.core.add_company('Stone Café','stone')

    def test_invalid_and_repeated_archive(self):
        with self.assertRaises(ValueError):self.core.archive_company(99999)
        self.core.archive_company(self.cid)
        with self.assertRaises(ValueError):self.core.archive_company(self.cid)
        self.core.restore_company(self.cid)
        with self.assertRaises(ValueError):self.core.restore_company(self.cid)

    def test_schema_upgrades_in_place(self):
        cols=[r['name'] for r in self.core.conn.execute('PRAGMA table_info(companies)')]
        self.assertIn('archived_at',cols)

if __name__=='__main__':unittest.main()
