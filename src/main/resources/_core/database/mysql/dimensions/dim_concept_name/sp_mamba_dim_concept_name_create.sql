-- $BEGIN

CREATE TABLE mamba_dim_concept_name (
    concept_name_id int NOT NULL AUTO_INCREMENT,
    external_concept_id int,
    concept_name VARCHAR(255) NULL,
    PRIMARY KEY (concept_name_id)
);

-- $END
