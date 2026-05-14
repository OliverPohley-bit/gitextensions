-- ============================================================
-- EBS Foundation Setup Comparison - Supporting Objects
-- Run this script ONCE on the source environment.
-- ============================================================

-- Results table for all comparisons
CREATE TABLE ebs_compare_results (
    compare_id          NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id              VARCHAR2(36)   NOT NULL,
    run_date            DATE           DEFAULT SYSDATE NOT NULL,
    category            VARCHAR2(100)  NOT NULL,   -- e.g. 'PROFILE_OPTIONS'
    object_name         VARCHAR2(500)  NOT NULL,
    attribute_name      VARCHAR2(255),
    source_value        VARCHAR2(4000),
    target_value        VARCHAR2(4000),
    diff_type           VARCHAR2(30)   NOT NULL,   -- ONLY_IN_SOURCE | ONLY_IN_TARGET | VALUE_DIFF
    notes               VARCHAR2(1000)
);

CREATE INDEX ebs_compare_results_run_idx  ON ebs_compare_results (run_id);
CREATE INDEX ebs_compare_results_cat_idx  ON ebs_compare_results (category);

-- Summary view
CREATE OR REPLACE VIEW ebs_compare_summary AS
SELECT
    run_id,
    run_date,
    category,
    diff_type,
    COUNT(*) AS diff_count
FROM ebs_compare_results
GROUP BY run_id, run_date, category, diff_type
ORDER BY run_date DESC, category, diff_type;

-- Helper: grant SELECT on key FND/HR/GL views to the running schema if needed
-- GRANT SELECT ON apps.fnd_profile_options           TO <schema>;
-- GRANT SELECT ON apps.fnd_profile_option_values     TO <schema>;
-- GRANT SELECT ON apps.fnd_lookup_types_vl            TO <schema>;
-- GRANT SELECT ON apps.fnd_lookup_values_vl           TO <schema>;
-- GRANT SELECT ON apps.fnd_responsibility_vl          TO <schema>;
-- GRANT SELECT ON apps.fnd_user                       TO <schema>;
-- GRANT SELECT ON apps.fnd_concurrent_programs_vl     TO <schema>;
-- GRANT SELECT ON apps.fnd_id_flexs                   TO <schema>;
-- GRANT SELECT ON apps.fnd_descriptive_flexs_vl       TO <schema>;
-- GRANT SELECT ON apps.fnd_flex_value_sets            TO <schema>;
-- GRANT SELECT ON apps.hr_all_organization_units      TO <schema>;
-- GRANT SELECT ON apps.hr_operating_units             TO <schema>;
-- GRANT SELECT ON apps.gl_ledgers                     TO <schema>;
-- GRANT SELECT ON apps.gl_period_sets                 TO <schema>;
-- GRANT SELECT ON apps.fnd_currencies_vl              TO <schema>;
-- GRANT SELECT ON apps.fnd_languages                  TO <schema>;
