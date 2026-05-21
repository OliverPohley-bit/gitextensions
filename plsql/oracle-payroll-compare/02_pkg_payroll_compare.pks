-- =============================================================================
-- Package specificatie: PKG_PAYROLL_COMPARE
-- =============================================================================
-- Doel   : Vergelijkt Oracle EBS HR Payroll setup én maatwerk code tussen de
--          lokale omgeving en een remote (PROD) omgeving via database link.
--
-- DB Link: PROD_LINK  -- verander g_db_link_display en alle @PROD_LINK verwijzingen
--          in de package body als uw database link anders heet.
--
-- Gebruik:
--   1. Pas eventueel g_custom_schema en g_custom_prefix aan
--   2. EXEC pkg_payroll_compare.run_all_comparisons;
--   3. EXEC pkg_payroll_compare.print_summary;
--      of: SELECT * FROM payroll_compare_results WHERE run_id = '<run_id>';
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_payroll_compare AUTHID CURRENT_USER AS

  -- ===========================================================================
  -- CONFIGURATIE  (pas aan indien nodig)
  -- ===========================================================================

  -- Weergavenaam van de database link (informatief in rapportage)
  g_db_link_display   VARCHAR2(50)  := 'PROD_LINK';

  -- Schema voor custom PL/SQL maatwerk (bv. 'APPS', 'XXCUST', 'XXHR')
  g_custom_schema     VARCHAR2(30)  := 'APPS';

  -- Prefix waarmee maatwerk objecten beginnen (bv. 'XX', 'CUST_')
  g_custom_prefix     VARCHAR2(10)  := 'XX';

  -- Business Group ID filter — NULL vergelijkt alle business groups
  g_business_grp_id   NUMBER        := NULL;

  -- Automatisch gegenereerde run identifier voor deze sessie
  g_run_id            VARCHAR2(50)  := TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS');

  -- ===========================================================================
  -- HOOFDPROCEDURE
  -- Voert alle vergelijkingen hieronder sequentieel uit
  -- ===========================================================================
  PROCEDURE run_all_comparisons;

  -- ===========================================================================
  -- SETUP VERGELIJKINGEN
  -- ===========================================================================
  PROCEDURE compare_pay_elements;        -- PAY_ELEMENT_TYPES_F
  PROCEDURE compare_element_links;       -- PAY_ELEMENT_LINKS_F
  PROCEDURE compare_payrolls;            -- PAY_ALL_PAYROLLS_F
  PROCEDURE compare_salary_basis;        -- PER_PAY_BASES
  PROCEDURE compare_balance_types;       -- PAY_BALANCE_TYPES
  PROCEDURE compare_fast_formula_setup;  -- FF_FORMULAS_F (definitie, niet code)

  -- ===========================================================================
  -- MAATWERK CODE VERGELIJKINGEN
  -- ===========================================================================
  PROCEDURE compare_fast_formula_text;   -- FF_FORMULA_TEXT (werkelijke formule code)
  PROCEDURE compare_plsql_source;        -- ALL_SOURCE (packages / procedures / functies)
  PROCEDURE compare_triggers;            -- ALL_TRIGGERS
  PROCEDURE compare_concurrent_programs; -- FND_CONCURRENT_PROGRAMS

  -- ===========================================================================
  -- BEVEILIGING & OVERIGE VERGELIJKINGEN
  -- ===========================================================================
  PROCEDURE compare_lookup_values;       -- FND_LOOKUP_VALUES (HR/Payroll lookups)
  PROCEDURE compare_profiles;            -- FND_PROFILE_OPTION_VALUES (HR/PAY profielen)
  PROCEDURE compare_users;               -- FND_USER (actieve gebruikers)
  PROCEDURE compare_responsibilities;    -- FND_RESPONSIBILITY_VL + toewijzingen

  -- ===========================================================================
  -- RAPPORTAGE
  -- ===========================================================================

  -- Druk gedetailleerd rapport af via DBMS_OUTPUT (SET SERVEROUTPUT ON SIZE UNL.)
  PROCEDURE print_report(
    p_category  VARCHAR2 DEFAULT NULL,   -- NULL = alle categorieën
    p_run_id    VARCHAR2 DEFAULT NULL    -- NULL = meest recente run
  );

  -- Druk een samenvatting per categorie/object type af
  PROCEDURE print_summary(
    p_run_id    VARCHAR2 DEFAULT NULL
  );

END pkg_payroll_compare;
/

SHOW ERRORS PACKAGE pkg_payroll_compare;
