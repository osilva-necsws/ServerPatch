-- Seed script for New PostgreSQL installations
-- Creates databases for Datamart and Metabase pairs (Prod/Test)
-- Run as Postgres user

-- Create DATABASES

create database cv_test_datamart encoding=UTF8;
create database cv_prod_datamart encoding=UTF8;

create database cv_test_metabase encoding=UTF8;
create database cv_prod_metabase encoding=UTF8;

-- ===========================================
-- Datamart Database Setup
-- ===========================================

-- Switch to cv_test_datamart

\c cv_test_datamart;

-- Create Schema cvmviews

create schema cvmviews;

-- Create admin group

create group cvdm_admin;

grant all on database cv_test_datamart to cvdm_admin;
grant all on schema cvmviews to cvdm_admin;

-- Add default user to admin group

create role cvdm_sqlwb with login password 'changeme!' inherit;
grant cvdm_admin to cvdm_sqlwb;

-- Create query group

create group cvdm_user;

grant connect on database cv_test_datamart to cvdm_user;
grant usage on schema cvmviews to cvdm_user;
grant select on all tables in schema cvmviews to cvdm_user;

create role cvdm_query with login password 'changeme!' inherit;
grant cvdm_user to cvdm_query;

\c cv_prod_datamart;

-- Create Schema cvmviews

create schema cvmviews;

-- Create admin group

--create group cvdm_admin;

grant all on database cv_prod_datamart to cvdm_admin;
grant all on schema cvmviews to cvdm_admin;

-- Add default user to admin group

--create role cvdm_sqlwb with login password 'changeme!' inherit;
--grant cvdm_admin to cvdm_sqlwb;

-- Create query group

--create group cvdm_user;

grant connect on database cv_prod_datamart to cvdm_user;
grant usage on schema cvmviews to cvdm_user;
grant select on all tables in schema cvmviews to cvdm_user;

--create role cvdm_query with login password 'changeme!' inherit;
grant cvdm_user to cvdm_query;

-- ===========================================
-- Metabase Database Setup
-- ===========================================

\c cv_prod_metabase;

-- Create Schema metabase

create schema metabase;

create group metabase_admin;

grant all on database cv_prod_metabase to metabase_admin;
grant all on schema metabase to metabase_admin;

create role metabase with login password 'changeme!' inherit;
grant metabase_admin to metabase;

\c cv_test_metabase;

-- Create Schema metabase

create schema metabase;

--create group metabase_admin;

grant all on database cv_prod_metabase to metabase_admin;
grant all on schema metabase to metabase_admin;

--create role metabase with login password 'changeme!' inherit;
--grant metabase_admin to metabase;
