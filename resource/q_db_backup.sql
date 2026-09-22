set heading off
set feedback off
select json_object(tag, status) from v$backup_piece where tag='#bcktag' group by tag,status;
exit