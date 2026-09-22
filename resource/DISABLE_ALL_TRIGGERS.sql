SET ECHO ON;
/**************************************************************************************
   Target Release         : 3.1
   CMR                    : 
   Description
   -----------
	Disable all triggers within CACI schemas

   Revision of Last Change: $Rev: 10790 $
   Last Changed By        : $Author: mbugeja $
   Last Changed On        : $Date: 2016-09-26 16:06:10 +0100 (Mon, 26 Sep 2016) $	
**************************************************************************************/
SET ECHO OFF;

SET SERVEROUTPUT ON;
/*
DECLARE
  vExists NUMBER;
  vSQL VARCHAR2(4000);
BEGIN

  SELECT COUNT(*)
    INTO vExists
  FROM   ALL_TABLES t
  WHERE  t.OWNER = 'CVAUTO'
    AND  t.TABLE_NAME = 'TMP_TRIGGERS_DIS';

  --check if table exists or create new one
  IF vExists < 1 THEN
	vSQL := 'create table CVAUTO.TMP_TRIGGERS_DIS AS
			  select t.owner, t.trigger_name, t.status, t.table_name, t.table_owner
			  from   all_triggers t
			  where  t.table_owner IN (''ASSET_PLUS'',''CVAPI'',''CVARCHIVE'',''CVFORMS'',''CVMVIEWS'',''CVXML'',''FSD'',''IMPULSE'',''PPORT'',''WIZARDS'',''YOIS_DATALOAD'')';
  ELSE
	vSQL := 'INSERT INTO CVAUTO.TMP_TRIGGERS_DIS(owner,trigger_name,status,table_name,table_owner)
				  select t.owner, t.trigger_name, t.status, t.table_name, t.table_owner
				  from   all_triggers t
				  where  t.table_owner IN (''ASSET_PLUS'',''CVAPI'',''CVARCHIVE'',''CVFORMS'',''CVMVIEWS'',''CVXML'',''FSD'',''IMPULSE'',''PPORT'',''WIZARDS'',''YOIS_DATALOAD'')
				    and  NOT EXISTS (SELECT 1 
									FROM 	CVAUTO.TMP_TRIGGERS_DIS x
									WHERE	x.owner = t.owner
									  AND	x.trigger_name = t.trigger_name)';
  END IF;
  
  --now run the generated SQL
  DBMS_OUTPUT.PUT_LINE(vSQL);
  EXECUTE IMMEDIATE vSQL;  
 */ 

 --disable all the triggers
DECLARE
	vSQL1 VARCHAR2(1000);  
BEGIN
  FOR d IN (SELECT 	t.owner, t.trigger_name, t.status 
			FROM 	ALL_TRIGGERS t 
			WHERE  	t.table_owner IN ('ASSET_PLUS','CVAPI','CVARCHIVE','CVFORMS','CVMVIEWS','CVXML','FSD','IMPULSE','PPORT','WIZARDS','YOIS_DATALOAD')) LOOP
	vSQL1 := 'ALTER TRIGGER ' || d.owner || '."' || d.trigger_name || '" DISABLE';
	dbms_output.put_line(vSQL1);
	BEGIN
	  EXECUTE IMMEDIATE vSQL1;
	EXCEPTION WHEN OTHERS THEN
	  dbms_output.put_line('ERROR: Could not DISABLE trigger: ' || d.owner || '."' || d.trigger_name || '" - ' || SQLERRM);
	END;
  END LOOP;
END;
/