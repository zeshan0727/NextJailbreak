"""Regression tests for valid manual filenames on existing images."""
import tempfile
import unittest
from pathlib import Path
from filemanager.core import FileManagerCore
from filemanager.repair import _normalize_manual_filename, manual_repair_proposal, apply_repair, undo_last_repair

class ManualNameV17Tests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root=Path(self.tmp.name)
        self.core=FileManagerCore(root/'library',seed_companies=False)
        self.addCleanup(self.core.close)
        self.cid=self.core.add_company('Stone Café','stone')
        original=root/'WhatsApp Image 2026-10-27.jpeg'
        original.write_bytes(b'sample image data')
        self.doc_id=self.core.import_file(original,ai=lambda *_:{
            'company_id':None,'category':'Other','confidence':0,
            'needs_review':True,'reason':'unidentified'})['id']
    def test_regular_name_with_extension(self):
        p=manual_repair_proposal(self.core,self.doc_id,self.cid,'Payroll','Staff Incentives.jpeg')
        self.assertEqual(p['new_name'],'Staff Incentives.jpeg')
        o=apply_repair(self.core,p)
        self.assertEqual(o['status'],'updated')
        self.assertEqual(self.core.document(self.doc_id)['title'],'Staff Incentives.jpeg')
        self.assertEqual(self.core.document(self.doc_id)['state'],'filed')
        self.assertTrue(self.core.search('WhatsApp Image 2026-10-27'))
        undo_last_repair(self.core,self.doc_id)
        self.assertEqual(self.core.document(self.doc_id)['state'],'review')
    def test_extension_auto_add_and_dedup(self):
        for s in ('Staff Incentives','Staff Incentives.jpeg.jpeg'):
            self.assertEqual(_normalize_manual_filename(s,'.jpeg'),'Staff Incentives.jpeg')
    def test_reject_malicious_or_wrong_extension(self):
        before=self.core.document(self.doc_id)
        for s in ('file.pdf','CON','bad/name','bad'+chr(92)+'name','name?','', 'AUX.jpeg'):
            with self.subTest(s=s),self.assertRaises(ValueError):
                manual_repair_proposal(self.core,self.doc_id,self.cid,'Payroll',s)
        self.assertEqual(before['relative_path'],self.core.document(self.doc_id)['relative_path'])
    def test_duplicate_safe_and_searchable(self):
        apply_repair(self.core,manual_repair_proposal(
            self.core,self.doc_id,self.cid,'Payroll','Staff Incentives'))
        original=Path(self.tmp.name)/'second.jpeg'
        original.write_bytes(b'another sample image')
        second=self.core.import_file(original,ai=lambda *_:{
            'company_id':None,'category':'Other','confidence':0,
            'needs_review':True,'reason':'unidentified'})['id']
        apply_repair(self.core,manual_repair_proposal(
            self.core,second,self.cid,'Payroll','Staff Incentives.jpeg'))
        self.assertEqual(self.core.document(second)['title'],'Staff Incentives (2).jpeg')
if __name__=='__main__':
    unittest.main()
