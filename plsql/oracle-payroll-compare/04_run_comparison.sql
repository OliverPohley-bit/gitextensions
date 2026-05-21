-- =============================================================================
-- Uitvoerscript: Oracle EBS HR Payroll Omgeving Vergelijking
-- =============================================================================
-- Voer dit uit als APPS gebruiker in SQL*Plus of SQL Developer:
--
--   SET SERVEROUTPUT ON SIZE UNLIMITED
--   @04_run_comparison.sql
--
-- Optioneel: filter op één business group
--   EXEC pkg_payroll_compare.g_business_grp_id := 81;
--
-- Optioneel: ander custom schema
--   EXEC pkg_payroll_compare.g_custom_schema := 'XXCUST';
--
-- Optioneel: ander custom prefix
--   EXEC pkg_payroll_compare.g_custom_prefix := 'CUST_';
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET LINESIZE 200
SET PAGESIZE 0

-- ===== STAP 1: Configuratie (pas aan indien gewenst) =====

-- Business group filter (weghalen = alle groups vergelijken)
-- EXEC pkg_payroll_compare.g_business_grp_id := NULL;

-- Custom code schema en prefix
-- EXEC pkg_payroll_compare.g_custom_schema  := 'APPS';
-- EXEC pkg_payroll_compare.g_custom_prefix  := 'XX';

-- ===== STAP 2: Vergelijking uitvoeren =====

PROMPT Vergelijking starten...
EXEC pkg_payroll_compare.run_all_comparisons;

-- ===== STAP 3: Detail-query's voor nabewerking =====

PROMPT
PROMPT Gebruik onderstaande query's voor details in uw eigen tool:
PROMPT

-- Alle verschillen van de laatste run
-- SELECT category, object_type, difference_type, object_name,
--        sub_object, local_value, remote_value, details
-- FROM   payroll_compare_results
-- WHERE  run_id = (SELECT MAX(run_id) FROM payroll_compare_results)
-- ORDER BY category, object_type, difference_type, object_name;

-- Alleen maatwerk code die verschilt
-- SELECT object_type, difference_type, object_name, sub_object, local_value, remote_value
-- FROM   payroll_compare_results
-- WHERE  run_id   = (SELECT MAX(run_id) FROM payroll_compare_results)
--   AND  category = 'MAATWERK'
-- ORDER BY object_type, object_name;

-- Samenvatting per run (meerdere runs vergelijken)
-- SELECT run_id, run_date, category, object_type,
--        SUM(CASE WHEN difference_type='LOKAAL_ALLEEN' THEN 1 ELSE 0 END) lokaal_alleen,
--        SUM(CASE WHEN difference_type='PROD_ALLEEN'   THEN 1 ELSE 0 END) prod_alleen,
--        SUM(CASE WHEN difference_type='VERSCHIL'      THEN 1 ELSE 0 END) verschil
-- FROM   payroll_compare_results
-- GROUP BY run_id, run_date, category, object_type
-- ORDER BY run_id DESC, category, object_type;

SET FEEDBACK ON
