-- $BEGIN
CREATE TABLE dim_client
(
    id            INT                             NOT NULL AUTO_INCREMENT,
    client_id     INT,
    date_of_birth DATE                            NULL,
    age           INT,
    sex           CHAR(255) CHARACTER SET UTF8MB4 NULL,
    county        CHAR(255) CHARACTER SET UTF8MB4 NULL,
    sub_county    CHAR(255) CHARACTER SET UTF8MB4 NULL,
    ward          CHAR(255) CHARACTER SET UTF8MB4 NULL,
    PRIMARY KEY (id)
);
-- $END
