CREATE OR REPLACE PACKAGE compare_ebs_setup AS
-- ============================================================
-- EBS Foundation Setup Comparison Package
--
-- Purpose : Compares foundation configuration between a source
--           EBS instance (local) and a target EBS instance
--           (reached via a database link).
--
-- Usage   :
--   BEGIN
--     compare_ebs_setup.run_all('MY_TARGET_DBLINK');
--   END;
--
--   Or run individual categories:
--   BEGIN
--     compare_ebs_setup.compare_profiles       ('MY_TARGET_DBLINK', l_run_id);
--     compare_ebs_setup.compare_lookups        ('MY_TARGET_DBLINK', l_run_id);
--   END;
--
-- Results are written to EBS_COMPARE_RESULTS and can be queried
-- via EBS_COMPARE_SUMMARY.
-- ============================================================

    -- Run every comparison category and return the run_id.
    PROCEDURE run_all (
        p_db_link   IN  VARCHAR2,
        p_run_id    OUT VARCHAR2
    );

    -- Shorthand: run all and print a summary to DBMS_OUTPUT.
    PROCEDURE run_all (
        p_db_link   IN VARCHAR2
    );

    -- Individual category procedures.
    -- Each accepts a DB-link name and the current run_id.
    PROCEDURE compare_profiles (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_lookups (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_responsibilities (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_concurrent_programs (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_flexfields (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_value_sets (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_organizations (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_ledgers (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_currencies (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_languages (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    PROCEDURE compare_users (
        p_db_link  IN VARCHAR2,
        p_run_id   IN VARCHAR2
    );

    -- Print a formatted summary for a completed run.
    PROCEDURE print_summary (
        p_run_id IN VARCHAR2
    );

END compare_ebs_setup;
/
