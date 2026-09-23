-- =============================================================================
-- Foundation security tests (pgTAP).
-- Everything runs inside one transaction and is ROLLED BACK at the end,
-- so no test data is left in the database.
-- Run:  npx supabase test db --linked
-- =============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(51);

-- -----------------------------------------------------------------------------
-- Helpers: pretend to be a logged-in user (the same way Supabase does it)
-- -----------------------------------------------------------------------------
create schema tests;
create function tests.act_as(uid uuid) returns void language plpgsql as $$
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
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner.a@test.local',      '{"full_name":"Owner A"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'admin.a@test.local',      '{"full_name":"Admin A"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'manager.a@test.local',    '{"full_name":"Manager A"}'),
  ('00000000-0000-0000-0000-0000000000a4', 'accountant.a@test.local', '{"full_name":"Accountant A"}'),
  ('00000000-0000-0000-0000-0000000000a5', 'employee.a@test.local',   '{"full_name":"Employee A"}'),
  ('00000000-0000-0000-0000-0000000000a6', 'client.a@test.local',     '{"full_name":"Client A"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'owner.b@test.local',      '{"full_name":"Owner B"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'platform@test.local',     '{"full_name":"Platform Admin"}');

insert into public.organizations (id, name, slug) values
  ('0000000a-0000-0000-0000-000000000000', 'Org A', 'org-a'),
  ('0000000b-0000-0000-0000-000000000000', 'Org B', 'org-b');
insert into public.organization_settings (organization_id) values
  ('0000000a-0000-0000-0000-000000000000'),
  ('0000000b-0000-0000-0000-000000000000');

insert into public.memberships (organization_id, user_id, role, customer_id) values
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1', 'owner', null),
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2', 'admin', null),
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a3', 'manager', null),
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a4', 'accountant', null),
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a5', 'employee', null),
  ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a6', 'client', gen_random_uuid()),
  ('0000000b-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1', 'owner', null);

insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000c1');

insert into public.invitations (organization_id, email, role, token_hash) values
  ('0000000b-0000-0000-0000-000000000000', 'someone@test.local', 'employee', repeat('b', 64));

-- -----------------------------------------------------------------------------
-- 1. Structure
-- -----------------------------------------------------------------------------
select tests.check(is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  0, 'RLS is enabled on every table in public'));

select tests.check(is(
  (select full_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  'Owner A', 'signup creates a profile with the full name'));

select tests.check(is(
  (select email from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  'owner.a@test.local', 'profile email copied from Auth'));

-- -----------------------------------------------------------------------------
-- 2. Tenant isolation: Organization A cannot see Organization B
-- -----------------------------------------------------------------------------
select tests.act_as('00000000-0000-0000-0000-0000000000a1'); -- Owner A

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
select tests.check(is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000000b1'),
  0, 'owner A cannot read the profile of Org B''s owner'));

update public.organizations set name = 'Hacked' where id = '0000000b-0000-0000-0000-000000000000';
select tests.check(throws_ok(
  $$ insert into public.invitations (organization_id, email, role, token_hash)
     values ('0000000b-0000-0000-0000-000000000000', 'x@test.local', 'admin', repeat('c', 64)) $$,
  '42501', null, 'owner A cannot create an invitation in Org B'));

select tests.act_as_system();
select tests.check(is((select name from public.organizations where id = '0000000b-0000-0000-0000-000000000000'),
  'Org B', 'owner A''s attempt to rename Org B changed nothing'));

select tests.act_as('00000000-0000-0000-0000-0000000000b1'); -- Owner B
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
select tests.act_as('00000000-0000-0000-0000-0000000000a2'); -- Admin A
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = '00000000-0000-0000-0000-0000000000a2' $$,
  '42501', null, 'a member cannot change their own role through the API'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1', 'admin') $$,
  '42501', null, 'nobody can add memberships directly through the API'));
select tests.act_as_system();

-- Even with direct database access, the trigger blocks self-changes and owner changes.
do $$ begin perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2"}', true); end $$;
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = '00000000-0000-0000-0000-0000000000a2' $$,
  'CANNOT_CHANGE_OWN_MEMBERSHIP', 'trigger blocks changing your own role'));
do $$ begin perform set_config('request.jwt.claims', '', true); end $$;

select tests.check(throws_ok(
  $$ update public.memberships set role = 'admin' where user_id = '00000000-0000-0000-0000-0000000000a1' $$,
  'OWNER_PROTECTED', 'the OWNER row cannot be demoted outside transfer_ownership'));
select tests.check(throws_ok(
  $$ update public.memberships set role = 'owner' where user_id = '00000000-0000-0000-0000-0000000000a3' $$,
  'OWNER_PROTECTED', 'nobody can be promoted to OWNER outside transfer_ownership'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000a-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000b1', 'owner') $$,
  '23505', null, 'an organization can have only one OWNER'));
select tests.check(throws_ok(
  $$ update public.memberships set organization_id = '0000000b-0000-0000-0000-000000000000'
     where user_id = '00000000-0000-0000-0000-0000000000a5' $$,
  'ORGANIZATION_ID_IMMUTABLE', 'a record cannot be moved to another organization'));
