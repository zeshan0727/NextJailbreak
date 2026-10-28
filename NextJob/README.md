# Next Job

Next Job is an iOS 16+ accounting work tracker designed for part-time jobs received from KB Accountants.

## Version 1.0.0 features

- Dashboard for Not Started, In Progress, Waiting for Documents, Ready for Review and Completed jobs.
- Assigned date, due date and completion date tracking.
- Job price, target hours and actual hours.
- Editable job types with default price and target time.
- Client/reference, required-document checklist and work notes.
- Source-document uploads and separate completed-work uploads.
- Local file storage under the app's `Next Job Files` Documents folder.
- Document request email drafts.
- Standards-compatible ZIP package containing a job summary and all related files.
- Completion email draft with the ZIP attached.
- Share Sheet fallback when Apple Mail is not configured.
- Light, dark and system appearance.
- Local JSON persistence with no personal data included in the source or build.

## Build

The GitHub Actions workflow `.github/workflows/build-next-job.yml` generates the Xcode project with XcodeGen, builds an unsigned iPhone application and packages `NextJob-1.0.0.tipa` for TrollStore.
