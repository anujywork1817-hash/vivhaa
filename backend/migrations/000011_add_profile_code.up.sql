CREATE SEQUENCE profile_code_seq START 100001;

ALTER TABLE profiles
    ADD COLUMN profile_code VARCHAR(12) UNIQUE NOT NULL
    DEFAULT ('VV' || nextval('profile_code_seq')::text);
