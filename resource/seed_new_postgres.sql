--
-- PostgreSQL database cluster dump
--

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Drop databases (except postgres and template1)
--

DROP DATABASE IF EXISTS cv_prod_datamart;
DROP DATABASE IF EXISTS cv_prod_metabase;
DROP DATABASE IF EXISTS cv_test_datamart;
DROP DATABASE IF EXISTS cv_test_metabase;




--
-- Drop roles
--

DROP ROLE IF EXISTS cvdm_admin;
DROP ROLE IF EXISTS cvdm_query;
DROP ROLE IF EXISTS cvdm_sqlwb;
DROP ROLE IF EXISTS cvdm_user;
DROP ROLE IF EXISTS metabase;
DROP ROLE IF EXISTS metabase_admin;
DROP ROLE IF EXISTS postgres;


--
-- Roles
--

CREATE ROLE cvdm_admin;
ALTER ROLE cvdm_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
CREATE ROLE cvdm_query;
ALTER ROLE cvdm_query WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:L2rTtM0ruMgb4ny8kiMdpA==$JB2G10maDh9bmNce67Og8HFcBO0NfrmJ6wX+sRNt7Tk=:QaSArlsqJtGAodhFeVRb4RI7zJkRTh8R+mC6RZ1KsiQ=';
CREATE ROLE cvdm_sqlwb;
ALTER ROLE cvdm_sqlwb WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:Fpf4WJlkZuDR+JjbKnVjNA==$NBrqKaFLvgkDWMOahk4YAWcGSVjP9N8ow4TZfYxyXEE=:iG56GZcl2k8eWGjt9Qqeh3tMUbS5FRi4afAh7ufxpwY=';
CREATE ROLE cvdm_user;
ALTER ROLE cvdm_user WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
CREATE ROLE metabase;
ALTER ROLE metabase WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:YsQwhxyePvIFQenzoyqaMA==$CSTVEt5Or9976f3mm7TX5PKRiHTxSTIfGGwVrdirqzw=:MZ9ZpN1vpKoMjouU9L4WxErfq4zVLGbwyXX1+egpWd8=';
CREATE ROLE metabase_admin;
ALTER ROLE metabase_admin WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;


--
-- Role memberships
--

GRANT cvdm_admin TO cvdm_sqlwb GRANTED BY postgres;
GRANT cvdm_user TO cvdm_query GRANTED BY postgres;
GRANT metabase_admin TO metabase GRANTED BY postgres;




--
-- Databases
--

--
-- Database "template1" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

UPDATE pg_catalog.pg_database SET datistemplate = false WHERE datname = 'template1';
DROP DATABASE template1;
--
-- Name: template1; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE template1 WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE template1 OWNER TO postgres;

\connect template1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: DATABASE template1; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE template1 IS 'default template for new databases';


--
-- Name: template1; Type: DATABASE PROPERTIES; Schema: -; Owner: postgres
--

ALTER DATABASE template1 IS_TEMPLATE = true;


\connect template1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: DATABASE template1; Type: ACL; Schema: -; Owner: postgres
--

REVOKE CONNECT,TEMPORARY ON DATABASE template1 FROM PUBLIC;
GRANT CONNECT ON DATABASE template1 TO PUBLIC;


--
-- PostgreSQL database dump complete
--

--
-- Database "cv_prod_datamart" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cv_prod_datamart; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE cv_prod_datamart WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE cv_prod_datamart OWNER TO postgres;

\connect cv_prod_datamart

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cvmviews; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cvmviews;


ALTER SCHEMA cvmviews OWNER TO postgres;

--
-- Name: DATABASE cv_prod_datamart; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON DATABASE cv_prod_datamart TO cvdm_admin;
GRANT CONNECT ON DATABASE cv_prod_datamart TO cvdm_user;


--
-- Name: SCHEMA cvmviews; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA cvmviews TO cvdm_admin;
GRANT USAGE ON SCHEMA cvmviews TO cvdm_user;


--
-- PostgreSQL database dump complete
--

--
-- Database "cv_prod_metabase" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cv_prod_metabase; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE cv_prod_metabase WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE cv_prod_metabase OWNER TO postgres;

\connect cv_prod_metabase

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: metabase; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA metabase;


ALTER SCHEMA metabase OWNER TO postgres;

--
-- Name: DATABASE cv_prod_metabase; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON DATABASE cv_prod_metabase TO metabase_admin;


--
-- Name: SCHEMA metabase; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA metabase TO metabase_admin;


--
-- PostgreSQL database dump complete
--

--
-- Database "cv_test_datamart" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cv_test_datamart; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE cv_test_datamart WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE cv_test_datamart OWNER TO postgres;

\connect cv_test_datamart

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cvmviews; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cvmviews;


ALTER SCHEMA cvmviews OWNER TO postgres;

--
-- Name: DATABASE cv_test_datamart; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON DATABASE cv_test_datamart TO cvdm_admin;


--
-- Name: SCHEMA cvmviews; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA cvmviews TO cvdm_admin;
GRANT USAGE ON SCHEMA cvmviews TO cvdm_user;


--
-- PostgreSQL database dump complete
--

--
-- Database "cv_test_metabase" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cv_test_metabase; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE cv_test_metabase WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE cv_test_metabase OWNER TO postgres;

\connect cv_test_metabase

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: metabase; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA metabase;


ALTER SCHEMA metabase OWNER TO postgres;

--
-- Name: SCHEMA metabase; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA metabase TO metabase_admin;


--
-- PostgreSQL database dump complete
--

--
-- Database "postgres" dump
--

--
-- PostgreSQL database dump
--

-- Dumped from database version 14.2
-- Dumped by pg_dump version 14.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE postgres;
--
-- Name: postgres; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE postgres WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'English_United Kingdom.1252';


ALTER DATABASE postgres OWNER TO postgres;

\connect postgres

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: DATABASE postgres; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON DATABASE postgres IS 'default administrative connection database';


--
-- PostgreSQL database dump complete
--

--
-- PostgreSQL database cluster dump complete
--

