-- $BEGIN

-- update obs question UUIDs
UPDATE mamba_z_encounter_obs z
    INNER JOIN mamba_dim_concept_metadata md
    ON z.obs_question_concept_id = md.concept_id
SET z.obs_question_uuid = md.concept_uuid
WHERE TRUE;

-- update obs_value_coded (UUIDs & Concept value names)
UPDATE mamba_z_encounter_obs z
    INNER JOIN mamba_dim_concept_name cn
    ON z.obs_value_coded = cn.concept_id
    INNER JOIN mamba_dim_concept c
    ON c.concept_id = cn.concept_id
SET z.obs_value_text       = cn.name,
    z.obs_value_coded_uuid = c.uuid
WHERE z.obs_value_coded IS NOT NULL;

-- Add and update column obs_value_boolean (Concept values)
ALTER TABLE mamba_z_encounter_obs
ADD obs_value_boolean boolean;

UPDATE   mamba_z_encounter_obs z
INNER JOIN mamba_dim_concept_name cn
    ON z.obs_value_coded = cn.concept_id
INNER JOIN mamba_dim_concept c
    ON c.concept_id = cn.concept_id
INNER JOIN mamba_dim_concept_datatype cd
    ON c.datatype_id = cd.concept_datatype_id
SET obs_value_boolean =
    CASE
        WHEN obs_value_coded in (SELECT DISTINCT concept_id FROM mamba_dim_concept c where c.uuid in ('cf82933b-3f3f-45e7-a5ab-5d31aaee3da3','1065AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')) THEN TRUE
        WHEN obs_value_coded in (SELECT DISTINCT concept_id FROM mamba_dim_concept c where c.uuid in ('488b58ff-64f5-4f8a-8979-fa79940b1594','1066AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')) THEN FALSE
    END
WHERE z.obs_value_coded IS NOT NULL;


-- $END
