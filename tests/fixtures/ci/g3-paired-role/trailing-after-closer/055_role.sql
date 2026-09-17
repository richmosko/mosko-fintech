-- fixture: a conformant SUPERVISED-lane file — carries NEITHER half, by design
create role fixture_worker with nologin noinherit;
comment on role fixture_worker is 'fixture';
