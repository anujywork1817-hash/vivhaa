-- Fields the Flutter onboarding flow collects that the original profiles
-- table (migration 000003) had no home for. Added as one batch rather
-- than piecemeal since they're all "extra profile detail" in the same
-- vein as what's already there.
ALTER TABLE profiles
    ADD COLUMN profile_for          VARCHAR(20),   -- myself, son, daughter, brother, sister, relative, friend
    ADD COLUMN sub_community        VARCHAR(100),
    ADD COLUMN caste_no_bar         BOOLEAN,
    ADD COLUMN college              VARCHAR(150),
    ADD COLUMN work_with            VARCHAR(50),   -- private_company, government, defense, business, not_working
    ADD COLUMN company_name         VARCHAR(150),
    ADD COLUMN matchmaking_opt_out  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN family_values        VARCHAR(20),   -- traditional, moderate, liberal
    ADD COLUMN lives_with_family    BOOLEAN,
    ADD COLUMN hobbies              TEXT[],
    ADD COLUMN selfie_verified      BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN manglik              VARCHAR(20),   -- yes, no, dont_know
    ADD COLUMN rashi                VARCHAR(30),
    ADD COLUMN nakshatra            VARCHAR(30),
    ADD COLUMN birth_time           VARCHAR(10),   -- free-form "HH:MM", not always known precisely
    ADD COLUMN birth_place          VARCHAR(150),
    ADD COLUMN weight_kg            SMALLINT,
    ADD COLUMN body_type            VARCHAR(20),   -- slim, athletic, average, heavy
    ADD COLUMN complexion           VARCHAR(30),
    ADD COLUMN has_disability       BOOLEAN;
