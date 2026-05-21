-- =============================================================================
-- Package body: PKG_PAYROLL_COMPARE
-- Database link target: PROD_LINK
-- Zoek en vervang '@PROD_LINK' als uw link anders heet.
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY pkg_payroll_compare AS

  -- ===========================================================================
  -- Private helpers
  -- ===========================================================================

  PROCEDURE p_log(p_msg VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(p_msg);
  END p_log;

  PROCEDURE p_section(p_titel VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== ' || p_titel || ' ===');
  END p_section;

  -- ===========================================================================
  -- SETUP: Pay Elements
  -- Tabellen: PAY_ELEMENT_TYPES_F, PAY_ELEMENT_CLASSIFICATIONS
  -- ===========================================================================
  PROCEDURE compare_pay_elements IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Pay Elements (PAY_ELEMENT_TYPES_F)...');

    -- Elementen alleen lokaal aanwezig
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'PAY_ELEMENTS', 'LOKAAL_ALLEEN',
           l.element_name,
           'Classificatie: ' || c.classification_name ||
           ' | Type: '       || l.processing_type
    FROM   pay_element_types_f l
    JOIN   pay_element_classifications c
           ON c.classification_id = l.classification_id
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1
             FROM   pay_element_types_f@PROD_LINK r
             WHERE  r.element_name = l.element_name
               AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
               AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Elementen alleen in PROD aanwezig
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'PAY_ELEMENTS', 'PROD_ALLEEN',
           r.element_name,
           'Classificatie: ' || c.classification_name ||
           ' | Type: '       || r.processing_type
    FROM   pay_element_types_f@PROD_LINK r
    JOIN   pay_element_classifications@PROD_LINK c
           ON c.classification_id = r.classification_id
    WHERE  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1
             FROM   pay_element_types_f l
             WHERE  l.element_name = r.element_name
               AND  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
               AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Elementen in beide maar met afwijkend processing_type
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'PAY_ELEMENTS', 'VERSCHIL',
           l.element_name, 'PROCESSING_TYPE',
           l.processing_type, r.processing_type
    FROM   pay_element_types_f l
    JOIN   pay_element_types_f@PROD_LINK r
           ON  r.element_name = l.element_name
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NVL(l.processing_type, '~') != NVL(r.processing_type, '~');

    -- Elementen in beide maar met afwijkende classificatie
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'PAY_ELEMENTS', 'VERSCHIL',
           l.element_name, 'CLASSIFICATIE',
           cl.classification_name, cr.classification_name
    FROM   pay_element_types_f l
    JOIN   pay_element_types_f@PROD_LINK r
           ON  r.element_name = l.element_name
    JOIN   pay_element_classifications cl
           ON  cl.classification_id = l.classification_id
    JOIN   pay_element_classifications@PROD_LINK cr
           ON  cr.classification_id = r.classification_id
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  cl.classification_name != cr.classification_name;

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_pay_elements: ' || SQLERRM);
      ROLLBACK;
  END compare_pay_elements;

  -- ===========================================================================
  -- SETUP: Element Links
  -- Tabellen: PAY_ELEMENT_LINKS_F
  -- ===========================================================================
  PROCEDURE compare_element_links IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Element Links (PAY_ELEMENT_LINKS_F)...');

    -- Links alleen lokaal (identificatie via element_link_id)
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'ELEMENT_LINKS', 'LOKAAL_ALLEEN',
           e.element_name || ' -> ' ||
           CASE l.link_to_all_payrolls_flag
             WHEN 'Y' THEN 'Alle Payrolls'
             ELSE NVL(p.payroll_name, NVL(og.name, 'Overig'))
           END,
           'Standaard link: ' || l.standard_link_flag ||
           ' | Alle payrolls: ' || l.link_to_all_payrolls_flag
    FROM   pay_element_links_f l
    JOIN   pay_element_types_f e
           ON  e.element_type_id = l.element_type_id
           AND TRUNC(SYSDATE) BETWEEN e.effective_start_date AND e.effective_end_date
    LEFT JOIN pay_all_payrolls_f p
           ON  p.payroll_id = l.payroll_id
           AND TRUNC(SYSDATE) BETWEEN p.effective_start_date AND p.effective_end_date
    LEFT JOIN hr_organization_units og
           ON  og.organization_id = l.organization_id
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_element_links_f@PROD_LINK r
             WHERE  r.element_link_id = l.element_link_id
               AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Links alleen in PROD
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'ELEMENT_LINKS', 'PROD_ALLEEN',
           e.element_name || ' -> ' ||
           CASE r.link_to_all_payrolls_flag
             WHEN 'Y' THEN 'Alle Payrolls'
             ELSE NVL(p.payroll_name, 'Overig')
           END,
           'Standaard link: ' || r.standard_link_flag ||
           ' | Alle payrolls: ' || r.link_to_all_payrolls_flag
    FROM   pay_element_links_f@PROD_LINK r
    JOIN   pay_element_types_f@PROD_LINK e
           ON  e.element_type_id = r.element_type_id
           AND TRUNC(SYSDATE) BETWEEN e.effective_start_date AND e.effective_end_date
    LEFT JOIN pay_all_payrolls_f@PROD_LINK p
           ON  p.payroll_id = r.payroll_id
           AND TRUNC(SYSDATE) BETWEEN p.effective_start_date AND p.effective_end_date
    WHERE  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_element_links_f l
             WHERE  l.element_link_id = r.element_link_id
               AND  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Links in beide maar standard_link_flag verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'ELEMENT_LINKS', 'VERSCHIL',
           e.element_name, 'STANDARD_LINK_FLAG',
           l.standard_link_flag, r.standard_link_flag
    FROM   pay_element_links_f l
    JOIN   pay_element_links_f@PROD_LINK r
           ON  r.element_link_id = l.element_link_id
    JOIN   pay_element_types_f e
           ON  e.element_type_id = l.element_type_id
           AND TRUNC(SYSDATE) BETWEEN e.effective_start_date AND e.effective_end_date
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NVL(l.standard_link_flag, '~') != NVL(r.standard_link_flag, '~');

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_element_links: ' || SQLERRM);
      ROLLBACK;
  END compare_element_links;

  -- ===========================================================================
  -- SETUP: Payrolls
  -- Tabellen: PAY_ALL_PAYROLLS_F
  -- ===========================================================================
  PROCEDURE compare_payrolls IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Payrolls (PAY_ALL_PAYROLLS_F)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'PAYROLLS', 'LOKAAL_ALLEEN',
           l.payroll_name,
           'Periode type: ' || l.period_type
    FROM   pay_all_payrolls_f l
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_all_payrolls_f@PROD_LINK r
             WHERE  r.payroll_name = l.payroll_name
               AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
               AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'PAYROLLS', 'PROD_ALLEEN',
           r.payroll_name,
           'Periode type: ' || r.period_type
    FROM   pay_all_payrolls_f@PROD_LINK r
    WHERE  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_all_payrolls_f l
             WHERE  l.payroll_name = r.payroll_name
               AND  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
               AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Periode type verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'PAYROLLS', 'VERSCHIL',
           l.payroll_name, 'PERIOD_TYPE',
           l.period_type, r.period_type
    FROM   pay_all_payrolls_f l
    JOIN   pay_all_payrolls_f@PROD_LINK r
           ON  r.payroll_name = l.payroll_name
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NVL(l.period_type, '~') != NVL(r.period_type, '~');

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_payrolls: ' || SQLERRM);
      ROLLBACK;
  END compare_payrolls;

  -- ===========================================================================
  -- SETUP: Salary Basis
  -- Tabellen: PER_PAY_BASES
  -- ===========================================================================
  PROCEDURE compare_salary_basis IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Salary Basis (PER_PAY_BASES)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'SALARY_BASIS', 'LOKAAL_ALLEEN',
           l.name,
           'Basis: ' || l.pay_basis || ' | Element: ' ||
           (SELECT e.element_name
            FROM   pay_element_types_f e
            WHERE  e.element_type_id = l.element_type_id
              AND  TRUNC(SYSDATE) BETWEEN e.effective_start_date AND e.effective_end_date
              AND  ROWNUM = 1)
    FROM   per_pay_bases l
    WHERE  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM per_pay_bases@PROD_LINK r
             WHERE  r.name = l.name
               AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'SALARY_BASIS', 'PROD_ALLEEN',
           r.name,
           'Basis: ' || r.pay_basis
    FROM   per_pay_bases@PROD_LINK r
    WHERE  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM per_pay_bases l
             WHERE  l.name = r.name
               AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- pay_basis verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'SALARY_BASIS', 'VERSCHIL',
           l.name, 'PAY_BASIS',
           l.pay_basis, r.pay_basis
    FROM   per_pay_bases l
    JOIN   per_pay_bases@PROD_LINK r ON r.name = l.name
    WHERE  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NVL(l.pay_basis, '~') != NVL(r.pay_basis, '~');

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_salary_basis: ' || SQLERRM);
      ROLLBACK;
  END compare_salary_basis;

  -- ===========================================================================
  -- SETUP: Balance Types
  -- Tabellen: PAY_BALANCE_TYPES
  -- ===========================================================================
  PROCEDURE compare_balance_types IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Balance Types (PAY_BALANCE_TYPES)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'BALANCE_TYPES', 'LOKAAL_ALLEEN',
           l.balance_name,
           'UOM: ' || l.balance_uom ||
           ' | Remuneration: ' || l.assignment_remuneration_flag
    FROM   pay_balance_types l
    WHERE  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_balance_types@PROD_LINK r
             WHERE  r.balance_name = l.balance_name
               AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'BALANCE_TYPES', 'PROD_ALLEEN',
           r.balance_name,
           'UOM: ' || r.balance_uom
    FROM   pay_balance_types@PROD_LINK r
    WHERE  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM pay_balance_types l
             WHERE  l.balance_name = r.balance_name
               AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- UOM verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'SETUP', 'BALANCE_TYPES', 'VERSCHIL',
           l.balance_name, 'BALANCE_UOM',
           l.balance_uom, r.balance_uom
    FROM   pay_balance_types l
    JOIN   pay_balance_types@PROD_LINK r ON r.balance_name = l.balance_name
    WHERE  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NVL(l.balance_uom, '~') != NVL(r.balance_uom, '~');

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_balance_types: ' || SQLERRM);
      ROLLBACK;
  END compare_balance_types;

  -- ===========================================================================
  -- SETUP: Fast Formula Definities (metadata, niet de code zelf)
  -- Tabellen: FF_FORMULAS_F, FF_FORMULA_TYPES
  -- ===========================================================================
  PROCEDURE compare_fast_formula_setup IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Fast Formula definities (FF_FORMULAS_F)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'FAST_FORMULA_DEF', 'LOKAAL_ALLEEN',
           l.formula_name,
           'Type: ' || ft.formula_type_name
    FROM   ff_formulas_f l
    JOIN   ff_formula_types ft ON ft.formula_type_id = l.formula_type_id
    WHERE  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
      AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM ff_formulas_f@PROD_LINK r
             WHERE  r.formula_name = l.formula_name
               AND  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
               AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'SETUP', 'FAST_FORMULA_DEF', 'PROD_ALLEEN',
           r.formula_name,
           'Type: ' || ft.formula_type_name
    FROM   ff_formulas_f@PROD_LINK r
    JOIN   ff_formula_types@PROD_LINK ft ON ft.formula_type_id = r.formula_type_id
    WHERE  TRUNC(SYSDATE) BETWEEN r.effective_start_date AND r.effective_end_date
      AND  (g_business_grp_id IS NULL OR r.business_group_id = g_business_grp_id)
      AND  NOT EXISTS (
             SELECT 1 FROM ff_formulas_f l
             WHERE  l.formula_name = r.formula_name
               AND  TRUNC(SYSDATE) BETWEEN l.effective_start_date AND l.effective_end_date
               AND  (g_business_grp_id IS NULL OR l.business_group_id = g_business_grp_id)
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_fast_formula_setup: ' || SQLERRM);
      ROLLBACK;
  END compare_fast_formula_setup;

  -- ===========================================================================
  -- MAATWERK: Fast Formula Code
  -- Tabellen: FF_FORMULAS_F, FF_FORMULA_TEXT
  -- Checksum via SUM(ORA_HASH) per regel — werkt ook bij grote formules
  -- ===========================================================================
  PROCEDURE compare_fast_formula_text IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Fast Formula code (FF_FORMULA_TEXT)...');

    -- Formules waarbij de tekst inhoudelijk verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'FAST_FORMULA_CODE', 'VERSCHIL',
           lf.formula_name,
           'Regels lokaal: ' || lf.line_count ||
           ' | Regels PROD: ' || rf.line_count
    FROM (
      SELECT f.formula_id, f.formula_name,
             COUNT(ft.line_number)          AS line_count,
             SUM(ORA_HASH(TRIM(ft.text)))   AS code_hash
      FROM   ff_formulas_f f
      JOIN   ff_formula_text ft ON ft.formula_id = f.formula_id
      WHERE  TRUNC(SYSDATE) BETWEEN f.effective_start_date AND f.effective_end_date
        AND  (g_business_grp_id IS NULL OR f.business_group_id = g_business_grp_id)
      GROUP BY f.formula_id, f.formula_name
    ) lf
    JOIN (
      SELECT f.formula_id, f.formula_name,
             COUNT(ft.line_number)          AS line_count,
             SUM(ORA_HASH(TRIM(ft.text)))   AS code_hash
      FROM   ff_formulas_f@PROD_LINK f
      JOIN   ff_formula_text@PROD_LINK ft ON ft.formula_id = f.formula_id
      WHERE  TRUNC(SYSDATE) BETWEEN f.effective_start_date AND f.effective_end_date
        AND  (g_business_grp_id IS NULL OR f.business_group_id = g_business_grp_id)
      GROUP BY f.formula_id, f.formula_name
    ) rf ON rf.formula_name = lf.formula_name
    WHERE  lf.code_hash  != rf.code_hash
       OR  lf.line_count != rf.line_count;

    v_cnt := SQL%ROWCOUNT;
    p_log('    Formules met code-verschil: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_fast_formula_text: ' || SQLERRM);
      ROLLBACK;
  END compare_fast_formula_text;

  -- ===========================================================================
  -- MAATWERK: PL/SQL Source Code
  -- Tabellen: ALL_SOURCE
  -- Vergelijkt packages, procedures, functies en types in g_custom_schema
  -- Checksum via SUM(ORA_HASH(text)) — voorkomt LISTAGG lengte limieten
  -- ===========================================================================
  PROCEDURE compare_plsql_source IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: PL/SQL code (ALL_SOURCE, schema: ' ||
          g_custom_schema || ', prefix: ' || g_custom_prefix || '*)...');

    -- Objecten alleen lokaal aanwezig
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'PLSQL_SOURCE', 'LOKAAL_ALLEEN',
           l.name, 'Type: ' || l.type
    FROM (
      SELECT DISTINCT name, type
      FROM   all_source
      WHERE  owner = g_custom_schema
        AND  name  LIKE g_custom_prefix || '%'
        AND  type  IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TYPE','TYPE BODY')
    ) l
    WHERE NOT EXISTS (
      SELECT 1 FROM all_source@PROD_LINK r
      WHERE  r.owner = g_custom_schema
        AND  r.name  = l.name
        AND  r.type  = l.type
        AND  ROWNUM  = 1
    );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Objecten alleen in PROD aanwezig
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'PLSQL_SOURCE', 'PROD_ALLEEN',
           r.name, 'Type: ' || r.type
    FROM (
      SELECT DISTINCT name, type
      FROM   all_source@PROD_LINK
      WHERE  owner = g_custom_schema
        AND  name  LIKE g_custom_prefix || '%'
        AND  type  IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TYPE','TYPE BODY')
    ) r
    WHERE NOT EXISTS (
      SELECT 1 FROM all_source l
      WHERE  l.owner = g_custom_schema
        AND  l.name  = r.name
        AND  l.type  = r.type
        AND  ROWNUM  = 1
    );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Objecten in beide maar code verschilt (checksum vergelijking)
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'MAATWERK', 'PLSQL_SOURCE', 'VERSCHIL',
           ls.name, ls.type,
           'Regels: ' || ls.line_count,
           'Regels: ' || rs.line_count
    FROM (
      SELECT name, type,
             COUNT(*)                  AS line_count,
             SUM(ORA_HASH(TRIM(text))) AS code_hash
      FROM   all_source
      WHERE  owner = g_custom_schema
        AND  name  LIKE g_custom_prefix || '%'
        AND  type  IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TYPE','TYPE BODY')
      GROUP BY name, type
    ) ls
    JOIN (
      SELECT name, type,
             COUNT(*)                  AS line_count,
             SUM(ORA_HASH(TRIM(text))) AS code_hash
      FROM   all_source@PROD_LINK
      WHERE  owner = g_custom_schema
        AND  name  LIKE g_custom_prefix || '%'
        AND  type  IN ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TYPE','TYPE BODY')
      GROUP BY name, type
    ) rs ON rs.name = ls.name AND rs.type = ls.type
    WHERE  ls.code_hash  != rs.code_hash
       OR  ls.line_count != rs.line_count;

    v_cnt := SQL%ROWCOUNT;
    p_log('    Objecten met code-verschil: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_plsql_source: ' || SQLERRM);
      ROLLBACK;
  END compare_plsql_source;

  -- ===========================================================================
  -- MAATWERK: Database Triggers
  -- Tabellen: ALL_TRIGGERS
  -- ===========================================================================
  PROCEDURE compare_triggers IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Triggers (ALL_TRIGGERS, schema: ' || g_custom_schema || ')...');

    -- Triggers alleen lokaal
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'TRIGGERS', 'LOKAAL_ALLEEN',
           l.trigger_name,
           'Op: ' || l.table_owner || '.' || l.table_name ||
           ' | Type: ' || l.trigger_type ||
           ' | Events: ' || l.triggering_event
    FROM   all_triggers l
    WHERE  l.owner = g_custom_schema
      AND  NOT EXISTS (
             SELECT 1 FROM all_triggers@PROD_LINK r
             WHERE  r.owner = g_custom_schema
               AND  r.trigger_name = l.trigger_name
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Triggers alleen in PROD
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'TRIGGERS', 'PROD_ALLEEN',
           r.trigger_name,
           'Op: ' || r.table_owner || '.' || r.table_name ||
           ' | Type: ' || r.trigger_type ||
           ' | Events: ' || r.triggering_event
    FROM   all_triggers@PROD_LINK r
    WHERE  r.owner = g_custom_schema
      AND  NOT EXISTS (
             SELECT 1 FROM all_triggers l
             WHERE  l.owner = g_custom_schema
               AND  l.trigger_name = r.trigger_name
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Trigger body verschilt (via ORA_HASH van trigger_body CLOB)
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'TRIGGERS', 'VERSCHIL',
           l.trigger_name,
           'Trigger body inhoud verschilt' ||
           CASE WHEN l.status != r.status
                THEN ' | Status lokaal: ' || l.status || ', PROD: ' || r.status
                ELSE NULL
           END
    FROM   all_triggers l
    JOIN   all_triggers@PROD_LINK r
           ON  r.owner = l.owner
           AND r.trigger_name = l.trigger_name
    WHERE  l.owner = g_custom_schema
      AND  (ORA_HASH(l.trigger_body)  != ORA_HASH(r.trigger_body)
         OR NVL(l.status, '~')        != NVL(r.status, '~'));

    v_cnt := SQL%ROWCOUNT;
    p_log('    Triggers met verschil: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_triggers: ' || SQLERRM);
      ROLLBACK;
  END compare_triggers;

  -- ===========================================================================
  -- MAATWERK: Concurrent Programs
  -- Tabellen: FND_CONCURRENT_PROGRAMS, FND_CONCURRENT_PROGRAMS_TL
  -- Gefilterd op g_custom_prefix
  -- ===========================================================================
  PROCEDURE compare_concurrent_programs IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Concurrent Programs (FND_CONCURRENT_PROGRAMS, prefix: ' ||
          g_custom_prefix || '*)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'CONCURRENT_PROGRAMS', 'LOKAAL_ALLEEN',
           l.concurrent_program_name,
           'Naam: ' || lt.user_concurrent_program_name
    FROM   fnd_concurrent_programs l
    LEFT JOIN fnd_concurrent_programs_tl lt
           ON  lt.concurrent_program_id = l.concurrent_program_id
           AND lt.language = 'NL'
    WHERE  l.concurrent_program_name LIKE g_custom_prefix || '%'
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_concurrent_programs@PROD_LINK r
             WHERE  r.concurrent_program_name = l.concurrent_program_name
               AND  r.application_id = l.application_id
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'MAATWERK', 'CONCURRENT_PROGRAMS', 'PROD_ALLEEN',
           r.concurrent_program_name,
           'Naam: ' || rt.user_concurrent_program_name
    FROM   fnd_concurrent_programs@PROD_LINK r
    LEFT JOIN fnd_concurrent_programs_tl@PROD_LINK rt
           ON  rt.concurrent_program_id = r.concurrent_program_id
           AND rt.language = 'NL'
    WHERE  r.concurrent_program_name LIKE g_custom_prefix || '%'
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_concurrent_programs l
             WHERE  l.concurrent_program_name = r.concurrent_program_name
               AND  l.application_id = r.application_id
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Executable of output type verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'MAATWERK', 'CONCURRENT_PROGRAMS', 'VERSCHIL',
           l.concurrent_program_name, 'OUTPUT_FILE_TYPE',
           l.output_file_type, r.output_file_type
    FROM   fnd_concurrent_programs l
    JOIN   fnd_concurrent_programs@PROD_LINK r
           ON  r.concurrent_program_name = l.concurrent_program_name
           AND r.application_id = l.application_id
    WHERE  l.concurrent_program_name LIKE g_custom_prefix || '%'
      AND  NVL(l.output_file_type, '~') != NVL(r.output_file_type, '~');

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_concurrent_programs: ' || SQLERRM);
      ROLLBACK;
  END compare_concurrent_programs;

  -- ===========================================================================
  -- BEVEILIGING: Lookup Values
  -- Tabellen: FND_LOOKUP_VALUES
  -- Gefilterd op HR/Payroll applicaties (app_id 800, 801, 809)
  -- ===========================================================================
  PROCEDURE compare_lookup_values IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Lookup Values (FND_LOOKUP_VALUES, HR/Payroll)...');

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'LOOKUP_VALUES', 'LOKAAL_ALLEEN',
           l.lookup_type || ' | ' || l.lookup_code,
           'Betekenis: ' || l.meaning
    FROM   fnd_lookup_values l
    WHERE  l.language              = USERENV('LANG')
      AND  l.view_application_id  IN (800, 801, 809)
      AND  TRUNC(SYSDATE) BETWEEN NVL(l.start_date_active, TRUNC(SYSDATE))
                                 AND NVL(l.end_date_active, TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_lookup_values@PROD_LINK r
             WHERE  r.lookup_type = l.lookup_type
               AND  r.lookup_code = l.lookup_code
               AND  r.language    = l.language
               AND  r.view_application_id IN (800, 801, 809)
               AND  TRUNC(SYSDATE) BETWEEN NVL(r.start_date_active, TRUNC(SYSDATE))
                                          AND NVL(r.end_date_active, TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'LOOKUP_VALUES', 'PROD_ALLEEN',
           r.lookup_type || ' | ' || r.lookup_code,
           'Betekenis: ' || r.meaning
    FROM   fnd_lookup_values@PROD_LINK r
    WHERE  r.language              = USERENV('LANG')
      AND  r.view_application_id  IN (800, 801, 809)
      AND  TRUNC(SYSDATE) BETWEEN NVL(r.start_date_active, TRUNC(SYSDATE))
                                 AND NVL(r.end_date_active, TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_lookup_values l
             WHERE  l.lookup_type = r.lookup_type
               AND  l.lookup_code = r.lookup_code
               AND  l.language    = r.language
               AND  l.view_application_id IN (800, 801, 809)
               AND  TRUNC(SYSDATE) BETWEEN NVL(l.start_date_active, TRUNC(SYSDATE))
                                          AND NVL(l.end_date_active, TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Meaning verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'BEVEILIGING', 'LOOKUP_VALUES', 'VERSCHIL',
           l.lookup_type || ' | ' || l.lookup_code, 'MEANING',
           l.meaning, r.meaning
    FROM   fnd_lookup_values l
    JOIN   fnd_lookup_values@PROD_LINK r
           ON  r.lookup_type = l.lookup_type
           AND r.lookup_code = l.lookup_code
           AND r.language    = l.language
    WHERE  l.language             = USERENV('LANG')
      AND  l.view_application_id IN (800, 801, 809)
      AND  TRUNC(SYSDATE) BETWEEN NVL(l.start_date_active, TRUNC(SYSDATE))
                                 AND NVL(l.end_date_active, TRUNC(SYSDATE))
      AND  TRUNC(SYSDATE) BETWEEN NVL(r.start_date_active, TRUNC(SYSDATE))
                                 AND NVL(r.end_date_active, TRUNC(SYSDATE))
      AND  NVL(l.meaning, '~') != NVL(r.meaning, '~');

    v_cnt := SQL%ROWCOUNT;
    p_log('    Lookup values met verschil: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_lookup_values: ' || SQLERRM);
      ROLLBACK;
  END compare_lookup_values;

  -- ===========================================================================
  -- BEVEILIGING: Profielen
  -- Tabellen: FND_PROFILE_OPTIONS, FND_PROFILE_OPTION_VALUES
  -- Gefilterd op HR% en PAY% profielen
  -- ===========================================================================
  PROCEDURE compare_profiles IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Profielen (FND_PROFILE_OPTION_VALUES, HR%/PAY%)...');

    -- Profielwaarden alleen lokaal
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'PROFIELEN', 'LOKAAL_ALLEEN',
           po.profile_option_name,
           'Niveau: ' || DECODE(pov.level_id,
             10001, 'Site',
             10002, 'Applicatie',
             10003, 'Verantwoordelijkheid',
             10004, 'Gebruiker',
             TO_CHAR(pov.level_id)) ||
           ' | Waarde: ' || SUBSTR(pov.profile_option_value, 1, 200)
    FROM   fnd_profile_option_values pov
    JOIN   fnd_profile_options po
           ON  po.profile_option_id   = pov.profile_option_id
           AND po.application_id      = pov.application_id
    WHERE  (po.profile_option_name LIKE 'HR%' OR po.profile_option_name LIKE 'PAY%')
      AND  NOT EXISTS (
             SELECT 1
             FROM   fnd_profile_option_values@PROD_LINK pov2
             JOIN   fnd_profile_options@PROD_LINK po2
                    ON  po2.profile_option_id = pov2.profile_option_id
                    AND po2.application_id    = pov2.application_id
             WHERE  po2.profile_option_name = po.profile_option_name
               AND  pov2.level_id           = pov.level_id
               AND  pov2.level_value        = pov.level_value
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Profielwaarden alleen in PROD
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'PROFIELEN', 'PROD_ALLEEN',
           po.profile_option_name,
           'Niveau: ' || DECODE(pov.level_id,
             10001, 'Site',
             10002, 'Applicatie',
             10003, 'Verantwoordelijkheid',
             10004, 'Gebruiker',
             TO_CHAR(pov.level_id)) ||
           ' | Waarde: ' || SUBSTR(pov.profile_option_value, 1, 200)
    FROM   fnd_profile_option_values@PROD_LINK pov
    JOIN   fnd_profile_options@PROD_LINK po
           ON  po.profile_option_id   = pov.profile_option_id
           AND po.application_id      = pov.application_id
    WHERE  (po.profile_option_name LIKE 'HR%' OR po.profile_option_name LIKE 'PAY%')
      AND  NOT EXISTS (
             SELECT 1
             FROM   fnd_profile_option_values pov2
             JOIN   fnd_profile_options po2
                    ON  po2.profile_option_id = pov2.profile_option_id
                    AND po2.application_id    = pov2.application_id
             WHERE  po2.profile_option_name = po.profile_option_name
               AND  pov2.level_id           = pov.level_id
               AND  pov2.level_value        = pov.level_value
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    -- Zelfde sleutel maar waarde verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'BEVEILIGING', 'PROFIELEN', 'VERSCHIL',
           po_l.profile_option_name,
           DECODE(pov_l.level_id, 10001,'Site',10002,'App',10003,'Resp',10004,'User',
                  TO_CHAR(pov_l.level_id)),
           SUBSTR(pov_l.profile_option_value, 1, 500),
           SUBSTR(pov_r.profile_option_value, 1, 500)
    FROM   fnd_profile_option_values pov_l
    JOIN   fnd_profile_options po_l
           ON  po_l.profile_option_id = pov_l.profile_option_id
           AND po_l.application_id    = pov_l.application_id
    JOIN   fnd_profile_option_values@PROD_LINK pov_r
           ON  pov_r.level_id    = pov_l.level_id
           AND pov_r.level_value = pov_l.level_value
    JOIN   fnd_profile_options@PROD_LINK po_r
           ON  po_r.profile_option_id = pov_r.profile_option_id
           AND po_r.application_id    = pov_r.application_id
           AND po_r.profile_option_name = po_l.profile_option_name
    WHERE  (po_l.profile_option_name LIKE 'HR%' OR po_l.profile_option_name LIKE 'PAY%')
      AND  NVL(pov_l.profile_option_value, '~') != NVL(pov_r.profile_option_value, '~');

    v_cnt := SQL%ROWCOUNT;
    p_log('    Profielen met afwijkende waarde: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_profiles: ' || SQLERRM);
      ROLLBACK;
  END compare_profiles;

  -- ===========================================================================
  -- BEVEILIGING: Gebruikers
  -- Tabellen: FND_USER
  -- Vergelijkt actieve gebruikers (end_date IS NULL of in de toekomst)
  -- ===========================================================================
  PROCEDURE compare_users IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Gebruikers (FND_USER)...');

    -- Gebruikers alleen lokaal actief
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'USERS', 'LOKAAL_ALLEEN',
           l.user_name,
           'Email: ' || l.email_address ||
           ' | Actief van: ' || TO_CHAR(l.start_date, 'DD-MM-YYYY')
    FROM   fnd_user l
    WHERE  TRUNC(SYSDATE) >= TRUNC(l.start_date)
      AND  (l.end_date IS NULL OR TRUNC(l.end_date) > TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_user@PROD_LINK r
             WHERE  r.user_name = l.user_name
               AND  TRUNC(SYSDATE) >= TRUNC(r.start_date)
               AND  (r.end_date IS NULL OR TRUNC(r.end_date) > TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal actief:  ' || v_cnt);

    -- Gebruikers alleen in PROD actief
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'USERS', 'PROD_ALLEEN',
           r.user_name,
           'Email: ' || r.email_address ||
           ' | Actief van: ' || TO_CHAR(r.start_date, 'DD-MM-YYYY')
    FROM   fnd_user@PROD_LINK r
    WHERE  TRUNC(SYSDATE) >= TRUNC(r.start_date)
      AND  (r.end_date IS NULL OR TRUNC(r.end_date) > TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_user l
             WHERE  l.user_name = r.user_name
               AND  TRUNC(SYSDATE) >= TRUNC(l.start_date)
               AND  (l.end_date IS NULL OR TRUNC(l.end_date) > TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD actief: ' || v_cnt);

    -- Gebruikers in beide maar e-mail verschilt
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name,
       sub_object, local_value, remote_value)
    SELECT g_run_id, 'BEVEILIGING', 'USERS', 'VERSCHIL',
           l.user_name, 'EMAIL_ADDRESS',
           l.email_address, r.email_address
    FROM   fnd_user l
    JOIN   fnd_user@PROD_LINK r ON r.user_name = l.user_name
    WHERE  TRUNC(SYSDATE) >= TRUNC(l.start_date)
      AND  (l.end_date IS NULL OR TRUNC(l.end_date) > TRUNC(SYSDATE))
      AND  TRUNC(SYSDATE) >= TRUNC(r.start_date)
      AND  (r.end_date IS NULL OR TRUNC(r.end_date) > TRUNC(SYSDATE))
      AND  NVL(l.email_address, '~') != NVL(r.email_address, '~');

    v_cnt := SQL%ROWCOUNT;
    p_log('    Gebruikers met verschil: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_users: ' || SQLERRM);
      ROLLBACK;
  END compare_users;

  -- ===========================================================================
  -- BEVEILIGING: Verantwoordelijkheden (Responsibilities)
  -- Tabellen: FND_RESPONSIBILITY_VL, FND_USER_RESP_GROUPS_DIRECT
  -- ===========================================================================
  PROCEDURE compare_responsibilities IS
    v_cnt PLS_INTEGER;
  BEGIN
    p_log('  Vergelijken: Verantwoordelijkheden (FND_RESPONSIBILITY_VL)...');

    -- Responsibilities alleen lokaal
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'RESPONSIBILITIES', 'LOKAAL_ALLEEN',
           l.responsibility_name,
           'Sleutel: ' || l.responsibility_key ||
           ' | App: '  || fa.application_short_name
    FROM   fnd_responsibility_vl l
    JOIN   fnd_application fa ON fa.application_id = l.application_id
    WHERE  TRUNC(SYSDATE) BETWEEN NVL(l.start_date, TRUNC(SYSDATE))
                                 AND NVL(l.end_date, TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_responsibility_vl@PROD_LINK r
             WHERE  r.responsibility_key = l.responsibility_key
               AND  r.application_id    = l.application_id
               AND  TRUNC(SYSDATE) BETWEEN NVL(r.start_date, TRUNC(SYSDATE))
                                          AND NVL(r.end_date, TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen lokaal:  ' || v_cnt);

    -- Responsibilities alleen in PROD
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'RESPONSIBILITIES', 'PROD_ALLEEN',
           r.responsibility_name,
           'Sleutel: ' || r.responsibility_key ||
           ' | App: '  || fa.application_short_name
    FROM   fnd_responsibility_vl@PROD_LINK r
    JOIN   fnd_application@PROD_LINK fa ON fa.application_id = r.application_id
    WHERE  TRUNC(SYSDATE) BETWEEN NVL(r.start_date, TRUNC(SYSDATE))
                                 AND NVL(r.end_date, TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1 FROM fnd_responsibility_vl l
             WHERE  l.responsibility_key = r.responsibility_key
               AND  l.application_id    = r.application_id
               AND  TRUNC(SYSDATE) BETWEEN NVL(l.start_date, TRUNC(SYSDATE))
                                          AND NVL(l.end_date, TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Alleen in PROD: ' || v_cnt);

    p_log('  Vergelijken: Gebruiker-Verantwoordelijkheid toewijzingen...');

    -- Gebruiker-responsibility toewijzingen alleen lokaal
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'USER_RESP_GROUPS', 'LOKAAL_ALLEEN',
           fu.user_name || ' -> ' || fr.responsibility_name,
           'Actief tot: ' || TO_CHAR(urg.end_date, 'DD-MM-YYYY')
    FROM   fnd_user_resp_groups_direct urg
    JOIN   fnd_user fu            ON fu.user_id             = urg.user_id
    JOIN   fnd_responsibility_vl fr
           ON  fr.responsibility_id = urg.responsibility_id
           AND fr.application_id    = urg.responsibility_application_id
    WHERE  (urg.end_date IS NULL OR TRUNC(urg.end_date) > TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1
             FROM   fnd_user_resp_groups_direct@PROD_LINK urg2
             JOIN   fnd_user@PROD_LINK fu2 ON fu2.user_id = urg2.user_id
             WHERE  fu2.user_name              = fu.user_name
               AND  urg2.responsibility_id     = urg.responsibility_id
               AND  urg2.responsibility_application_id
                                               = urg.responsibility_application_id
               AND  (urg2.end_date IS NULL OR TRUNC(urg2.end_date) > TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Toewijzingen alleen lokaal:  ' || v_cnt);

    -- Gebruiker-responsibility toewijzingen alleen in PROD
    INSERT INTO payroll_compare_results
      (run_id, category, object_type, difference_type, object_name, details)
    SELECT g_run_id, 'BEVEILIGING', 'USER_RESP_GROUPS', 'PROD_ALLEEN',
           fu.user_name || ' -> ' || fr.responsibility_name,
           'Actief tot: ' || TO_CHAR(urg.end_date, 'DD-MM-YYYY')
    FROM   fnd_user_resp_groups_direct@PROD_LINK urg
    JOIN   fnd_user@PROD_LINK fu ON fu.user_id = urg.user_id
    JOIN   fnd_responsibility_vl@PROD_LINK fr
           ON  fr.responsibility_id = urg.responsibility_id
           AND fr.application_id    = urg.responsibility_application_id
    WHERE  (urg.end_date IS NULL OR TRUNC(urg.end_date) > TRUNC(SYSDATE))
      AND  NOT EXISTS (
             SELECT 1
             FROM   fnd_user_resp_groups_direct urg2
             JOIN   fnd_user fu2 ON fu2.user_id = urg2.user_id
             WHERE  fu2.user_name              = fu.user_name
               AND  urg2.responsibility_id     = urg.responsibility_id
               AND  urg2.responsibility_application_id
                                               = urg.responsibility_application_id
               AND  (urg2.end_date IS NULL OR TRUNC(urg2.end_date) > TRUNC(SYSDATE))
           );
    v_cnt := SQL%ROWCOUNT;
    p_log('    Toewijzingen alleen in PROD: ' || v_cnt);

    COMMIT;
    p_log('    Klaar.');
  EXCEPTION
    WHEN OTHERS THEN
      p_log('  FOUT bij compare_responsibilities: ' || SQLERRM);
      ROLLBACK;
  END compare_responsibilities;

  -- ===========================================================================
  -- HOOFDPROCEDURE
  -- ===========================================================================
  PROCEDURE run_all_comparisons IS
    v_start DATE := SYSDATE;
  BEGIN
    -- Genereer een unieke run ID voor deze sessie
    g_run_id := TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');

    p_log('');
    p_log('=================================================================');
    p_log(' Oracle EBS HR Payroll Omgeving Vergelijking');
    p_log('=================================================================');
    p_log(' Run ID      : ' || g_run_id);
    p_log(' Lokaal      : ' || SYS_CONTEXT('USERENV','DB_NAME'));
    p_log(' Remote      : ' || g_db_link_display);
    p_log(' Schema      : ' || g_custom_schema);
    p_log(' BG Filter   : ' || NVL(TO_CHAR(g_business_grp_id), 'Alle'));
    p_log(' Maatwkpfix  : ' || g_custom_prefix || '*');
    p_log(' Tijdstip    : ' || TO_CHAR(SYSDATE, 'DD-MM-YYYY HH24:MI:SS'));
    p_log('=================================================================');

    p_section('SETUP');
    compare_pay_elements;
    compare_element_links;
    compare_payrolls;
    compare_salary_basis;
    compare_balance_types;
    compare_fast_formula_setup;

    p_section('MAATWERK CODE');
    compare_fast_formula_text;
    compare_plsql_source;
    compare_triggers;
    compare_concurrent_programs;

    p_section('BEVEILIGING');
    compare_lookup_values;
    compare_profiles;
    compare_users;
    compare_responsibilities;

    p_log('');
    p_log('Vergelijking voltooid in ' ||
          ROUND((SYSDATE - v_start) * 24 * 60, 1) || ' minuten.');
    p_log('');

    print_summary(g_run_id);
  END run_all_comparisons;

  -- ===========================================================================
  -- RAPPORTAGE: Samenvatting
  -- ===========================================================================
  PROCEDURE print_summary(p_run_id VARCHAR2 DEFAULT NULL) IS
    v_run_id VARCHAR2(50) := NVL(p_run_id, g_run_id);
    v_total  PLS_INTEGER  := 0;
  BEGIN
    p_log('');
    p_log('=================================================================');
    p_log(' SAMENVATTING  (run_id: ' || v_run_id || ')');
    p_log('=================================================================');
    p_log(RPAD('Categorie',          18) ||
          RPAD('Object type',        28) ||
          RPAD('Lokaal-alleen',      15) ||
          RPAD('PROD-alleen',        13) ||
          'Verschil');
    p_log(RPAD('-', 80, '-'));

    FOR r IN (
      SELECT category,
             object_type,
             SUM(CASE WHEN difference_type = 'LOKAAL_ALLEEN' THEN 1 ELSE 0 END) AS lokaal,
             SUM(CASE WHEN difference_type = 'PROD_ALLEEN'   THEN 1 ELSE 0 END) AS prod,
             SUM(CASE WHEN difference_type = 'VERSCHIL'      THEN 1 ELSE 0 END) AS verschil,
             COUNT(*)                                                             AS totaal
      FROM   payroll_compare_results
      WHERE  run_id = v_run_id
      GROUP BY category, object_type
      ORDER BY category, object_type
    ) LOOP
      p_log(RPAD(r.category,     18) ||
            RPAD(r.object_type,  28) ||
            RPAD(r.lokaal,       15) ||
            RPAD(r.prod,         13) ||
            r.verschil);
      v_total := v_total + r.totaal;
    END LOOP;

    p_log(RPAD('-', 80, '-'));
    p_log('Totaal aantal verschillen: ' || v_total);
    p_log('');
    p_log('Details opvragen:');
    p_log('  SELECT * FROM payroll_compare_results');
    p_log('  WHERE  run_id = ''' || v_run_id || '''');
    p_log('  ORDER BY category, object_type, difference_type, object_name;');
    p_log('');
  END print_summary;

  -- ===========================================================================
  -- RAPPORTAGE: Gedetailleerd rapport
  -- ===========================================================================
  PROCEDURE print_report(
    p_category VARCHAR2 DEFAULT NULL,
    p_run_id   VARCHAR2 DEFAULT NULL
  ) IS
    v_run_id  VARCHAR2(50) := NVL(p_run_id, g_run_id);
    v_prev_ot VARCHAR2(100);
  BEGIN
    p_log('');
    p_log('=================================================================');
    p_log(' GEDETAILLEERD RAPPORT  (run_id: ' || v_run_id || ')');
    p_log('=================================================================');

    FOR r IN (
      SELECT category, object_type, difference_type,
             object_name, sub_object, local_value, remote_value, details
      FROM   payroll_compare_results
      WHERE  run_id   = v_run_id
        AND  (p_category IS NULL OR category = p_category)
      ORDER BY category, object_type, difference_type, object_name
    ) LOOP
      IF NVL(v_prev_ot, '~') != r.object_type THEN
        p_log('');
        p_log('--- ' || r.category || ' / ' || r.object_type || ' ---');
        v_prev_ot := r.object_type;
      END IF;

      p_log('  [' || RPAD(r.difference_type, 14) || '] ' ||
            SUBSTR(r.object_name, 1, 60) ||
            CASE WHEN r.sub_object  IS NOT NULL THEN ' (' || r.sub_object || ')' END);

      IF r.local_value IS NOT NULL OR r.remote_value IS NOT NULL THEN
        p_log('    Lokaal : ' || SUBSTR(NVL(r.local_value,  '(leeg)'), 1, 100));
        p_log('    PROD   : ' || SUBSTR(NVL(r.remote_value, '(leeg)'), 1, 100));
      END IF;

      IF r.details IS NOT NULL THEN
        p_log('    Info   : ' || SUBSTR(r.details, 1, 120));
      END IF;
    END LOOP;

    p_log('');
  END print_report;

END pkg_payroll_compare;
/

SHOW ERRORS PACKAGE BODY pkg_payroll_compare;
