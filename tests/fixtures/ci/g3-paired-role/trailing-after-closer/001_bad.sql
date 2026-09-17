-- fixture: a statement AFTER the closer
set role pfin_owner;
create table pfin.fixture_bad (id bigint primary key);
reset role;
create table pfin.fixture_after (id bigint primary key);
