set serveroutput on
set sqlformat ansiconsole
set linesize 200
set time on

WHENEVER SQLERROR EXIT SQL.SQLCODE

WHENEVER OSERROR EXIT

drop user APEX_040200 cascade;

drop user APEX_040000 cascade;


EXIT;
