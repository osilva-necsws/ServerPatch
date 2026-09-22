SET DEFINE OFF;

CREATE OR REPLACE PACKAGE impulse.CV_INSTALLER_PKG AS

	  FUNCTION get_package_version RETURN number;

	  /* CV_INSTALLER_JAVA wrappers */
	  FUNCTION CV_INS_JAVA_VERSION RETURN NUMBER
		AS LANGUAGE JAVA NAME 'CV_INSTALLER_JAVA.GetVersion() return int';
	  FUNCTION CV_INS_JAVA_CREATE_DB_DIR (dirPath IN varchar2) RETURN VARCHAR2
		AS LANGUAGE JAVA NAME 'CV_INSTALLER_JAVA.CheckFileExists_Create(java.lang.String) return java.lang.String';

	  /* DECLARE FUNCTION & PROCEDURES */
	  PROCEDURE COPY_BLOB_TO_DIR(pDirName VARCHAR2, pFileName VARCHAR2, pFileAsBlob BLOB);
	  PROCEDURE READ_BLOB_FROM_DIR(pDirName VARCHAR2, pFileName VARCHAR2, pOutBlob OUT BLOB);
	  PROCEDURE REMOVE_FILE_FROM_DIR(pDirName VARCHAR2, pFileName VARCHAR2);

	  FUNCTION CREATE_DB_DIR_LOCATION(pDirPath IN VARCHAR2) RETURN VARCHAR2;
			  	
END CV_INSTALLER_PKG;
/
SHOW ERRORS

CREATE OR REPLACE PACKAGE BODY impulse.CV_INSTALLER_PKG AS

	  /**************************************************************************************
		Name -  MERGE_PKG

		Description
		-----------
		Something about the package

		Ver    Release/CMR        Date          Author      Description
		----------------------------------------------------------------------------------------
		1    CHILDVIEW INSTALLER  28/11/2013    MicB		This will hold any database function/procedures related to the new ChildView Installer
														- it allows deploy/read to/from Database directories
		2    CHILDVIEW INSTALLER  09/12/2014    MicB		- updated deploy to Database directories process
																				- it call underlying functions to create database directories
		3    CHILDVIEW INSTALLER  07/03/2016    MicB		- updated REGENERATE_ALL_INPUT_FORMS to create an APEX session first prior to call the REGENERATE_ALL_FORMS function. Now also writes the output to DEBUG_LOGS table
	  **************************************************************************************/

	  /*
		***************************************************************
		*********** UPDATE THE VERSION HERE ***************************
		***************************************************************
	  */
	  FUNCTION get_package_version RETURN NUMBER IS
	  BEGIN
		RETURN 3;
	  END get_package_version;

		  /* BODIES FOR FUNCTION & PROCEDURES */
	PROCEDURE COPY_BLOB_TO_DIR(pDirName VARCHAR2, pFileName VARCHAR2, pFileAsBlob BLOB) IS
	  l_file      UTL_FILE.FILE_TYPE;
	  l_buffer    RAW(32767);
	  l_amount    BINARY_INTEGER := 32767;
	  l_pos       NUMBER := 1;
	  l_blob_len  NUMBER;
	BEGIN
	  l_blob_len := DBMS_LOB.getlength(pFileAsBlob);

	  -- Open the destination file.
	  l_file := UTL_FILE.fopen(pDirName, pFileName, 'wb');

	  -- Read chunks of the BLOB and write them to the file until complete.
	  WHILE l_pos < l_blob_len LOOP
		DBMS_LOB.read(pFileAsBlob, l_amount, l_pos, l_buffer);
		UTL_FILE.put_raw(l_file, l_buffer, TRUE);
		l_pos := l_pos + l_amount;
	  END LOOP;
		
	  -- Close the file.
	  UTL_FILE.fclose(l_file);
	END;

  PROCEDURE READ_BLOB_FROM_DIR(pDirName VARCHAR2, pFileName VARCHAR2, pOutBlob OUT BLOB) IS
	input_file      utl_file.file_type;
	chunk_size      constant pls_integer := 4096;
	buf             raw                    (4096); -- Must be equal to chunk_size
	read_sofar      pls_integer := 0;              --(avoid PLS-00491: numeric literal required)
	bytes_to_read   pls_integer;
  BEGIN
	input_file := utl_file.fopen(pDirName, pFileName, 'RB');
	DBMS_LOB.CREATETEMPORARY(pOutBlob,true);
	begin
	  loop

		utl_file.get_raw(input_file, buf, chunk_size);
		bytes_to_read := length(buf) / 2;
		dbms_lob.write(pOutBlob, bytes_to_read, read_sofar+1, buf);
		read_sofar := read_sofar + bytes_to_read;

	  -- utl_file raises no_data_found when unable to read
	  end loop;
	exception when no_data_found then null;
	end;

	utl_file.fclose(input_file);
  END;

  PROCEDURE REMOVE_FILE_FROM_DIR(pDirName VARCHAR2, pFileName VARCHAR2) IS
  BEGIN
	   UTL_FILE.FREMOVE (location => pDirName
						,filename => pFileName);
  END;

  FUNCTION CREATE_DB_DIR_LOCATION(pDirPath IN VARCHAR2) RETURN VARCHAR2 IS
	vDelimiter  CHAR := '/';      
	vOutput		VARCHAR2(4000);
  BEGIN
	--check path contains forward or backward slash
	IF (instr(pDirPath, '/') < 0) THEN
	  IF (instr(pDirPath, '\\') > 0) THEN
		vDelimiter := '\\';
	  END IF;
	END IF;
	SYS.SET_JAVA_FILE_IO_PERMISSIONS(pSchema => 'IMPULSE', pDirPath => pDirPath, pDelimiter => vDelimiter);

	--call java function to create the directory, return the feedback from the procedure
	vOutput := CV_INSTALLER_PKG.CV_INS_JAVA_CREATE_DB_DIR(dirPath => pDirPath);
	RETURN vOutput;
  END;

END CV_INSTALLER_PKG;
/
SHOW ERRORS