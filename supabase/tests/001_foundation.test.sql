-- =============================================================================
-- Foundation security tests (pgTAP).
-- Everything runs inside one transaction and is ROLLED BACK at the end,
-- so no test data is left in the database.
-- Run:  npx supabase test db --linked   (needs Docker)
--  or:  paste this whole file into the Supabase SQL Editor and click Run
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(51);

-- -----------------------------------------------------------------------------
-- Helpers: pretend to be a logged-in user (the same way Supabase does it)
-- -----------------------------------------------------------------------------
create schema tests;
create function tests.act_as(uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function tests.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
end;
$$;
create function tests.act_as_system() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;
-- Every check is also recorded here, so the Supabase SQL Editor can show a
-- summary table at the end (the SQL Editor only displays the last result).
create table tests.results (id serial primary key, line text not null);
create function tests.check(tap text) returns text
language plpgsql security definer set search_path = '' as $$
begin
  insert into tests.results (line) values (tap);
  return tap;
end;
$$;
grant usage on schema tests to anon, authenticated;
grant execute on all functions in schema tests to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Test data: two organizations (A and B) and one person per role
-- -----------------------------------------------------------------------------
-- Profiles are normally created by our server from Clerk; here they are inserted directly.
insert into public.profiles (id, email, full_name) values
  ('user_test_owner_a',      'owner.a@test.local',      'Owner A'),
  ('user_test_admin_a',      'admin.a@test.local',      'Admin A'),
  ('user_test_manager_a',    'manager.a@test.local',    'Manager A'),
  ('user_test_accountant_a', 'accountant.a@test.local', 'Accountant A'),
  ('user_test_employee_a',   'employee.a@test.local',   'Employee A'),
  ('user_test_client_a',     'client.a@test.local',     'Client A'),
  ('user_test_owner_b',      'owner.b@test.local',      'Owner B'),
  ('user_test_platform',     'platform@test.local',     'Platform Admin');

insert into public.organizations (id, name, slug) values
  ('0000000a-0000-0000-0000-000000000000', 'Org A', 'org-a'),
  ('0000000b-0000-0000-0000-000000000000', 'Org B', 'org-b');
insert into public.organization_settings (organization_id) values
  ('0000000a-0000-0000-0000-000000000000'),
  ('0000000b-0000-0000-0000-000000000000');

insert into public.memberships (organization_id, user_id, role, customer_id) values
  ('0000000a-0000-0000-0000-000000000000', 'user_test_owner_a', 'owner', null),
  ('0000000a-0000-0000-0000-000000000000', 'user_test_admin_a', 'admin', null),
  ('0000000a-0000-0000-0000-000000000000', 'user_test_manager_a', 'manager', null),
  ('0000000a-0000-0000-0000-000000000000', 'user_test_accountant_a', 'accountant', null),
  ('0000000a-0000-0000-0000-000000000000', 'user_test_employee_a', 'employee', null),
  ('0000000a-0000-0000-0000-000000000000', 'user_test_client_a', 'client', gen_random_uuid()),
  ('0000000b-0000-0000-0000-000000000000', 'user_test_owner_b', 'owner', null);

insert into public.platform_admins (user_id) values ('user_test_platform');

insert into public.invitations (organization_id, email, role, token_hash) values
  ('0000000b-0000-0000-0000-000000000000', 'someone@test.local', 'employee', repeat('b', 64));

-- -----------------------------------------------------------------------------
-- 1. Structure
-- -----------------------------------------------------------------------------
select tests.check(is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every table in public'));

select tests.act_as('user_test_owner_a');
select tests.check(throws_ok(
  $$ insert into public.profiles (id, email) values ('user_fake', 'fake@test.local') $$,
  '42501', null, 'nobody can create a profile through the API (only the server, from Clerk)'));
select tests.check(throws_ok(
  $$ update public.profiles set email = 'other@test.local' where id = 'user_test_owner_a' $$,
  '42501', null, 'a user cannot change their own email (managed in Clerk)'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 2. Tenant isolation: Organization A cannot see Organization B
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_owner_a'); -- Owner A

select tests.check(is((select count(*)::int from public.organizations), 1, 'owner A sees exactly one organization'));
select tests.check(is((select name from public.organizations limit 1), 'Org A', '... and it is Org A'));
select tests.check(is((select count(*)::int from public.organizations where id = '0000000b-0000-0000-0000-000000000000'),
  0, 'owner A cannot read Org B'));
select tests.check(is((select count(*)::int from public.organization_settings where organization_id = '0000000b-0000-0000-0000-000000000000'),
  0, 'owner A cannot read Org B settings'));
select tests.check(is((select count(*)::int from public.memberships where organization_id = '0000000b-0000-0000-0000-000000000000'),
  0, 'owner A cannot read Org B memberships'));
select tests.check(is((select count(*)::int from public.invitations where organization_id = '0000000b-0000-0000-0000-000000000000'),
  0, 'owner A cannot read Org B invitations'));
select tests.check(is((select count(*)::int from public.activity_logs where organization_id = '0000000b-0000-0000-0000-000000000000'),
  0, 'owner A cannot read Org B activity log'));
select tests.check(is((select count(*)::int from public.profiles where id = 'user_test_owner_b'),
  0, 'owner A cannot read the profile of Org B''s owner'));

update public.organizations set name = 'Hacked' where id = '0000000b-0000-0000-0000-000000000000';
select tests.check(throws_ok(
  $$ insert into public.invitations (organization_id, email, role, token_hash)
     values ('0000000b-0000-0000-0000-000000000000', 'x@test.local', 'admin', repeat('c', 64)) $$,
  '42501', null, 'owner A cannot create an invitation in Org B'));

select tests.act_as_system();
select tests.check(is((select name from public.organizations where id = '0000000b-0000-0000-0000-000000000000'),
  'Org B', 'owner A''s attempt to rename Org B changed nothing'));

select tests.act_as('user_test_owner_b'); -- Owner B
select tests.check(is((select count(*)::int from public.organizations where id = '0000000a-0000-0000-0000-000000000000'),
  0, 'owner B cannot read Org A'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 3. Not logged in (anon) gets nothing
-- -----------------------------------------------------------------------------
select tests.act_as_anon();
select tests.check(throws_ok('select * from public.organizations', '42501', null, 'anon cannot read organizations'));
select tests.check(throws_ok('select * from public.memberships',   '42501', null, 'anon cannot read memberships'));
select tests.check(throws_ok('select * from public.profiles',      '42501', null, 'anon cannot read profiles'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 4. Roles and memberships
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_admin_a'); -- Admin A
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = 'user_test_admin_a' $$,
  '42501', null, 'a member cannot change their own role through the API'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000a-0000-0000-0000-000000000000', 'user_test_owner_b', 'admin') $$,
  '42501', null, 'nobody can add memberships directly through the API'));
select tests.act_as_system();

-- Even with direct database access, the trigger blocks self-changes and owner changes.
do $$ begin perform set_config('request.jwt.claims', '{"sub":"user_test_admin_a"}', true); end $$;
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = 'user_test_admin_a' $$,
  'CANNOT_CHANGE_OWN_MEMBERSHIP', 'trigger blocks changing your own role'));
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

select tests.check(throws_ok(
  $$ update public.memberships set role = 'admin' where user_id = 'user_test_owner_a' $$,
  'OWNER_PROTECTED', 'the OWNER row cannot be demoted outside transfer_ownership'));
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = 'user_test_manager_a' $$,
  'OWNER_PROTECTED', 'nobody can be promoted to OWNER outside transfer_ownership'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000a-0000-0000-0000-000000000000', 'user_test_owner_b', 'owner') $$,
  '23505', null, 'an organization can have only one OWNER'));
select tests.check(throws_ok(
  $$ update public.memberships set organization_id = '0000000b-0000-0000-0000-000000000000'
     where user_id = 'user_test_employee_a' $$,
  'ORGANIZATION_ID_IMMUTABLE', 'a record cannot be moved to another organization'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000b-0000-0000-0000-000000000000', 'user_test_client_a', 'client') $$,
  '23514', null, 'a CLIENT membership must be linked to a customer'));
select tests.check(throws_ok(
  $$ delete from public.profiles where id = 'user_test_owner_a' $$,
  'OWNER_PROTECTED', 'the owner''s account cannot be deleted while they own an organization'));

-- Who sees which memberships
select tests.act_as('user_test_manager_a'); -- Manager A
select tests.check(is((select count(*)::int from public.memberships), 6, 'manager sees the whole team of Org A'));
select tests.check(is((select count(*)::int from public.profiles), 6, 'manager sees profiles of Org A members only'));
select tests.act_as('user_test_employee_a'); -- Employee A
select tests.check(is((select count(*)::int from public.memberships), 1, 'employee sees only their own membership'));
select tests.check(is((select count(*)::int from public.profiles), 1, 'employee sees only their own profile (for now)'));
select tests.act_as('user_test_client_a'); -- Client A
select tests.check(is((select count(*)::int from public.memberships), 1, 'client sees only their own membership'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 5. Profiles
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_employee_a'); -- Employee A
update public.profiles set phone = '0300-1234567' where id = 'user_test_employee_a';
select tests.check(is((select phone from public.profiles where id = 'user_test_employee_a'),
  '0300-1234567', 'a user can edit their own phone number'));
select tests.check(throws_ok(
  $$ update public.profiles set status = 'active' where id = 'user_test_employee_a' $$,
  '42501', null, 'a user cannot change their own account status'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 6. Invitations
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_owner_a'); -- Owner A
select tests.check(lives_ok(
  $$ insert into public.invitations (organization_id, email, role, token_hash)
     values ('0000000a-0000-0000-0000-000000000000', '  New.Person@Test.local ', 'employee', repeat('a', 64)) $$,
  'owner A can invite someone to Org A'));
select tests.check(is((select email from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  'new.person@test.local', 'invitation email is stored in lowercase'));
select tests.check(is((select invited_by from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  'user_test_owner_a', 'invited_by is set to the logged-in user'));
select tests.check(ok((select expires_at between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
           from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  'invitation expires in 7 days'));
select tests.check(throws_ok('select token_hash from public.invitations', '42501', null,
  'nobody can read the invitation token hash'));
select tests.check(throws_ok(
  $$ insert into public.invitations (organization_id, email, role, token_hash)
     values ('0000000a-0000-0000-0000-000000000000', 'boss@test.local', 'owner', repeat('d', 64)) $$,
  '23514', null, 'nobody can be invited as OWNER'));
update public.invitations set status = 'cancelled' where organization_id = '0000000a-0000-0000-0000-000000000000';
select tests.check(is((select cancelled_by from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  'user_test_owner_a', 'cancelling records who cancelled'));
select tests.check(throws_ok(
  $$ update public.invitations set status = 'pending' where organization_id = '0000000a-0000-0000-0000-000000000000' $$,
  'INVITATION_NOT_PENDING', 'a cancelled invitation cannot be re-opened'));

select tests.act_as('user_test_manager_a'); -- Manager A
select tests.check(is((select count(*)::int from public.invitations), 0, 'manager cannot see invitations'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 7. Activity log
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_owner_a'); -- Owner A
select tests.check(ok((select count(*) from public.activity_logs) > 0, 'owner A can read Org A''s activity log'));
select tests.check(throws_ok('update public.activity_logs set action = ''x''', '42501', null, 'nobody can edit the activity log'));
select tests.check(throws_ok('delete from public.activity_logs', '42501', null, 'nobody can delete from the activity log'));
select tests.act_as('user_test_employee_a'); -- Employee A
select tests.check(is((select count(*)::int from public.activity_logs), 0, 'employee cannot read the activity log'));
select tests.act_as_system();

select tests.check(is(
  (select count(*)::int from public.activity_logs where table_name = 'invitations' and changes ? 'token_hash'),
  0, 'the token hash is never written to the activity log'));

-- -----------------------------------------------------------------------------
-- 8. Platform admin, disabled members, suspended organizations
-- -----------------------------------------------------------------------------
select tests.act_as('user_test_platform'); -- Platform admin
select tests.check(is((select count(*)::int from public.organizations), 2, 'platform admin sees all organizations'));
select tests.check(is((select count(*)::int from public.activity_logs where organization_id is not null),
  0, 'platform admin cannot read organizations'' business logs (D-01)'));
select tests.act_as_system();

update public.memberships set status = 'disabled' where user_id = 'user_test_manager_a';
select tests.act_as('user_test_manager_a'); -- disabled Manager A
select tests.check(is((select count(*)::int from public.organizations), 0, 'a disabled member loses access immediately'));
select tests.act_as_system();

update public.organizations set status = 'suspended' where id = '0000000a-0000-0000-0000-000000000000';
select tests.act_as('user_test_owner_a'); -- Owner A of a suspended org
select tests.check(is((select count(*)::int from public.organization_settings), 0, 'a suspended organization''s data is closed, even for the OWNER'));
select tests.act_as_system();

select * from finish();

-- Summary for the Supabase SQL Editor (lines do not start with "ok", so pg_prove ignores them).
select result, check_name from (
  select r.id as sort_order,
         case when r.line like 'ok %' then 'PASS' else 'FAIL' end as result,
         regexp_replace(split_part(r.line, E'\n', 1), '^(not )?ok [0-9]+ - ', '') as check_name
  from tests.results r
  union all
  select 0, 'TOTAL', format('%s of %s checks passed',
                            (select count(*) from tests.results where line like 'ok %'),
                            (select count(*) from tests.results))
) summary
order by sort_order;

rollback;
