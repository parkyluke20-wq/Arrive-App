-- Pool-level operating hours, mirroring site_operating_hours.
-- day_of_week_int uses the same convention as site_operating_hours:
--   0 = Sunday, 1 = Monday, 2 = Tuesday, 3 = Wednesday,
--   4 = Thursday, 5 = Friday, 6 = Saturday.

CREATE TABLE IF NOT EXISTS pool_operating_hours (
  pool_id          uuid    NOT NULL REFERENCES capacity_pools(pool_id) ON DELETE CASCADE,
  day_of_week_int  integer NOT NULL CHECK (day_of_week_int BETWEEN 0 AND 6),
  day_of_week_text text    NOT NULL,
  open_time        time    NOT NULL,
  close_time       time    NOT NULL,
  PRIMARY KEY (pool_id, day_of_week_int)
);

ALTER TABLE pool_operating_hours ENABLE ROW LEVEL SECURITY;

-- internal_admins (global scope) can insert, update, and delete
CREATE POLICY "internal_admins manage pool_operating_hours"
  ON pool_operating_hours
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid()
        AND role = 'internal_admin'
        AND scope_type = 'global'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_roles
      WHERE user_id = auth.uid()
        AND role = 'internal_admin'
        AND scope_type = 'global'
    )
  );

-- Any authenticated user can read
CREATE POLICY "authenticated users select pool_operating_hours"
  ON pool_operating_hours
  FOR SELECT
  USING (auth.role() = 'authenticated');
