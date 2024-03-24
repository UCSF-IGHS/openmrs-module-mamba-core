DROP FUNCTION IF EXISTS fn_mamba_get_datatype_for_concept;

DELIMITER //

CREATE FUNCTION fn_mamba_get_datatype_for_concept(conceptDatatype VARCHAR(20)) RETURNS VARCHAR(20)
    DETERMINISTIC
BEGIN
    DECLARE mysqlDatatype VARCHAR(20);


    IF conceptDatatype = 'Coded'
       OR conceptDatatype = 'N/A'
       OR conceptDatatype = 'Text' THEN
        SET mysqlDatatype = 'TEXT';

    ELSEIF conceptDatatype = 'Boolean' THEN
        SET mysqlDatatype = 'Boolean';

    ELSEIF conceptDatatype = 'Date' THEN
        SET mysqlDatatype = 'DATE';

    ELSEIF conceptDatatype = 'Datetime' THEN
        SET mysqlDatatype = 'DATETIME';

    ELSEIF conceptDatatype = 'Numeric' THEN
        SET mysqlDatatype = 'DOUBLE';

    END IF;

    RETURN mysqlDatatype;
END //

DELIMITER ;