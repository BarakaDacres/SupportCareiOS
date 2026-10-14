-- Support Care iOS: move preferences that were device-only (browser localStorage) into
-- user_settings so they sync across web and iOS. Adds the public-holiday auto-detect and
-- onboarding columns.
--
-- This is additive and safe to run on the live project. Every column is nullable or has a default
-- that matches the web app's current behaviour.
-- Copy it into the web repo's supabase/migrations/ folder, or run it in the Supabase SQL editor.

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS evening_start        TIME    DEFAULT '18:00',
  -- '00:00' means midnight (end of day), matching pref_evening_end semantics. Default window 18:00–24:00.
  ADD COLUMN IF NOT EXISTS evening_end          TIME    DEFAULT '00:00',
  ADD COLUMN IF NOT EXISTS sleepover_start      TIME    DEFAULT '00:00',
  ADD COLUMN IF NOT EXISTS sleepover_end        TIME    DEFAULT '06:00',
  -- 0 = Sunday … 6 = Saturday
  ADD COLUMN IF NOT EXISTS week_start_day       SMALLINT DEFAULT 1 CHECK (week_start_day BETWEEN 0 AND 6),
  ADD COLUMN IF NOT EXISTS auto_timezone        BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS haptics              BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS shift_reminders      BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS invoice_reminders    BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS holiday_auto_detect  BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS holiday_state        TEXT    DEFAULT 'NSW'
    CHECK (holiday_state IN ('ACT','NSW','NT','QLD','SA','TAS','VIC','WA')),
  ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT false;

-- Existing users have already set the app up, so skip onboarding for them.
UPDATE public.user_settings SET onboarding_completed = true WHERE onboarding_completed IS DISTINCT FROM true;