select tests.check(throws_ok(
  $$ insert into public.memberships (organization_id, user_id, role)
     values ('0000000b-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a6', 'client') $$,
  '23514', null, 'a CLIENT membership must be linked to a customer'));
select tests.check(throws_ok(
  $$ delete from auth.users where id = '00000000-0000-0000-0000-0000000000a1' $$,
  'OWNER_PROTECTED', 'the owner''s account cannot be deleted while they own an organization'));

-- Who sees which memberships
select tests.act_as('00000000-0000-0000-0000-0000000000a3'); -- Manager A
select tests.check(is((select count(*)::int from public.memberships), 6, 'manager sees the whole team of Org A'));
select tests.check(is((select count(*)::int from public.profiles), 6, 'manager sees profiles of Org A members only'));
select tests.act_as('00000000-0000-0000-0000-0000000000a5'); -- Employee A
select tests.check(is((select count(*)::int from public.memberships), 1, 'employee sees only their own membership'));
select tests.check(is((select count(*)::int from public.profiles), 1, 'employee sees only their own profile (for now)'));
select tests.act_as('00000000-0000-0000-0000-0000000000a6'); -- Client A
select tests.check(is((select count(*)::int from public.memberships), 1, 'client sees only their own membership'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 5. Profiles
-- -----------------------------------------------------------------------------
select tests.act_as('00000000-0000-0000-0000-0000000000a5'); -- Employee A
update public.profiles set full_name = 'Employee A Renamed' where id = '00000000-0000-0000-0000-0000000000a5';
select tests.check(is((select full_name from public.profiles where id = '00000000-0000-0000-0000-0000000000a5'),
  'Employee A Renamed', 'a user can edit their own name'));
select tests.check(throws_ok(
  $$ update public.profiles set status = 'active' where id = '00000000-0000-0000-0000-0000000000a5' $$,
  '42501', null, 'a user cannot change their own account status'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 6. Invitations
-- -----------------------------------------------------------------------------
select tests.act_as('00000000-0000-0000-0000-0000000000a1'); -- Owner A
select tests.check(lives_ok(
  $$ insert into public.invitations (organization_id, email, role, token_hash)
     values ('0000000a-0000-0000-0000-000000000000', '  New.Person@Test.local ', 'employee', repeat('a', 64)) $$,
  'owner A can invite someone to Org A'));
select tests.check(is((select email from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  'new.person@test.local', 'invitation email is stored in lowercase'));
select tests.check(is((select invited_by from public.invitations where organization_id = '0000000a-0000-0000-0000-000000000000'),
  '00000000-0000-0000-0000-0000000000a1'::uuid, 'invited_by is set to the logged-in user'));
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
  '00000000-0000-0000-0000-0000000000a1'::uuid, 'cancelling records who cancelled'));
select tests.check(throws_ok(
  $$ update public.invitations set status = 'pending' where organization_id = '0000000a-0000-0000-0000-000000000000' $$,
  'INVITATION_NOT_PENDING', 'a cancelled invitation cannot be re-opened'));

select tests.act_as('00000000-0000-0000-0000-0000000000a3'); -- Manager A
select tests.check(is((select count(*)::int from public.invitations), 0, 'manager cannot see invitations'));
select tests.act_as_system();

-- -----------------------------------------------------------------------------
-- 7. Activity log
-- -----------------------------------------------------------------------------
select tests.act_as('00000000-0000-0000-0000-0000000000a1'); -- Owner A
select tests.check(ok((select count(*) from public.activity_logs) > 0, 'owner A can read Org A''s activity log'));
select tests.check(throws_ok('update public.activity_logs set action = ''x''', '42501', null, 'nobody can edit the activity log'));
select tests.check(throws_ok('delete from public.activity_logs', '42501', null, 'nobody can delete from the activity log'));
select tests.act_as('00000000-0000-0000-0000-0000000000a5'); -- Employee A
select tests.check(is((select count(*)::int from public.activity_logs), 0, 'employee cannot read the activity log'));
select tests.act_as_system();

select tests.check(is(
  (select count(*)::int from public.activity_logs where table_name = 'invitations' and changes ? 'token_hash'),
  0, 'the token hash is never written to the activity log'));

-- -----------------------------------------------------------------------------
-- 8. Platform admin, disabled members, suspended organizations
-- -----------------------------------------------------------------------------
select tests.act_as('00000000-0000-0000-0000-0000000000c1'); -- Platform admin
select tests.check(is((select count(*)::int from public.organizations), 2, 'platform admin sees all organizations'));
select tests.check(is((select count(*)::int from public.activity_logs where organization_id is not null),
  0, 'platform admin cannot read organizations'' business logs (D-01)'));
select tests.act_as_system();

update public.memberships set status = 'disabled' where user_id = '00000000-0000-0000-0000-0000000000a3';
select tests.act_as('00000000-0000-0000-0000-0000000000a3'); -- disabled Manager A
select tests.check(is((select count(*)::int from public.organizations), 0, 'a disabled member loses access immediately'));
select tests.act_as_system();

update public.organizations set status = 'suspended' where id = '0000000a-0000-0000-0000-000000000000';
select tests.act_as('00000000-0000-0000-0000-0000000000a1'); -- Owner A of a suspended org
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
