# 10 — Documents (files)

> Files are stored in **Supabase Storage** (a file store, like Google Drive for our app). Information about each file (name, size, who uploaded it, what it is attached to) is stored in the `documents` table (`04-database.md`).
> A **bucket** is a top-level storage folder with its own rules. A **private** bucket cannot be opened by anyone without permission. A **signed URL** is a temporary download link that stops working after a few minutes.

**Main rule:** no user may open a file of another organization, or a file of another client.

---

## 1. Buckets

| Bucket | Private? | Contents | Limits (set on the bucket itself, so Storage refuses bigger/wrong files) |
|---|---|---|---|
| `org-files` | **Private** | All documents attached to customers, projects, tasks, invoices, expenses | Max 10 MB per file; allowed types from D-43 |
| `org-logos` | **Public read** (D-44) | Organization logos only | Max 1 MB; PNG, JPEG, WEBP only (no SVG, because SVG files can contain scripts) |

Profile photos: no bucket in V1 (D-45).

## 2. Folder (path) strategy

```
org-files/
  {organization_id}/customers/{customer_id}/{random_uuid}-{safe_file_name}
  {organization_id}/projects/{project_id}/{random_uuid}-{safe_file_name}
  {organization_id}/tasks/{task_id}/{random_uuid}-{safe_file_name}
  {organization_id}/invoices/{invoice_id}/{random_uuid}-{safe_file_name}
  {organization_id}/expenses/{expense_id}/{random_uuid}-{safe_file_name}

org-logos/
  {organization_id}/{random_uuid}.{png|jpg|webp}
```

- The path **always starts with the organization ID**. Storage policies read this first folder to know which organization owns the file.
- The **server** builds the path; the browser never chooses it.
- `safe_file_name`: the original name cleaned (only letters, digits, `-`, `_`, `.`; max 100 chars). The original name is kept in `documents.file_name` for display.
- The random UUID makes names impossible to guess and avoids two files overwriting each other.

## 3. Metadata table

`documents` (full column list in `04-database.md`): `organization_id`, `bucket`, `storage_path` (unique), `file_name`, `mime_type`, `size_bytes`, exactly one of `customer_id` / `project_id` / `task_id` / `invoice_id` / `expense_id`, `visible_to_client` (default false), `uploaded_by`, `created_at`.

A file in `org-files` **without** a `documents` row is invisible to everyone (see §6), so the table is the single source of truth for who may see a file.

## 4. Allowed files and sizes

| Rule | V1 value (D-43) |
|---|---|
| Max size per file | **10 MB** |
| Allowed types | PDF, JPEG, PNG, WEBP, DOCX (Word), XLSX (Excel), CSV, TXT |
| Not allowed | Everything else — especially HTML, SVG, JavaScript, EXE, ZIP (can hide dangerous content) |
| Files per upload | Up to 10 at once |
| Organization storage limit | From the plan (`plans.max_storage_mb`, Step 22) = Σ `documents.size_bytes` of the organization |

Checks happen three times: in the browser (quick feedback), on the server before the upload link is created (name, type, size, permission, storage limit), and by the bucket settings in Storage (size and type).

## 5. Upload flow

Uploading through our Next.js server is not possible for bigger files (Vercel limits request bodies to about 4.5 MB). So the file goes **straight from the browser to Supabase Storage**, but only with a one-time permission created by our server:

```
1. Browser: user picks a file on e.g. a project page.
2. Server Action prepareUpload({ entity: 'project', entityId, fileName, size, mimeType })
     - Zod validation (type in allowed list, size ≤ 10 MB)
     - requireMembership + role allowed to upload to this kind of record (matrix §3.9)
     - load the record by id AND organization_id (must exist, user must be able to see it)
     - storage limit not exceeded
     - build the path {org}/projects/{projectId}/{uuid}-{safeName}
     - create a signed UPLOAD URL for exactly this path (valid a short time)
3. Browser uploads the file to that URL (progress bar).
4. Server Action confirmUpload({ path, ... })
     - checks again: path belongs to this org and to the same record it prepared
     - reads the real size and type from Storage (does not trust the browser)
     - inserts the documents row (uploaded_by forced) → activity log → notifications
5. The file now appears in the list.
```

- If step 4 fails or the user closes the tab, the file stays without a `documents` row → invisible to everyone. A clean-up (manual script in V1, scheduled job later) deletes such orphan files older than 24 hours.
- Storage **insert policy** on `org-files`: only allowed when the first folder is an organization where the user has an upload role (`can_write`), so even a hand-made upload request cannot write into another organization's folder.

