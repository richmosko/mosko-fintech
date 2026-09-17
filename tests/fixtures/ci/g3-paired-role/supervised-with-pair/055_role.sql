-- fixture: a SUPERVISED-lane file that wrongly carries the pair
set role pfin_owner;
create role fixture_worker with nologin noinherit;
reset role;
