-- Distinguishes video calls from audio-only calls. Existing rows default
-- to TRUE since every call_sessions row so far was created by the
-- video-only calling feature — there's no way to retroactively know
-- otherwise, and TRUE matches what actually happened.
ALTER TABLE call_sessions ADD COLUMN is_video BOOLEAN NOT NULL DEFAULT TRUE;