## 6. Download flow (private files)

1. User clicks "Download" / "View".
2. Server Action `getDocumentUrl(documentId)`: `requireMembership` → select the `documents` row **with the user's own session** (so RLS decides visibility, matrix §3.9 and `06-authorization-rls.md` §5.13) → if not visible → "Not found".
3. Server creates a **signed URL valid for 5 minutes** and returns it; the browser opens it.
4. Storage **select policy** on `org-files` as a second wall: a file may be read only if the user can select a `documents` row with that exact `storage_path`:

```sql
create policy "read files the user can see in documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'org-files'
  and exists (
    select 1 from public.documents d
    where d.storage_path = storage.objects.name
  )   -- documents' own RLS applies inside this check
);
```

Because the `documents` RLS runs inside this check, all role/client rules (including `visible_to_client`) automatically apply to the file itself. Links are never stored or shown permanently; each view creates a fresh one.

## 7. Access permissions (summary)

| Role | Can see files attached to | Can upload to | Can delete |
|---|---|---|---|
| OWNER, ADMIN | everything | everything | any |
| MANAGER | customers, projects, tasks, invoices (not expenses) | customers, projects, tasks | own uploads |
| ACCOUNTANT | customers, invoices, expenses; projects/tasks (view, D-03) | customers, invoices, expenses | own uploads |
| EMPLOYEE | tasks assigned to them, projects they are a member of | same (D-22) | own uploads |
| CLIENT | only files with **`visible_to_client = true`** attached to **their** customer, their projects, their non-draft invoices (and tasks of their projects if D-06 is on) | nothing (D-21) | nothing |
| PLATFORM_ADMIN | nothing (D-01) | nothing | only permanent organization deletion (D-24) |

`visible_to_client` can be switched by OWNER, ADMIN, MANAGER, ACCOUNTANT. Files on **expenses are never visible to clients** (the switch is hidden and a database check blocks it).

## 8. Deletion rules

- Deleting a document removes the `documents` row **and** the file in Storage (in that order, inside one Server Action; if the file removal fails, the row is already gone so the file is invisible, and the orphan clean-up removes it later).
- Logged in `activity_logs` (file name, record, who).
- Records that are archived (customer, project, task) keep their documents.
- Documents on issued invoices and on expenses can be deleted only by OWNER/ADMIN (receipts are evidence).
- Organization permanent deletion (D-24): PLATFORM_ADMIN removes the whole `{organization_id}/` folder from both buckets with the admin client.

## 9. Organization logo

- Uploaded in `/settings` by OWNER/ADMIN (square-ish image, ≤ 1 MB, PNG/JPEG/WEBP).
- Same prepare/confirm flow, into `org-logos/{organization_id}/{uuid}.ext`; `organizations.logo_path` is updated; the old logo file is deleted.
- **D-44 recommended: public-read bucket** for logos only. Why: the logo appears in the header for every member, on printed invoices, and later in emails, where signed links would expire. A logo is not secret, and the random file name means nobody can list or guess other organizations' logos.
- Upload/replace/delete in `org-logos` is still protected by storage policies (only OWNER/ADMIN of the organization in the first folder).
- If no logo: the organization's initials are shown.

## 10. Tests (Step 18)

1. User of org A requests a signed URL for a document of org B → "Not found".
2. User of org A calls Storage directly for a path in org B's folder → refused.
3. Client A requests a document of customer B (same organization) → refused.
4. Client requests a document of their own customer with `visible_to_client = false` → refused.
5. Employee requests a file of a task not assigned to them → refused.
6. Upload of an `.exe` / `.html` / 11 MB file → refused (server and bucket).
7. Upload into another organization's folder with a hand-made request → refused by the insert policy.
8. Signed URL stops working after 5 minutes.

## 11. Decisions raised in this file

| # | Question | Recommended default | Why |
|---|---|---|---|
| D-43 | File size and types | **10 MB**; PDF, JPEG, PNG, WEBP, DOCX, XLSX, CSV, TXT. | Covers photos, scans and office files while blocking file types that can carry scripts. |
| D-44 | Logo storage | **Separate public-read bucket for logos only**; all other files private. | Logos must show on printed invoices/emails without expiring links; they are not secret. |

Referenced: D-01, D-03, D-06, D-21, D-22, D-24, D-45.
