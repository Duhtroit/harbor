# Importing a Chrome or Chromium Partial Download

Harbor can continue a stopped Chrome/Chromium download from a `.crdownload` snapshot. The import wizard is deliberately guided so the browser cannot keep writing while Harbor takes its snapshot.

## Guided import

1. **Pause Chrome first.** In Chrome’s Downloads window, pause or cancel the download. Do not close or delete the `.crdownload` file yet.
2. In Harbor, choose **Downloads > Import Partial Download…**.
3. **Step 1 — Select the partial file:** choose the file ending in `.crdownload`. Harbor checks that it is a non-empty regular file and displays its size.
4. **Step 2 — Provide the source:** copy the direct HTTP/HTTPS file URL from Chrome’s download details and paste it into the wizard. A page URL is not necessarily the file URL.
5. **Step 3 — Confirm the file is paused:** enable the confirmation that Chrome has stopped writing and continue. This prevents importing a moving snapshot by accident.
6. **Step 4 — Review:** check the file name, snapshot size, and source URL. Choose **Import and Prepare Resume**.
7. Harbor probes the exact byte-range operation it needs. It requires `206 Partial Content`, a known total size, and an `ETag` or `Last-Modified` validator.
8. The imported item appears paused with its recovered byte count. Select it and choose **Resume**.

Harbor copies the partial file into its own recovery store. It never writes to Chrome’s file. After confirming that Harbor resumed successfully, the original `.crdownload` can be removed manually.

## Why Harbor may reject a file

Harbor refuses an import when it cannot prove that appending the remaining bytes is safe. Common reasons include:

- The server does not support HTTP byte ranges or ignores the `Range` header.
- The server does not provide an `ETag` or `Last-Modified` value.
- The URL is no longer available, has changed, or requires browser-only authentication.
- The partial file is empty, already complete, or changed during import.
- The selected file is not a regular `.crdownload` file.

These checks avoid silently joining bytes from different versions of a resource.

## Limitations

- Chrome’s download database is not imported. The source URL must be supplied manually.
- Cookies, authorization headers, and browser-specific session state are not copied. If the URL requires a login, configure appropriate request headers in Harbor or start the download directly in Harbor.
- Import is snapshot-based, not a live hot-swap. Chrome must be paused before importing.
- Compressed, encrypted, dynamically generated, and expiring downloads may not be resumable even when they have a `.crdownload` suffix.
