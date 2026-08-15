-- Backfill sample Master Plan / Floor Plans / Brochure data onto already-
-- seeded communities, so the public Community Details page's new sections
-- have something to render. Safe to re-run (only ever touches rows that are
-- still empty/null, so it won't duplicate or clobber real admin-entered
-- data). Run with: psql "$DB_URL" -f backend/src/seeds/backfill_floor_plans_and_documents.sql

-- 1. Master plan image — reuse the 4th gallery photo when present, else the
--    hero image (same fallback the public page itself already uses).
UPDATE communities
SET master_plan_image = COALESCE(gallery[4], hero_image)
WHERE master_plan_image IS NULL;

-- 2. Floor plans — one entry per Unit Type the community already has
--    configured (never a hardcoded 2BHK/3BHK/Villa list), using a generic
--    blueprint image and an increasing sample area per plan.
UPDATE communities c
SET floor_plans = sub.plans
FROM (
  WITH numbered AS (
    SELECT
      cm.id,
      ut AS configuration,
      row_number() OVER (PARTITION BY cm.id ORDER BY ut) AS rn
    FROM communities cm, unnest(cm.unit_types) AS ut
    WHERE jsonb_array_length(cm.floor_plans) = 0
  )
  SELECT
    id,
    jsonb_agg(
      jsonb_build_object(
        'id', 'fp-' || id::text || '-' || rn,
        'configuration', configuration,
        'name', configuration || ' Floor Plan',
        'area', (1000 + rn * 350)::text || ' sq.ft',
        'image', 'https://images.unsplash.com/photo-1503387762-592deb58ef4e?q=80&w=1600&auto=format&fit=crop',
        'active', true
      )
    ) AS plans
  FROM numbered
  GROUP BY id
) sub
WHERE c.id = sub.id;

-- 3. Brochures & Plans documents — Brochure / Master Plan / Floor Plan /
--    Price Plan, all marked public so they show on the public page.
UPDATE communities
SET documents = jsonb_build_array(
  jsonb_build_object('name', name || ' — Project Brochure', 'type', 'PDF', 'category', 'Brochure', 'size', '4.2 MB', 'url', hero_image, 'public', true),
  jsonb_build_object('name', name || ' — Master Plan', 'type', 'PDF', 'category', 'Master Plan', 'size', '2.8 MB', 'url', COALESCE(master_plan_image, hero_image), 'public', true),
  jsonb_build_object('name', name || ' — Floor Plans', 'type', 'PDF', 'category', 'Floor Plan', 'size', '3.1 MB', 'url', 'https://images.unsplash.com/photo-1503387762-592deb58ef4e?q=80&w=1600&auto=format&fit=crop', 'public', true),
  jsonb_build_object('name', name || ' — Price List', 'type', 'PDF', 'category', 'Price Plan', 'size', '1.4 MB', 'url', hero_image, 'public', true)
)
WHERE jsonb_array_length(documents) = 0;
