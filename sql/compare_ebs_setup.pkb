CREATE OR REPLACE PACKAGE BODY compare_ebs_setup AS

-- ============================================================
-- Private helpers
-- ============================================================

    -- Generate a simple UUID-style run identifier.
    FUNCTION new_run_id RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') || '_' ||
               DBMS_RANDOM.STRING('U', 6);
    END new_run_id;

    -- Persist one difference row.
    PROCEDURE save_diff (
        p_run_id       IN VARCHAR2,
        p_category     IN VARCHAR2,
        p_object_name  IN VARCHAR2,
        p_attr         IN VARCHAR2,
        p_src_val      IN VARCHAR2,
        p_tgt_val      IN VARCHAR2,
        p_diff_type    IN VARCHAR2,
        p_notes        IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO ebs_compare_results (
            run_id, category, object_name, attribute_name,
            source_value, target_value, diff_type, notes
        ) VALUES (
            p_run_id, p_category, p_object_name, p_attr,
            SUBSTR(p_src_val, 1, 4000),
            SUBSTR(p_tgt_val, 1, 4000),
            p_diff_type,
            p_notes
        );
        COMMIT;
    END save_diff;

    -- Safely truncate long values for comparison keys.
    FUNCTION trunc_val (p_val IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN SUBSTR(p_val, 1, 4000);
    END trunc_val;

    -- Build a dynamic SQL string that queries the target via DB link.
    -- The caller appends table-specific columns and WHERE clause.
    FUNCTION target_sql (
        p_db_link IN VARCHAR2,
        p_select  IN VARCHAR2
    ) RETURN VARCHAR2 IS
    BEGIN
        -- Validate link name: only alphanumerics, underscores and dots allowed.
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Invalid DB link name: ' || p_db_link);
        END IF;
        RETURN p_select || '@' || p_db_link;
    END target_sql;

-- ============================================================
-- Profile Options  (FND level + site-level values)
-- ============================================================

    PROCEDURE compare_profiles (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        TYPE t_str_tab  IS TABLE OF VARCHAR2(500);
        TYPE t_val_tab  IS TABLE OF VARCHAR2(4000);

        -- Source profile option names
        CURSOR c_src IS
            SELECT po.profile_option_name,
                   po.user_profile_option_name,
                   NVL(pov.profile_option_value, '<NULL>') AS site_value
            FROM   apps.fnd_profile_options     po
            LEFT JOIN apps.fnd_profile_option_values pov
                   ON  pov.profile_option_id   = po.profile_option_id
                   AND pov.application_id      = po.application_id
                   AND pov.level_id            = 10001  -- SITE
                   AND pov.level_value         = 0
            ORDER BY po.profile_option_name;

        l_sql           VARCHAR2(2000);
        l_tgt_name      VARCHAR2(500);
        l_tgt_val       VARCHAR2(4000);
        l_cat  CONSTANT VARCHAR2(30) := 'PROFILE_OPTIONS';
        l_found         INTEGER;
    BEGIN
        l_sql :=
            'SELECT NVL(pov.profile_option_value,''<NULL>'') ' ||
            'FROM   apps.fnd_profile_options po ' ||
            'LEFT JOIN apps.fnd_profile_option_values pov ' ||
            '       ON  pov.profile_option_id = po.profile_option_id ' ||
            '       AND pov.application_id    = po.application_id ' ||
            '       AND pov.level_id          = 10001 ' ||
            '       AND pov.level_value       = 0 ' ||
            'WHERE po.profile_option_name = :1';

        FOR r IN c_src LOOP
            BEGIN
                EXECUTE IMMEDIATE target_sql(p_db_link, l_sql)
                    INTO l_tgt_val
                    USING r.profile_option_name;

                IF NVL(r.site_value, '<NULL>') != NVL(l_tgt_val, '<NULL>') THEN
                    save_diff(p_run_id, l_cat,
                              r.profile_option_name,
                              'SITE_VALUE',
                              r.site_value, l_tgt_val,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.profile_option_name,
                              NULL,
                              r.site_value, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        -- Find options that exist only in target
        l_sql :=
            'SELECT po.profile_option_name ' ||
            'FROM   apps.fnd_profile_options po ' ||
            'WHERE  NOT EXISTS ( ' ||
            '    SELECT 1 FROM apps.fnd_profile_options src ' ||
            '    WHERE  src.profile_option_name = po.profile_option_name' ||
            ')';

        -- We can't iterate a remote cursor dynamically, so use a bulk approach
        -- by fetching into a collection via a single dynamic query.
        DECLARE
            l_names t_str_tab;
            l_full_sql VARCHAR2(2000);
        BEGIN
            l_full_sql :=
                'SELECT po.profile_option_name ' ||
                'FROM   apps.fnd_profile_options' || '@' || p_db_link || ' po ' ||
                'WHERE  po.profile_option_name NOT IN ' ||
                '  (SELECT profile_option_name FROM apps.fnd_profile_options)';

            -- Validate again before concatenation (already done in target_sql but
            -- this path builds its own SQL string).
            IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
                RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
            END IF;

            EXECUTE IMMEDIATE l_full_sql
                BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL,
                          NULL, NULL,
                          'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_profiles;

-- ============================================================
-- Lookups  (FND_LOOKUP_TYPES + FND_LOOKUP_VALUES)
-- ============================================================

    PROCEDURE compare_lookups (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat  CONSTANT VARCHAR2(30) := 'LOOKUPS';

        -- Source lookup types (USER_EXTENSIBLE and SYSTEM not excluded so that
        -- customisations in SYSTEM lookups are also caught)
        CURSOR c_src_types IS
            SELECT lookup_type, meaning, description
            FROM   apps.fnd_lookup_types_vl
            WHERE  view_application_id NOT IN (0, 3)  -- skip internal-only
            ORDER BY lookup_type;

        CURSOR c_src_values (p_type IN VARCHAR2) IS
            SELECT lookup_code, meaning, description, enabled_flag,
                   start_date_active, end_date_active
            FROM   apps.fnd_lookup_values_vl
            WHERE  lookup_type   = p_type
            AND    view_application_id NOT IN (0, 3)
            ORDER BY lookup_code;

        l_tgt_meaning   VARCHAR2(500);
        l_tgt_enabled   VARCHAR2(1);
        l_count         INTEGER;
        l_sql           VARCHAR2(4000);
    BEGIN
        -- Check which source types are missing on target
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR rt IN c_src_types LOOP
            l_sql := 'SELECT COUNT(1) FROM apps.fnd_lookup_types' ||
                     '@' || p_db_link ||
                     ' WHERE lookup_type = :1 AND view_application_id NOT IN (0,3)';
            EXECUTE IMMEDIATE l_sql INTO l_count USING rt.lookup_type;

            IF l_count = 0 THEN
                save_diff(p_run_id, l_cat,
                          rt.lookup_type, NULL,
                          rt.meaning, NULL,
                          'ONLY_IN_SOURCE');
            ELSE
                -- Compare individual lookup values
                FOR rv IN c_src_values(rt.lookup_type) LOOP
                    l_sql :=
                        'SELECT meaning, enabled_flag ' ||
                        'FROM   apps.fnd_lookup_values' || '@' || p_db_link ||
                        ' WHERE lookup_type = :1 AND lookup_code = :2' ||
                        ' AND view_application_id NOT IN (0,3) AND ROWNUM = 1';
                    BEGIN
                        EXECUTE IMMEDIATE l_sql
                            INTO l_tgt_meaning, l_tgt_enabled
                            USING rt.lookup_type, rv.lookup_code;

                        IF NVL(rv.meaning,'<NULL>') != NVL(l_tgt_meaning,'<NULL>') OR
                           NVL(rv.enabled_flag,'N') != NVL(l_tgt_enabled,'N')
                        THEN
                            save_diff(p_run_id, l_cat,
                                      rt.lookup_type || '.' || rv.lookup_code,
                                      'MEANING|ENABLED',
                                      rv.meaning || '|' || rv.enabled_flag,
                                      l_tgt_meaning || '|' || l_tgt_enabled,
                                      'VALUE_DIFF');
                        END IF;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN
                            save_diff(p_run_id, l_cat,
                                      rt.lookup_type || '.' || rv.lookup_code,
                                      NULL, rv.meaning, NULL,
                                      'ONLY_IN_SOURCE');
                    END;
                END LOOP;
            END IF;
        END LOOP;

        -- Target-only lookup types
        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT lt.lookup_type ' ||
                'FROM   apps.fnd_lookup_types@' || p_db_link || ' lt ' ||
                'WHERE  lt.view_application_id NOT IN (0,3) ' ||
                'AND    lt.lookup_type NOT IN ' ||
                '  (SELECT lookup_type FROM apps.fnd_lookup_types_vl ' ||
                '   WHERE view_application_id NOT IN (0,3))'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_lookups;

-- ============================================================
-- Responsibilities
-- ============================================================

    PROCEDURE compare_responsibilities (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'RESPONSIBILITIES';

        CURSOR c_src IS
            SELECT responsibility_key, responsibility_name,
                   menu_name, data_group_name
            FROM   apps.fnd_responsibility_vl
            ORDER BY responsibility_key;

        l_sql       VARCHAR2(2000);
        l_tgt_name  VARCHAR2(500);
        l_tgt_menu  VARCHAR2(500);
        l_count     INTEGER;
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT r.responsibility_name, m.menu_name ' ||
                'FROM   apps.fnd_responsibility_vl@' || p_db_link || ' r ' ||
                'JOIN   apps.fnd_menus_vl@' || p_db_link || ' m ' ||
                '       ON m.menu_id = r.menu_id ' ||
                'WHERE  r.responsibility_key = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql
                    INTO l_tgt_name, l_tgt_menu
                    USING r.responsibility_key;

                IF NVL(r.responsibility_name,'<NULL>') != NVL(l_tgt_name,'<NULL>') OR
                   NVL(r.menu_name,'<NULL>') != NVL(l_tgt_menu,'<NULL>')
                THEN
                    save_diff(p_run_id, l_cat,
                              r.responsibility_key,
                              'NAME|MENU',
                              r.responsibility_name || '|' || r.menu_name,
                              l_tgt_name || '|' || l_tgt_menu,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.responsibility_key, NULL,
                              r.responsibility_name, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        -- Target-only responsibilities
        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_keys t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT responsibility_key ' ||
                'FROM   apps.fnd_responsibility_vl@' || p_db_link ||
                ' WHERE responsibility_key NOT IN ' ||
                '  (SELECT responsibility_key FROM apps.fnd_responsibility_vl)'
            BULK COLLECT INTO l_keys;

            FOR i IN 1 .. l_keys.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_keys(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_responsibilities;

-- ============================================================
-- Concurrent Programs
-- ============================================================

    PROCEDURE compare_concurrent_programs (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'CONCURRENT_PROGRAMS';

        CURSOR c_src IS
            SELECT concurrent_program_name, user_concurrent_program_name,
                   execution_method_code, enabled_flag
            FROM   apps.fnd_concurrent_programs_vl
            WHERE  enabled_flag = 'Y'
            ORDER BY concurrent_program_name;

        l_sql        VARCHAR2(2000);
        l_tgt_meth   VARCHAR2(1);
        l_tgt_enab   VARCHAR2(1);
        l_count      INTEGER;
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT execution_method_code, enabled_flag ' ||
                'FROM   apps.fnd_concurrent_programs_vl@' || p_db_link ||
                ' WHERE concurrent_program_name = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql
                    INTO l_tgt_meth, l_tgt_enab
                    USING r.concurrent_program_name;

                IF NVL(r.execution_method_code,'<NULL>') != NVL(l_tgt_meth,'<NULL>') OR
                   NVL(r.enabled_flag,'N') != NVL(l_tgt_enab,'N')
                THEN
                    save_diff(p_run_id, l_cat,
                              r.concurrent_program_name,
                              'EXEC_METHOD|ENABLED',
                              r.execution_method_code || '|' || r.enabled_flag,
                              l_tgt_meth || '|' || l_tgt_enab,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.concurrent_program_name, NULL,
                              r.user_concurrent_program_name, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT concurrent_program_name ' ||
                'FROM   apps.fnd_concurrent_programs_vl@' || p_db_link ||
                ' WHERE enabled_flag = ''Y'' ' ||
                ' AND   concurrent_program_name NOT IN ' ||
                '  (SELECT concurrent_program_name ' ||
                '   FROM   apps.fnd_concurrent_programs_vl ' ||
                '   WHERE  enabled_flag = ''Y'')'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_concurrent_programs;

-- ============================================================
-- Flexfields (Key + Descriptive)
-- ============================================================

    PROCEDURE compare_flexfields (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'FLEXFIELDS';
        l_sql    VARCHAR2(2000);
        l_count  INTEGER;

        -- Key flexfields
        CURSOR c_kff IS
            SELECT id_flex_code, id_flex_name, application_id
            FROM   apps.fnd_id_flexs
            ORDER BY id_flex_code;

        -- Descriptive flexfields
        CURSOR c_dff IS
            SELECT descriptive_flexfield_name, title, application_id
            FROM   apps.fnd_descriptive_flexs_vl
            ORDER BY descriptive_flexfield_name;
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_kff LOOP
            EXECUTE IMMEDIATE
                'SELECT COUNT(1) FROM apps.fnd_id_flexs@' || p_db_link ||
                ' WHERE id_flex_code = :1 AND application_id = :2'
                INTO l_count USING r.id_flex_code, r.application_id;

            IF l_count = 0 THEN
                save_diff(p_run_id, l_cat || '_KFF',
                          r.id_flex_code, NULL,
                          r.id_flex_name, NULL,
                          'ONLY_IN_SOURCE');
            END IF;
        END LOOP;

        FOR r IN c_dff LOOP
            EXECUTE IMMEDIATE
                'SELECT COUNT(1) FROM apps.fnd_descriptive_flexs_vl@' || p_db_link ||
                ' WHERE descriptive_flexfield_name = :1 AND application_id = :2'
                INTO l_count
                USING r.descriptive_flexfield_name, r.application_id;

            IF l_count = 0 THEN
                save_diff(p_run_id, l_cat || '_DFF',
                          r.descriptive_flexfield_name, NULL,
                          r.title, NULL,
                          'ONLY_IN_SOURCE');
            END IF;
        END LOOP;

        -- Target-only KFF
        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_codes t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT id_flex_code ' ||
                'FROM   apps.fnd_id_flexs@' || p_db_link ||
                ' WHERE (id_flex_code, application_id) NOT IN ' ||
                '  (SELECT id_flex_code, application_id FROM apps.fnd_id_flexs)'
            BULK COLLECT INTO l_codes;

            FOR i IN 1 .. l_codes.COUNT LOOP
                save_diff(p_run_id, l_cat || '_KFF',
                          l_codes(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_flexfields;

-- ============================================================
-- Value Sets
-- ============================================================

    PROCEDURE compare_value_sets (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'VALUE_SETS';

        CURSOR c_src IS
            SELECT flex_value_set_name, format_type,
                   maximum_size, validation_type
            FROM   apps.fnd_flex_value_sets
            ORDER BY flex_value_set_name;

        l_sql      VARCHAR2(2000);
        l_tgt_fmt  VARCHAR2(10);
        l_tgt_vsz  NUMBER;
        l_tgt_val  VARCHAR2(10);
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT format_type, maximum_size, validation_type ' ||
                'FROM   apps.fnd_flex_value_sets@' || p_db_link ||
                ' WHERE flex_value_set_name = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql
                    INTO l_tgt_fmt, l_tgt_vsz, l_tgt_val
                    USING r.flex_value_set_name;

                IF NVL(r.format_type,   '<N>') != NVL(l_tgt_fmt, '<N>') OR
                   NVL(r.maximum_size,    0)   != NVL(l_tgt_vsz,  0)    OR
                   NVL(r.validation_type,'<N>') != NVL(l_tgt_val, '<N>')
                THEN
                    save_diff(p_run_id, l_cat,
                              r.flex_value_set_name,
                              'FORMAT|MAX_SIZE|VALIDATION',
                              r.format_type || '|' || r.maximum_size || '|' || r.validation_type,
                              l_tgt_fmt    || '|' || l_tgt_vsz      || '|' || l_tgt_val,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.flex_value_set_name, NULL,
                              r.format_type, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT flex_value_set_name ' ||
                'FROM   apps.fnd_flex_value_sets@' || p_db_link ||
                ' WHERE flex_value_set_name NOT IN ' ||
                '  (SELECT flex_value_set_name FROM apps.fnd_flex_value_sets)'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_value_sets;

-- ============================================================
-- Organizations (Operating Units + Inventory Orgs)
-- ============================================================

    PROCEDURE compare_organizations (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'ORGANIZATIONS';

        CURSOR c_src IS
            SELECT name, type, business_group_id
            FROM   apps.hr_all_organization_units
            ORDER BY name;

        l_sql      VARCHAR2(2000);
        l_tgt_type VARCHAR2(100);
        l_count    INTEGER;
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT type FROM apps.hr_all_organization_units@' || p_db_link ||
                ' WHERE name = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql INTO l_tgt_type USING r.name;

                IF NVL(r.type,'<NULL>') != NVL(l_tgt_type,'<NULL>') THEN
                    save_diff(p_run_id, l_cat,
                              r.name, 'ORG_TYPE',
                              r.type, l_tgt_type,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.name, NULL,
                              r.type, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT name FROM apps.hr_all_organization_units@' || p_db_link ||
                ' WHERE name NOT IN ' ||
                '  (SELECT name FROM apps.hr_all_organization_units)'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_organizations;

-- ============================================================
-- GL Ledgers
-- ============================================================

    PROCEDURE compare_ledgers (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'GL_LEDGERS';

        CURSOR c_src IS
            SELECT name, short_name, currency_code,
                   period_set_name, accounted_period_type,
                   chart_of_accounts_id, ledger_category_code
            FROM   apps.gl_ledgers
            ORDER BY name;

        l_sql       VARCHAR2(2000);
        l_tgt_curr  VARCHAR2(30);
        l_tgt_pset  VARCHAR2(100);
        l_tgt_coa   NUMBER;
        l_tgt_cat   VARCHAR2(30);
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT currency_code, period_set_name, ' ||
                '       chart_of_accounts_id, ledger_category_code ' ||
                'FROM   apps.gl_ledgers@' || p_db_link ||
                ' WHERE short_name = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql
                    INTO l_tgt_curr, l_tgt_pset, l_tgt_coa, l_tgt_cat
                    USING r.short_name;

                IF NVL(r.currency_code,'<N>') != NVL(l_tgt_curr,'<N>') OR
                   NVL(r.period_set_name,'<N>') != NVL(l_tgt_pset,'<N>') OR
                   NVL(r.chart_of_accounts_id,0) != NVL(l_tgt_coa,0) OR
                   NVL(r.ledger_category_code,'<N>') != NVL(l_tgt_cat,'<N>')
                THEN
                    save_diff(p_run_id, l_cat,
                              r.name,
                              'CURRENCY|PERIOD_SET|COA|CATEGORY',
                              r.currency_code    || '|' || r.period_set_name ||
                              '|' || r.chart_of_accounts_id || '|' || r.ledger_category_code,
                              l_tgt_curr || '|' || l_tgt_pset ||
                              '|' || l_tgt_coa || '|' || l_tgt_cat,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.name, NULL,
                              r.currency_code, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(500);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT name FROM apps.gl_ledgers@' || p_db_link ||
                ' WHERE short_name NOT IN ' ||
                '  (SELECT short_name FROM apps.gl_ledgers)'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_ledgers;

-- ============================================================
-- Currencies
-- ============================================================

    PROCEDURE compare_currencies (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'CURRENCIES';

        CURSOR c_src IS
            SELECT currency_code, name, enabled_flag
            FROM   apps.fnd_currencies_vl
            WHERE  enabled_flag = 'Y'
            ORDER BY currency_code;

        l_sql       VARCHAR2(1000);
        l_tgt_enab  VARCHAR2(1);
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT enabled_flag FROM apps.fnd_currencies_vl@' || p_db_link ||
                ' WHERE currency_code = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql INTO l_tgt_enab USING r.currency_code;

                IF NVL(r.enabled_flag,'N') != NVL(l_tgt_enab,'N') THEN
                    save_diff(p_run_id, l_cat,
                              r.currency_code, 'ENABLED_FLAG',
                              r.enabled_flag, l_tgt_enab,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.currency_code, NULL,
                              r.enabled_flag, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(30);
            l_codes t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT currency_code FROM apps.fnd_currencies_vl@' || p_db_link ||
                ' WHERE enabled_flag = ''Y'' ' ||
                ' AND   currency_code NOT IN ' ||
                '  (SELECT currency_code FROM apps.fnd_currencies_vl WHERE enabled_flag=''Y'')'
            BULK COLLECT INTO l_codes;

            FOR i IN 1 .. l_codes.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_codes(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_currencies;

-- ============================================================
-- Languages
-- ============================================================

    PROCEDURE compare_languages (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'LANGUAGES';

        CURSOR c_src IS
            SELECT language_code, nls_language, installed_flag
            FROM   apps.fnd_languages
            WHERE  installed_flag IN ('B', 'I')  -- Base or Installed
            ORDER BY language_code;

        l_sql       VARCHAR2(1000);
        l_tgt_flag  VARCHAR2(1);
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT installed_flag FROM apps.fnd_languages@' || p_db_link ||
                ' WHERE language_code = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql INTO l_tgt_flag USING r.language_code;

                IF NVL(r.installed_flag,'<N>') != NVL(l_tgt_flag,'<N>') THEN
                    save_diff(p_run_id, l_cat,
                              r.language_code, 'INSTALLED_FLAG',
                              r.installed_flag, l_tgt_flag,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.language_code, NULL,
                              r.nls_language, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(30);
            l_codes t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT language_code FROM apps.fnd_languages@' || p_db_link ||
                ' WHERE installed_flag IN (''B'',''I'') ' ||
                ' AND   language_code NOT IN ' ||
                '  (SELECT language_code FROM apps.fnd_languages ' ||
                '   WHERE  installed_flag IN (''B'',''I''))'
            BULK COLLECT INTO l_codes;

            FOR i IN 1 .. l_codes.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_codes(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_languages;

-- ============================================================
-- Users  (active FND users)
-- ============================================================

    PROCEDURE compare_users (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    ) IS
        l_cat CONSTANT VARCHAR2(30) := 'FND_USERS';

        CURSOR c_src IS
            SELECT user_name, email_address,
                   NVL(end_date, DATE '9999-12-31') AS eff_end
            FROM   apps.fnd_user
            WHERE  NVL(end_date, DATE '9999-12-31') >= SYSDATE
            ORDER BY user_name;

        l_sql       VARCHAR2(1000);
        l_tgt_mail  VARCHAR2(500);
        l_tgt_end   DATE;
    BEGIN
        IF REGEXP_LIKE(p_db_link, '[^A-Za-z0-9_\.]') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Invalid DB link name');
        END IF;

        FOR r IN c_src LOOP
            l_sql :=
                'SELECT email_address, NVL(end_date, DATE ''9999-12-31'') ' ||
                'FROM   apps.fnd_user@' || p_db_link ||
                ' WHERE user_name = :1 AND ROWNUM = 1';
            BEGIN
                EXECUTE IMMEDIATE l_sql
                    INTO l_tgt_mail, l_tgt_end
                    USING r.user_name;

                IF NVL(r.email_address,'<N>') != NVL(l_tgt_mail,'<N>') THEN
                    save_diff(p_run_id, l_cat,
                              r.user_name, 'EMAIL',
                              r.email_address, l_tgt_mail,
                              'VALUE_DIFF');
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    save_diff(p_run_id, l_cat,
                              r.user_name, NULL,
                              r.email_address, NULL,
                              'ONLY_IN_SOURCE');
            END;
        END LOOP;

        DECLARE
            TYPE t_str IS TABLE OF VARCHAR2(200);
            l_names t_str;
        BEGIN
            EXECUTE IMMEDIATE
                'SELECT user_name FROM apps.fnd_user@' || p_db_link ||
                ' WHERE NVL(end_date, DATE ''9999-12-31'') >= SYSDATE ' ||
                ' AND   user_name NOT IN ' ||
                '  (SELECT user_name FROM apps.fnd_user ' ||
                '   WHERE  NVL(end_date, DATE ''9999-12-31'') >= SYSDATE)'
            BULK COLLECT INTO l_names;

            FOR i IN 1 .. l_names.COUNT LOOP
                save_diff(p_run_id, l_cat,
                          l_names(i), NULL, NULL, NULL, 'ONLY_IN_TARGET');
            END LOOP;
        END;
    END compare_users;

-- ============================================================
-- run_all  (two-arg version: returns run_id)
-- ============================================================

    PROCEDURE run_all (
        p_db_link  IN  VARCHAR2,
        p_run_id   OUT VARCHAR2
    ) IS
    BEGIN
        p_run_id := new_run_id;

        compare_profiles             (p_db_link, p_run_id);
        compare_lookups              (p_db_link, p_run_id);
        compare_responsibilities     (p_db_link, p_run_id);
        compare_concurrent_programs  (p_db_link, p_run_id);
        compare_flexfields           (p_db_link, p_run_id);
        compare_value_sets           (p_db_link, p_run_id);
        compare_organizations        (p_db_link, p_run_id);
        compare_ledgers              (p_db_link, p_run_id);
        compare_currencies           (p_db_link, p_run_id);
        compare_languages            (p_db_link, p_run_id);
        compare_users                (p_db_link, p_run_id);

        print_summary(p_run_id);
    END run_all;

-- ============================================================
-- run_all  (one-arg convenience wrapper)
-- ============================================================

    PROCEDURE run_all (
        p_db_link IN VARCHAR2
    ) IS
        l_run_id VARCHAR2(50);
    BEGIN
        run_all(p_db_link, l_run_id);
    END run_all;

-- ============================================================
-- print_summary
-- ============================================================

    PROCEDURE print_summary (
        p_run_id IN VARCHAR2
    ) IS
        CURSOR c IS
            SELECT category, diff_type, diff_count
            FROM   ebs_compare_summary
            WHERE  run_id = p_run_id
            ORDER BY category, diff_type;

        l_prev_cat VARCHAR2(100) := '~';
        l_total    NUMBER        := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('======================================================');
        DBMS_OUTPUT.PUT_LINE(' EBS Foundation Setup Comparison');
        DBMS_OUTPUT.PUT_LINE(' Run ID  : ' || p_run_id);
        DBMS_OUTPUT.PUT_LINE(' Date    : ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE('======================================================');

        FOR r IN c LOOP
            IF r.category != l_prev_cat THEN
                IF l_prev_cat != '~' THEN
                    DBMS_OUTPUT.PUT_LINE('');
                END IF;
                DBMS_OUTPUT.PUT_LINE('  ' || RPAD(r.category, 35));
                l_prev_cat := r.category;
            END IF;
            DBMS_OUTPUT.PUT_LINE('    ' ||
                RPAD('  ' || r.diff_type, 25) || ': ' || r.diff_count);
            l_total := l_total + r.diff_count;
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('  TOTAL DIFFERENCES : ' || l_total);
        DBMS_OUTPUT.PUT_LINE('======================================================');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Query results:');
        DBMS_OUTPUT.PUT_LINE('  SELECT * FROM ebs_compare_results');
        DBMS_OUTPUT.PUT_LINE('  WHERE run_id = ''' || p_run_id || ''';');
    END print_summary;

END compare_ebs_setup;
/
