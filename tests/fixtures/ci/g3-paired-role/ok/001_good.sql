-- fixture: a conformant pfin-lane migration
set role pfin_owner;
create table pfin.fixture_ok (id bigint primary key);
reset role;
