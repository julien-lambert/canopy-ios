-- JardinForet: species/cultivars metadata alignment for offline-first sync
-- Safe to run multiple times (IF NOT EXISTS).

begin;

-- 1) Species: add phenology columns used by app forms/details.
alter table public.species
    add column if not exists flowering_period text,
    add column if not exists fruiting_period text;

-- 2) Cultivars: add full metadata columns now handled by app/UI.
alter table public.cultivars
    add column if not exists origin text,
    add column if not exists plant_type text,
    add column if not exists morphology text,
    add column if not exists culture text,
    add column if not exists uses text,
    add column if not exists melliferous_level text,
    add column if not exists ornamental_interest text,
    add column if not exists lifespan_min integer,
    add column if not exists lifespan_max integer,
    add column if not exists height_min double precision,
    add column if not exists height_max double precision,
    add column if not exists flowering_period text,
    add column if not exists fruiting_period text;

-- 3) Optional backfill from legacy species.variety_name rows into cultivars rows by (species_id, name).
--    Keeps existing cultivar values when already filled.
update public.cultivars c
set
    origin              = coalesce(c.origin, s.origin),
    plant_type          = coalesce(c.plant_type, s.plant_type),
    morphology          = coalesce(c.morphology, s.morphology),
    culture             = coalesce(c.culture, s.culture),
    uses                = coalesce(c.uses, s.uses),
    melliferous_level   = coalesce(c.melliferous_level, s.melliferous_level),
    ornamental_interest = coalesce(c.ornamental_interest, s.ornamental_interest),
    lifespan_min        = coalesce(c.lifespan_min, s.lifespan_min),
    lifespan_max        = coalesce(c.lifespan_max, s.lifespan_max),
    height_min          = coalesce(c.height_min, s.height_min),
    height_max          = coalesce(c.height_max, s.height_max),
    flowering_period    = coalesce(c.flowering_period, s.flowering_period),
    fruiting_period     = coalesce(c.fruiting_period, s.fruiting_period)
from public.species s
where s.id = c.species_id
  and nullif(trim(s.variety_name), '') is not null
  and lower(trim(s.variety_name)) = lower(trim(c.name));

-- 4) Helpful unique key for upsert stability (if absent).
create unique index if not exists cultivars_species_id_name_uidx
    on public.cultivars (species_id, lower(name));

commit;
