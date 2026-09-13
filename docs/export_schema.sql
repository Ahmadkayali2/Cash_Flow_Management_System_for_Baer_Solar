-- Run this in the Supabase SQL editor and save the result as schema.json.
-- It is the input the consistency check compares the ERD against, so the
-- check always runs against the database as it actually is, not against a
-- description of it.
SELECT json_agg(t ORDER BY t.table_name, t.ordinal_position) AS schema_json FROM (
  SELECT c.table_name, c.ordinal_position, c.column_name, c.data_type,
         c.character_maximum_length AS len, c.numeric_precision AS prec,
         c.numeric_scale AS scale, c.is_nullable, c.column_default,
         (SELECT string_agg(tc.constraint_type, ',')
            FROM information_schema.key_column_usage k
            JOIN information_schema.table_constraints tc
              ON tc.constraint_name = k.constraint_name
             AND tc.table_schema = k.table_schema
           WHERE k.table_schema = 'public' AND k.table_name = c.table_name
             AND k.column_name = c.column_name
             AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE')) AS keys,
         (SELECT ccu.table_name || '.' || ccu.column_name
            FROM information_schema.key_column_usage k
            JOIN information_schema.table_constraints tc
              ON tc.constraint_name = k.constraint_name
             AND tc.table_schema = k.table_schema
            JOIN information_schema.constraint_column_usage ccu
              ON ccu.constraint_name = tc.constraint_name
           WHERE tc.constraint_type = 'FOREIGN KEY' AND k.table_schema = 'public'
             AND k.table_name = c.table_name AND k.column_name = c.column_name
           LIMIT 1) AS fk_target
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
) t;
