-- fixture: transaction-scoped variant instead of the session-scoped pair
set local role pfin_owner;
create table pfin.fixture_bad (id bigint primary key);
reset role;
