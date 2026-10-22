-- C3B.7 — READ ONLY, one result row. Use ONLY in the existing hosted Supabase SQL Editor.
-- No UPDATE/DELETE/RPC and no object keys, credentials or signed URLs are selected.
-- The manifest is NOT an authorization to execute real deletion.
WITH exact_runs(run_id) AS (
  VALUES
    ('20261020T124143Z'), ('20261020T124907Z'),
    ('20261020T150501Z'), ('20261020T150959Z')
),
bucket_rows AS (
  SELECT id, owner_id, title, status, bucket, last_authorized_at, deleted_at
  FROM public.toolkit_documents
  WHERE bucket = 'broker-wallet-media-staging'
),
matched AS (
  SELECT d.* FROM bucket_rows AS d
  WHERE EXISTS (
    SELECT 1 FROM exact_runs AS r
    WHERE d.title LIKE 'staging-e2e-toolkit-' || r.run_id || '-%'
  )
),
stats AS (
  SELECT count(*) AS all_bucket_rows,
         count(*) FILTER (WHERE status = 'pending_delete') AS all_bucket_pending_delete,
         count(*) FILTER (WHERE title LIKE 'staging-e2e-toolkit-%') AS all_bucket_synthetic
  FROM bucket_rows
),
manifest AS (
  SELECT count(*) AS matched_count,
         count(*) FILTER (WHERE status = 'pending_delete') AS pending_delete_count,
         jsonb_pretty(jsonb_build_object(
           'schemaVersion', 1,
           'bucket', 'broker-wallet-media-staging',
           'records', coalesce(jsonb_agg(jsonb_build_object(
             'documentId', id::text,
             'ownerId', owner_id::text,
             'title', title,
             'status', status,
             'bucket', bucket,
             'lastAuthorizedAt', to_char(last_authorized_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
             'deletedAt', to_char(deleted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
           ) ORDER BY title), '[]'::jsonb)
         )) AS manifest_json
  FROM matched
)
SELECT s.all_bucket_rows, s.all_bucket_pending_delete, s.all_bucket_synthetic,
       m.matched_count, m.pending_delete_count, m.manifest_json
FROM stats AS s CROSS JOIN manifest AS m;
