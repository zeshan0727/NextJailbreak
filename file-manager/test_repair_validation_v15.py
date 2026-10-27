"""Regression tests for v1.5 nonblocking AI repair."""
import tempfile
import unittest
from pathlib import Path
from filemanager.core import FileManagerCore
from filemanager.repair import repair_proposal, apply_repair, undo_last_repair

class RepairFallbackTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root=Path(self.tmp.name)
        self.core=FileManagerCore(root/'library',seed_companies=False)
        self.addCleanup(self.core.close)
        self.cid=self.core.add_company('Stone Café','stone')
        src=root/'Stone_Registration_2021-06-14.txt'
        src.write_text('Stone Cafe\nCOMMERCIAL REGISTRATION\nRegistered entity: Stone Cafe\n')
        self.doc_id=self.core.import_file(src,ai=lambda *_: {
            'company_id':self.cid,'category':'Other','confidence':.94,
            'needs_review':True,'reason':'needs classification'})['id']
    def ai(self,*args,**kw):
        return {'company_id':self.cid,'category':'Company Registration & Licenses',
                'confidence':.95,'needs_review':False,'short_label':'Registration',
                'document_reference':'UNKNOWN-9999','document_date':'2021-06-14',
                'reason':'Company registration'}
    def test_unsupported_reference_does_not_block(self):
        p=repair_proposal(self.core,self.doc_id,self.ai)
        self.assertTrue(p['eligible'])
        p['reference']='HALLUCINATED-12345'
        p['new_name']='Stone_Registration_HALLUCINATED-12345.txt'
        result=apply_repair(self.core,p)
        self.assertEqual(result['status'],'updated')
        self.assertIn('Unsupported reference omitted',result['notices'])
        after=self.core.document(self.doc_id)
        self.assertEqual(after['category'],'Company Registration & Licenses')
        self.assertNotIn('HALLUCINATED',after['title'])
        undo_last_repair(self.core,self.doc_id)
        self.assertEqual(self.core.document(self.doc_id)['category'],'Other')
    def test_invalid_date_is_optional(self):
        p=repair_proposal(self.core,self.doc_id,self.ai)
        p['date']='2028-12-27'
        result=apply_repair(self.core,p)
        self.assertEqual(result['status'],'updated')
        self.assertIn('Unsupported document date omitted',result['notices'])
        self.assertNotIn('2028',self.core.document(self.doc_id)['title'])
    def test_old_blank_original_name_not_blocked(self):
        with self.core.conn:
            self.core.conn.execute('UPDATE documents SET original_name=? WHERE id=?',('',self.doc_id))
        p=repair_proposal(self.core,self.doc_id,self.ai)
        p['reference']='Stone_Registration'
        result=apply_repair(self.core,p)
        self.assertEqual(result['status'],'updated')
    def test_ambiguous_company_stays_manual(self):
        p=repair_proposal(self.core,self.doc_id,lambda *a,**kw:{
          'company_id':self.cid,'category':'Company Registration & Licenses',
          'confidence':.4,'needs_review':True,'reason':'uncertain'})
        self.assertFalse(p['eligible'])
        with self.assertRaises(ValueError):apply_repair(self.core,p)
    def test_changed_file_still_blocked(self):
        p=repair_proposal(self.core,self.doc_id,self.ai)
        Path(self.core.document(self.doc_id)['absolute_path']).write_text('changed')
        with self.assertRaises(ValueError):apply_repair(self.core,p)

if __name__=='__main__':unittest.main()
