set heading off
set feedback off
select json_object('est_size' is est_size) from  
(select to_char(sum(bytes)/1024/1024) est_size from dba_free_space);
exit