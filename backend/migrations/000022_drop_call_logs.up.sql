-- Video/voice calling feature removed. Drops the call_logs table created
-- in 000017_create_call_logs.up.sql. NOT auto-applied — this table holds
-- historical call data; run manually only after confirming that data
-- doesn't need to be retained/exported.
DROP TABLE IF EXISTS call_logs;
