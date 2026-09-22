-- SQL file to set the database compatability to 19.0.0.0
alter system set compatible ="19.0.0.0" scope=spfile;

shutdown immediate;

startup;
