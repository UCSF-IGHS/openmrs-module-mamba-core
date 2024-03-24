DROP FUNCTION IF EXISTS fn_mamba_get_obs_value_column;

DELIMITER //

CREATE FUNCTION fn_mamba_get_obs_value_column(conceptDatatype VARCHAR(20)) RETURNS VARCHAR(20)
    DETERMINISTIC
BEGIN
    DECLARE obsValueColumn VARCHAR(20);

        IF conceptDatatype = 'Text'
           OR  conceptDatatype = 'Coded'
           OR conceptDatatype = 'N/A' THEN
            SET obsValueColumn = 'obs_value_text';

        ELSEIF conceptDatatype = 'Boolean' THEN
            SET obsValueColumn = 'obs_value_boolean';

        ELSEIF  conceptDatatype = 'Date'
                OR conceptDatatype = 'Datetime' THEN
            SET obsValueColumn = 'obs_value_datetime';

        ELSEIF conceptDatatype = 'Numeric' THEN
            SET obsValueColumn = 'obs_value_numeric';
        END IF;

    RETURN (obsValueColumn);
END //

DELIMITER ;