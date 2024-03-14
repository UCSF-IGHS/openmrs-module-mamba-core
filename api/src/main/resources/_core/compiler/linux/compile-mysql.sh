#!/bin/bash

# Usage info
function show_help() {
cat << EOF

Usage: ${0##*/} [-h] [-d DATABASE] [-v VW_MAKEFILE] [-s SP_MAKEFILE]...
Reads file paths in the MAKE FILEs and for each file, uses the content to create a stored procedure or a view. Stored procedures are
put in the create_stored_procedures.sql file and views in a create_views.sql file.

    -h                      display this help and exit
    -t CONFIG_DIR           JSON configuration file
    -n DB_ENGINE            Database Vendor/Engine. One of: mysql|postgres|sqlserver|oracle
    -d SOURCE_DATABASE      the Source Database (openmrs database).
    -a ANALYSIS_DATABASE    the Target/Analysis Database (where the ETL data is stored).
    -v VW_MAKEFILE          file with a list of all files with views
    -s SP_MAKEFILE          file with a list of all files with stored procedures
    -k SCHEMA               schema in which the views and or stored procedures will be put
    -o OUTPUT_FILE          the file where the compiled output will be put
    -b BUILD_FLAG           (1 or 0) - If set to 1, engine will recompile scripts, if 0 - do nothing
    -c all                  clear all schema objects before run
    -c sp                   clear all stored procedures before run
    -c views                clear all views before run

EOF
}

echo "ARG 1  : $1"
echo "ARG 2  : $2"
echo "ARG 3  : $3"
echo "ARG 4  : $4"
echo "ARG 5  : $5"
echo "ARG 6  : $6"
echo "ARG 7  : $7"
echo "ARG 8  : $8"
echo "ARG 9  : $9"
echo "ARG 10 : ${10}"
echo "ARG 11 : ${11}"
echo "ARG 12 : ${12}"

# Variable will contain the stored procedures for the Service layer Reports
# these are auto-generated by the engine from the reports.json file
create_report_procedure=""

# Read in the JSON configuration metadata for Table flattening
function read_config_metadata() {

  JSON_CONTENTS="{\"flat_report_metadata\":["

  FIRST_FILE=true
  for FILENAME in "$config_dir"/*.json; do
    if [ "$FILENAME" = "$config_dir/reports.json" ]; then
        continue
    elif [ "$FIRST_FILE" = false ]; then
        JSON_CONTENTS="$JSON_CONTENTS,"
#     else
#        JSON_CONTENTS=""
    fi
    JSON_CONTENTS="$JSON_CONTENTS$(cat "$FILENAME")"
    FIRST_FILE=false
  done

  JSON_CONTENTS="$JSON_CONTENTS]}"

  # Count the number of JSON files excluding 'reports.json'
  count=$(find "$config_dir" -type f -name '*.json' ! -name 'reports.json' | wc -l)

  SQL_CONTENTS="

      -- \$BEGIN
          "$'
              SET @report_data = '%s';
              SET @file_count = %d;

              CALL sp_extract_configured_flat_table_file_into_dim_json_table(@report_data); -- insert manually added report JSON from config dir
              CALL sp_mamba_dim_json_insert(); -- insert automatically generated report JSON from db

              -- SET @report_data = fn_mamba_generate_report_array_from_automated_json_table();
              SET session group_concat_max_len = 200000;
              SET @report_data = (
                  SELECT CONCAT(
                      '\''{"flat_report_metadata":['\'',
                      GROUP_CONCAT(
                          CONCAT(
                              '\''{"report_name":'\'', json_data->'\''$.report_name'\'',
                              '\'',"flat_table_name":'\'', json_data->'\''$.flat_table_name'\'',
                              '\'',"concepts_locale":'\'', json_data->'\''$.concepts_locale'\'',
                              '\'',"encounter_type_uuid":'\'', json_data->'\''$.encounter_type_uuid'\'',
                              '\'',"table_columns": '\'', json_data->'\''$.table_columns'\'',
                              '\''}'\''
                          )
                          SEPARATOR '\'','\''
                      ),
                      '\'']}'\''
                  )
                  FROM mamba_dim_json
              );


              CALL sp_mamba_extract_report_metadata(@report_data, '\''mamba_dim_concept_metadata'\'');
          '"
      -- \$END
  "

  # Replace above placeholders in SQL_CONTENTS with actual values
  SQL_CONTENTS=$(printf "$SQL_CONTENTS" "'$JSON_CONTENTS'" "$count")

  echo "$SQL_CONTENTS" > "../../database/$db_engine/config/sp_mamba_dim_concept_metadata_insert.sql" #TODO: improve!!

}

# Read in the JSON for Report Definition configuration metadata
function read_config_report_definition_metadata() {

    FILENAME="$config_dir/reports.json";
    REPORT_DEFINITION_FILE="../../database/$db_engine/config/sp_mamba_dim_report_definition_insert.sql"

    # Check if reports.json file exists
    if [ -s "$FILENAME" ] && [ -f "$FILENAME" ]; then
       json_string=$(cat "$FILENAME")

    else
      echo "reports.json file not found, is null or is not a regular file. Will not read report_definition."
      json_string='{"report_definitions": []}'

      echo "-- \$BEGIN" > "$REPORT_DEFINITION_FILE"
      echo "-- \$END" >> "$REPORT_DEFINITION_FILE"
      return
    fi

    # Get the total number of report_definitions
    total_reports=$(jq '.report_definitions | length' <<< "$json_string")

    # Iterate through each report_definition
    for ((i = 0; i < total_reports; i++)); do

        reportId=$(jq -r ".report_definitions[$i].report_id" <<< "$json_string")

        report_procedure_name="sp_mamba_${reportId}_query"
        report_columns_procedure_name="sp_mamba_${reportId}_columns_query"
        report_columns_table_name="mamba_dim_$reportId"

        sql_query=$(jq -r ".report_definitions[$i].report_sql.sql_query" <<< "$json_string")
        # echo "SQL Query: $sql_query"

        # Iterate through query_params and save values before printing
        query_params=$(jq -c ".report_definitions[$i].report_sql.query_params[] | select(length > 0) | {name, type}" <<< "$json_string")
        in_parameters=""
        while IFS= read -r entry; do
            queryName=$(jq -r '.name' <<< "$entry")
            queryType=$(jq -r '.type' <<< "$entry")

            # Check if queryName and queryType are not null or empty before concatenating
            if [[ -n "$queryName" && -n "$queryType" ]]; then
                in_parameters+="IN $queryName $queryType, "
            fi
        done <<< "$query_params"

        # Remove trailing comma
        in_parameters="${in_parameters%, }"

        # Print concatenated pairs if there are any
        if [ -n "$in_parameters" ]; then
            echo "Query Params: $in_parameters"
        fi

create_report_procedure+="

-- ---------------------------------------------------------------------------------------------
-- ----------------------  $report_procedure_name  ----------------------------
-- ---------------------------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS $report_procedure_name;

DELIMITER //

CREATE PROCEDURE $report_procedure_name($in_parameters)
BEGIN

$sql_query;

END //

DELIMITER ;

"

create_report_procedure+="

-- ---------------------------------------------------------------------------------------------
-- ----------------------  $report_columns_procedure_name  ----------------------------
-- ---------------------------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS $report_columns_procedure_name;

DELIMITER //

CREATE PROCEDURE $report_columns_procedure_name($in_parameters)
BEGIN

-- Create Table to store report column names with no rows
DROP TABLE IF EXISTS $report_columns_table_name;
CREATE TABLE $report_columns_table_name AS
$sql_query
LIMIT 0;

-- Select report column names from Table
SELECT GROUP_CONCAT(COLUMN_NAME SEPARATOR ', ')
INTO @column_names
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$report_columns_table_name';

-- Update Table with report column names
UPDATE mamba_dim_report_definition
SET result_column_names = @column_names
WHERE report_id='$reportId';

END //

DELIMITER ;

"
    done

    # Now Read in the contents for the Mysql Part - to insert into Tables
    if [ ! -z "$FILENAME" ] && [ -f "$FILENAME" ]; then

        JSON_CONTENTS=$(cat "$FILENAME" | sed "s/'/''/g") # Read in the contents for the JSON file and escape single quotes

        REPORT_DEFINITION_CONTENT=$(cat <<EOF
-- \$BEGIN
SET @report_definition_json = '$JSON_CONTENTS';
CALL sp_mamba_extract_report_definition_metadata(@report_definition_json, 'mamba_dim_report_definition');
-- \$END
EOF
)
    fi

    echo "$REPORT_DEFINITION_CONTENT" > "$REPORT_DEFINITION_FILE" #TODO: improve!!
}

function make_buildfile_liquibase_compatible(){

  > "$cleaned_file"

  end_pattern="^[[:space:]]*(end|END)[[:space:]]*[/|//][[:space:]]*"
  delimiter_pattern="^[[:space:]]*(delimiter|DELIMITER)[[:space:]]*[;|//][[:space:]]*"

  while IFS= read -r line; do

    if [[ "$line" =~ $end_pattern ]]; then
      echo "END~" >> "$cleaned_file"
#      echo "~" >> "$cleaned_file"
      continue
    fi

    if [[ "$line" =~ $delimiter_pattern ]]; then
      continue
    fi

    # Add the character '/' on a new line before the statement 'CREATE PROCEDURE...'
    if [[ $line == "CREATE PROCEDURE"* ]]; then
      echo "~" >> "$cleaned_file"
    fi

     # Add the character '/' on a new line before the statement 'CREATE FUNCTION...'
    if [[ $line == "CREATE FUNCTION"* ]]; then
      echo "~" >> "$cleaned_file"
    fi

    # Write the modified line to the output file
    echo "$line" >> "$cleaned_file"

  done < "$file_to_clean"

  #after executing use analysis_db at strt of execution, we were getting a weir error in openmrs on unlocking liquibase changelock where it was looking for the Table inside analysis_db yet it is in the Openmrs transactional db
  #so let's manually change back to use the openmrs database at the end
  use_source_db="USE $source_database;"
  echo "$use_source_db" >> "$cleaned_file"

}

function consolidateSPsCallerFile() {

  # Save the current directory
  local currentDir=$(pwd)

  # Get the base dir for the db engine we are working with
  local dbEngineBaseDir=$(readlink -f "../../database/$db_engine")

  # Search for core's p_data_processing.sql file in all subdirectories in the path: ${project.build.directory}/mamba-etl/_core/database/$db_engine
  #  local consolidatedFile=$(find "../../database/$db_engine" -name sp_mamba_data_processing_flatten.sql -type f -print -quit)
  local consolidatedFile=$(find "$dbEngineBaseDir" -name sp_makefile -type f -print -quit)

  # Search for all files with the specified filename in the path: ${project.build.directory}/mamba-etl/_etl
  # Then get its directory name/path, so we can find a file named sp_mamba_data_processing_flatten.sql which is in the same dir
  local sp_make_folders=$(find "../../../_etl" -name sp_makefile -type f -exec dirname {} \; | sort -u)

  local newLine="\n"
  local formatHash="#############################################################################"

  printf "\n" >> "$consolidatedFile"
  printf "\n" >> "$consolidatedFile"
  echo $formatHash >> "$consolidatedFile"
  printf "############################### ETL Scripts #################################" >> "$consolidatedFile"
  printf "\n" >> "$consolidatedFile"
  echo $formatHash >> "$consolidatedFile"

  # Loop through each folder, cd to that folder
  local temp_folder_number=1
  for folder in $sp_make_folders; do

    cd "$folder"

    printf "\n" >> "$consolidatedFile"

    # Read the sp_makefile line by line skipping comments (#) and write the file and its dir structure to a new loc.
    cat sp_makefile | grep -v "^#" | grep -v "^$" | while read -r line; do

      # echo "copying file: $line"
      # echo "to temp location: $dbEngineBaseDir"/etl/$temp_folder_number

      # Extract the file name and folder name from the line
      # filename=$(basename "$line")
      # foldername=$(dirname "$line")

      # Output the file name and folder name to the console
      #echo "File name: $filename"
      #echo "Folder name: $foldername"

      #Copy the file with its full path and folder structure to the temp folder
      rsync --relative "$line" "$dbEngineBaseDir"/etl/$temp_folder_number/

      # copy the new file path to the consolidated file
      echo "etl/$temp_folder_number/$line" >>"$consolidatedFile"

    done

    temp_folder_number=$((temp_folder_number + 1))
    cd "$currentDir"
  done

}

function create_directory_if_absent(){
    DIR="$1"

    if [ ! -d "$DIR" ]; then
        mkdir "$DIR"
    fi
}

function exit_if_file_absent(){
    FILE="$1"
    if [ ! -f "$FILE" ]; then
        echo "We couldn't find this file. Please correct and try again"
        echo "$FILE"
        exit 1
    fi
}

BUILD_DIR=""
sp_out_file="create_stored_procedures.sql"
vw_out_file="create_views.sql"
makefile=""
source_database=""
analysis_database=""
config_dir=""
cleaned_file=""
file_to_clean=""
db_engine=""
views=""
stored_procedures=""
schema=""
objects=""
OPTIND=1
IFS='
'

while getopts ":h:t:n:d:a:v:s:k:o:c:" opt; do
    case "${opt}" in
        h)
            show_help
            exit 0
            ;;
        t)  config_dir="$OPTARG"
            ;;
        n)  db_engine="$OPTARG"
            ;;
        d)  source_database="$OPTARG"
            ;;
        a)  analysis_database="$OPTARG"
            ;;
        v)  views="$OPTARG"
            ;;
        s)  stored_procedures="$OPTARG"
            ;;
        k)  schema="$OPTARG"
            ;;
        o)  out_file="$OPTARG"
            ;;
        c)  objects="$OPTARG"
            ;;
        *)
            show_help >&2
            exit 1
            ;;
    esac
done
shift "$((OPTIND-1))"

if [ ! -n "$stored_procedures" ] && [ ! -n "$views" ]
then
    show_help >&2
    exit 1
fi

if [ -n "$views" ] && [ -n "$stored_procedures" ] && [ -n "$out_file" ]
then
    echo "Warning: You can not compile both views and stored procedures if you provide an output file."
    exit 1
fi

if [ -n "$out_file" ]
then
    sp_out_file=$out_file
    vw_out_file=$out_file
fi

schema_name="$schema"
if [ ! -n "$schema" ]
then
    schema_name="dbo"
else
    schema_name="$schema"
fi

objects_to_clear="$objects"
if [ ! -n "$objects" ]
then
    objects_to_clear=""
else
    objects_to_clear="$objects"
fi

clear_message="No objects to clean out."
clear_objects_sql=""
if [ "$objects_to_clear" == "all" ]; then
    clear_message="clearing all objects in $schema_name"
    clear_objects_sql="CALL dbo.sp_xf_system_drop_all_objects_in_schema '$schema_name' "
elif [ "$objects_to_clear" == "sp" ]; then
    clear_message="clearing all stored procedures in $schema_name"
    clear_objects_sql="CALL dbo.sp_xf_system_drop_all_stored_procedures_in_schema '$schema_name' "
elif [ "$objects_to_clear" == "views" ] || [ "$objects_to_clear" == "view" ] || [ "$objects_to_clear" == "v" ]; then
    clear_message="clearing all views in $schema_name"
    clear_objects_sql="CALL dbo.sp_xf_system_drop_all_views_in_schema '$schema_name' "
fi

# Read in the JSON for Report Definition configuration metadata
read_config_report_definition_metadata

# Read in the JSON configuration metadata for Table flattening
read_config_metadata

# Consolidate all the make files into one file
consolidateSPsCallerFile

if [ -n "$stored_procedures" ]
then

    makefile=$stored_procedures
    exit_if_file_absent "$makefile"

    WORKING_DIR=$(dirname "$makefile")
    BUILD_DIR="$WORKING_DIR/build"
    create_directory_if_absent "$BUILD_DIR"

    # all_stored_procedures="USE $analysis_database;
    all_stored_procedures="
        $clear_objects_sql
    "

    if [ ! -n "$source_database" ]
    then
        all_stored_procedures=""
    fi

    if [ ! -n "$analysis_database" ]
    then
        all_stored_procedures=""
    fi

    # if any of the files doesn't exist, do not process
    for file_path in $(sed -E '/^[[:blank:]]*(#|$)/d; s/#.*//' $makefile)
    do
        if [ ! -f "$WORKING_DIR/$file_path" ]
        then
            echo "Warning: Could not process stored procedures. File '$file_path' does not exist."
            exit 1
        fi
    done

    sp_name=""

    for file_path in $(sed -E '/^[[:blank:]]*(#|$)/d; s/#.*//' $makefile)
    do
        # create a stored procedure
        file_name=$(basename "$file_path" ".sql")
        sp_name="$file_name"
        sp_body=$(awk '/-- \$BEGIN/,/-- \$END/' $WORKING_DIR/$file_path)

        prefix='-- $BEGIN'
        suffix='-- $END'

        #sp_body=${sp_body#"$prefix"}
        #sp_body=${sp_body%"$suffix"}

        if [ -z "$sp_body" ]
        then
              sp_body=`cat $WORKING_DIR/$file_path`
              sp_create_statement="
-- ---------------------------------------------------------------------------------------------
-- ----------------------  $sp_name  ----------------------------
-- ---------------------------------------------------------------------------------------------

$sp_body

"
        else
            sp_create_statement="
-- ---------------------------------------------------------------------------------------------
-- ----------------------  $sp_name  ----------------------------
-- ---------------------------------------------------------------------------------------------

DROP PROCEDURE IF EXISTS $sp_name;

DELIMITER //

CREATE PROCEDURE $sp_name()
BEGIN
$sp_body
END //

DELIMITER ;
"
        fi

        all_stored_procedures="$all_stored_procedures
        $sp_create_statement"
    done

    ### SG - replace any place holders in the script e.g.$target_database
    ### all_stored_procedures="${all_stored_procedures//'$target_database'/'$analysis_database'}" commented out since we are not using it now
    ### all_stored_procedures="${all_stored_procedures//\$target_database/'$analysis_database'}" even this works!!

    ### Add the reporting SPs created above if any
    all_stored_procedures+="$create_report_procedure"
    ### write built contents (final SQL file contents) to the build output file
    echo "$all_stored_procedures" > "$BUILD_DIR/$sp_out_file"

    ### SG - Clean up build file to make it Liquibase compatible ###
    file_to_clean="$BUILD_DIR/$sp_out_file"

    ## Automate the Create Analysis Database command at the beginning of the script
    create_target_db="CREATE database IF NOT EXISTS $analysis_database;"$'\n~\n' #TODO: This also adds to the create_stored_procedures.sql file -> This needs to be corrected to only add to the liquibase cleaned file

    ## Add the target database to use at the beginning of the script
    use_target_db="USE $analysis_database;"$'\n~\n' #TODO: This also adds to the create_stored_procedures.sql file -> This needs to be corrected to only add to the liquibase cleaned file

    # Create a temporary file with the text to prepend
    temp_file=$(mktemp)

    # Add create command text to the temporary file
    echo "$create_target_db" > "$temp_file"

    # Append use command text to the temporary file
    echo "$use_target_db" >> "$temp_file"

    # Append the original file's content to the temporary file
    cat "$file_to_clean" >> "$temp_file"

    # Overwrite the original file with the contents of the temporary file
    mv "$temp_file" "$file_to_clean"

    # Remove the temporary file
    rm "$temp_file"


    ## Replace source database placeholder name

    temp_file=$(mktemp)

    # Use awk to perform the replacement
    awk -v search="mamba_source_db" -v replace="$source_database" '{ gsub(search, replace) }1' "$file_to_clean" > "$temp_file"

    # Overwrite the original file with the contents of the temporary file
    mv "$temp_file" "$file_to_clean"

    # Remove the temporary file
    rm "$temp_file"


    cleaned_file="$BUILD_DIR/liquibase_$sp_out_file"
    make_buildfile_liquibase_compatible
fi

if [ -n "$views" ]
then

    makefile=$views
    exit_if_file_absent "$makefile"

    WORKING_DIR=$(dirname "$makefile")
    BUILD_DIR="$WORKING_DIR/build"
    create_directory_if_absent "$BUILD_DIR"

    # views_body="USE $analysis_database;
    views_body="

$clear_objects_sql

"
    if [ ! -n "$source_database" ]
    then
        views_body=""
    fi

    if [ ! -n "$analysis_database" ]
    then
        views_body=""
    fi

    # if any of the files doesnt exist, do not process
    for file_path in $(sed -E '/^[[:blank:]]*(#|$)/d; s/#.*//' $makefile)
    do
        if [ ! -f "$WORKING_DIR/$file_path" ]
        then
            echo "Warning: Could not process. File '$file_path' does not exist."
            exit 1
        fi
    done

    for file_path in $(sed -E '/^[[:blank:]]*(#|$)/d; s/#.*//' $makefile)
    do
        # create view
        file_name=$(basename "$file_path" ".sql")
        vw_name="$file_name"
        vw_body=$(awk '/-- \$BEGIN/,/-- \$END/' $WORKING_DIR/$file_path)

        vw_header="

-- ---------------------------------------------------------------------------------------------
-- $vw_name
--

CREATE OR ALTER VIEW $vw_name AS
"

views_body="$views_body
$vw_header
$vw_body

"

    done

    echo "$views_body" > "$BUILD_DIR/$vw_out_file"

fi
