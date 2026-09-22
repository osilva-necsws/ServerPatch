set heading off
set feedback off
SELECT json_object(name is value) from
(select name, nvl(value,'unset') value
  FROM v$parameter
  WHERE name='db_recovery_file_dest'
-- union all
-- select 'Estimated_DB_size_MB' name, est_size value 
--	from (select to_char(sum(bytes)/1024/1024) est_size from dba_free_space)  
 );
exit