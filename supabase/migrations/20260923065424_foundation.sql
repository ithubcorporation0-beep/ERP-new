-- =============================================================================
-- Step 8 — Database foundation
-- Plan: docs/prp/04-database.md, 06-authorization-rls.md, 11-notifications-audit.md
--
-- Creates:  organizations, organization_settings, profiles, memberships,
--           invitations, platform_admins, activity_logs
-- Plus:     private helper functions used by security rules (RLS),
--           shared triggers (updated_at, created_by, audit log, protections),
--           RLS policies, column-level grants and indexes for every table.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 0. Private schema (NOT exposed by the Supabase API)
-- -----------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

-- 1.1 profiles — one row per user account. Logins are handled by Clerk (D-62), so the
--     id is the Clerk user id (text like "user_2abc…"). Rows are created/updated by our
--     server right after sign-in, with details it reads from Clerk (never from the browser).
--     No role column on purpose: roles live only in memberships / platform_admins.
create table public.profiles (
  id                   text primary key check (char_length(id) between 1 and 64),
  email                text not null default '',
  full_name            text not null default '' check (char_length(full_name) <= 100),
  phone                text check (char_length(phone) <= 30),
  avatar_path          text check (char_length(avatar_path) <= 500),
  status               text not null default 'active' check (status in ('active', 'disabled')),
  disabled_reason      text check (char_length(disabled_reason) <= 500),
  last_organization_id uuid,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);
create unique index profiles_email_key on public.profiles (lower(email)) where email <> '';

-- 1.2 organizations — one business (tenant).
create table public.organizations (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null check (char_length(btrim(name)) between 2 and 100),
  slug                  text not null
                          check (char_length(slug) between 3 and 40
                                 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
                                 and slug not in ('app', 'platform', 'api', 'admin', 'login', 'logout',
                                                  'signup', 'register', 'onboarding', 'settings', 'auth',
                                                  'invite', 'health', 'pricing', 'billing', 'support',
                                                  'help', 'www', 'mail', 'select-organization',
                                                  'account-disabled', 'organization-suspended')),
  status                text not null default 'active'
                          check (status in ('active', 'suspended', 'pending_deletion')),
  suspended_reason      text check (char_length(suspended_reason) <= 500),
  currency              char(3) not null default 'PKR' check (currency ~ '^[A-Z]{3}$'),
  timezone              text not null default 'Asia/Karachi' check (char_length(timezone) between 1 and 64),
  logo_path             text check (char_length(logo_path) <= 500),
  deletion_requested_at timestamptz,
  created_by            text references public.profiles (id) on delete set null,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create unique index organizations_slug_key on public.organizations (lower(slug));
create index organizations_status_idx on public.organizations (status);
create index organizations_created_by_idx on public.organizations (created_by);

alter table public.profiles
  add constraint profiles_last_organization_id_fkey
  foreign key (last_organization_id) references public.organizations (id) on delete set null;
create index profiles_last_organization_id_idx on public.profiles (last_organization_id);

-- 1.3 organization_settings — settings OWNER/ADMIN edit (1 row per organization).
create table public.organization_settings (
  organization_id         uuid primary key references public.organizations (id) on delete cascade,
  legal_name              text check (char_length(legal_name) <= 200),
  address                 text check (char_length(address) <= 500),
  city                    text check (char_length(city) <= 100),
  country                 text check (char_length(country) <= 100),
  phone                   text check (char_length(phone) <= 30),
  email                   text check (char_length(email) <= 254),
  website                 text check (char_length(website) <= 200),
  tax_registration_number text check (char_length(tax_registration_number) <= 50),
  invoice_prefix          text not null default 'INV' check (invoice_prefix ~ '^[A-Z0-9]{1,10}$'),
  invoice_due_days        integer not null default 30 check (invoice_due_days between 0 and 365),
  invoice_notes           text check (char_length(invoice_notes) <= 2000),
  invoice_terms           text check (char_length(invoice_terms) <= 2000),
  tax_label               text not null default 'Tax' check (char_length(tax_label) between 1 and 30),
  default_tax_rate        numeric(5,2) not null default 0 check (default_tax_rate between 0 and 100),
  clients_can_see_tasks   boolean not null default false,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

-- 1.4 memberships — person + organization + role.
create table public.memberships (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id         text not null references public.profiles (id) on delete cascade,
  role            text not null
                    check (role in ('owner', 'admin', 'manager', 'accountant', 'employee', 'client')),
  status          text not null default 'active' check (status in ('active', 'disabled')),
  customer_id     uuid, -- foreign key to customers is added in Step 12
  job_title       text check (char_length(job_title) <= 100),
  invited_by      text references public.profiles (id) on delete set null,
  disabled_at     timestamptz,
  disabled_by     text references public.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint memberships_org_user_key unique (organization_id, user_id),
  constraint memberships_org_id_key unique (organization_id, id),
  constraint memberships_client_customer_check check ((role = 'client') = (customer_id is not null))
);
-- At most one OWNER per organization ("at least one" is protected by a trigger below).
create unique index memberships_one_owner_idx on public.memberships (organization_id) where role = 'owner';
create index memberships_user_id_idx on public.memberships (user_id);
create index memberships_org_role_idx on public.memberships (organization_id, role);
create index memberships_org_customer_idx on public.memberships (organization_id, customer_id)
  where customer_id is not null;
create index memberships_invited_by_idx on public.memberships (invited_by);
create index memberships_disabled_by_idx on public.memberships (disabled_by);

-- 1.5 invitations — invite by email with a role. Only a hash of the token is stored.
create table public.invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email           text not null
                    check (email = lower(btrim(email))
                           and char_length(email) between 3 and 254
                           and email ~ '^[^@\s]+@[^@\s]+$'),
  role            text not null check (role in ('admin', 'manager', 'accountant', 'employee', 'client')),
  customer_id     uuid, -- foreign key to customers is added in Step 12
  token_hash      text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  status          text not null default 'pending'
                    check (status in ('pending', 'accepted', 'cancelled', 'expired')),
  expires_at      timestamptz not null default (now() + interval '7 days'),
  invited_by      text references public.profiles (id) on delete set null,
  accepted_by     text references public.profiles (id) on delete set null,
  accepted_at     timestamptz,
  cancelled_at    timestamptz,
  cancelled_by    text references public.profiles (id) on delete set null,
  last_sent_at    timestamptz not null default now(),
  send_count      integer not null default 1 check (send_count >= 1),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint invitations_org_id_key unique (organization_id, id),
  constraint invitations_client_customer_check check ((role = 'client') = (customer_id is not null))
);
create unique index invitations_one_pending_idx on public.invitations (organization_id, email)
  where status = 'pending';
create index invitations_email_idx on public.invitations (email);
create index invitations_invited_by_idx on public.invitations (invited_by);
create index invitations_accepted_by_idx on public.invitations (accepted_by);
create index invitations_cancelled_by_idx on public.invitations (cancelled_by);

-- 1.6 platform_admins — who runs the whole SaaS. Rows are added ONLY with SQL
--     in the Supabase dashboard (no policy lets the website add one).
create table public.platform_admins (
  user_id    text primary key references public.profiles (id) on delete cascade,
  note       text check (char_length(note) <= 200),
  created_at timestamptz not null default now()
);

-- 1.7 activity_logs — append-only audit trail.
--     actor_user_id has no foreign key on purpose: a log entry must never block a change.
create table public.activity_logs (
  id              bigint generated always as identity primary key,
  organization_id uuid references public.organizations (id) on delete cascade, -- null = platform-level event
  actor_user_id   text,
  action          text not null check (char_length(action) between 1 and 100),
  table_name      text not null,
  record_id       text,
  changes         jsonb,
  ip_address      inet,
  user_agent      text,
  created_at      timestamptz not null default now()
);
create index activity_logs_org_created_idx on public.activity_logs (organization_id, created_at desc);
create index activity_logs_org_record_idx on public.activity_logs (organization_id, table_name, record_id);
create index activity_logs_actor_idx on public.activity_logs (actor_user_id);


-- -----------------------------------------------------------------------------
-- 2. Helper functions for security rules
--    Who is logged in: the "sub" (subject) of the Clerk login token that Supabase has
--    already verified. (Supabase's private.current_user_id() is not used: it expects Supabase-style ids.)
--    security definer = runs with the owner's rights, so it can read memberships
--    without triggering RLS again (avoids "infinite recursion").
--    search_path = '' = every table is written with its schema (no look-alike tricks).
-- -----------------------------------------------------------------------------

create function private.current_user_id()
returns text
language sql stable set search_path = ''
as $$
  select nullif((select auth.jwt()) ->> 'sub', '');
$$;

create function private.is_platform_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins pa
    join public.profiles p on p.id = pa.user_id
    where pa.user_id = (select private.current_user_id())
      and p.status = 'active'
  );
$$;

-- Role of the current user in an organization, only if membership, organization
-- and account are all active. Null otherwise.
create function private.my_role(org uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select m.role
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join public.profiles p      on p.id = m.user_id
  where m.organization_id = org
    and m.user_id = (select private.current_user_id())
    and m.status = 'active'
    and o.status = 'active'
    and p.status = 'active';
$$;

create function private.is_member(org uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.my_role(org) is not null;
$$;

create function private.has_role(org uuid, roles text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(private.my_role(org) = any (roles), false);
$$;

create function private.my_membership_id(org uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select m.id
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join public.profiles p      on p.id = m.user_id
  where m.organization_id = org
    and m.user_id = (select private.current_user_id())
    and m.status = 'active'
    and o.status = 'active'
    and p.status = 'active';
$$;

-- For a CLIENT: the customer their login is linked to. Null for other roles.
create function private.client_customer_id(org uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select m.customer_id
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join public.profiles p      on p.id = m.user_id
  where m.organization_id = org
    and m.user_id = (select private.current_user_id())
    and m.role = 'client'
    and m.status = 'active'
    and o.status = 'active'
    and p.status = 'active';
$$;

-- May the organization be changed? Step 22 replaces this with the subscription
-- check (expired subscription = read-only, D-25). Until then: always yes.
create function private.org_writable(org uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select org is not null;
$$;

-- Used by every insert/update/delete policy: right role AND organization writable.
create function private.can_write(org uuid, roles text[])
returns boolean
language sql stable security definer set search_path = ''
as $$
  select private.has_role(org, roles) and private.org_writable(org);
$$;

-- May the current user see this person's profile (name, email)?
-- Yes if the person is a member of an organization where the current user is
-- OWNER, ADMIN, MANAGER or ACCOUNTANT. (Employees seeing co-members on shared
-- projects is added in Step 13.)
create function private.can_see_profile(target text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships t
    where t.user_id = target
      and private.has_role(t.organization_id, array['owner', 'admin', 'manager', 'accountant'])
  );
$$;

revoke all on function
  private.current_user_id(), private.is_platform_admin(), private.my_role(uuid), private.is_member(uuid),
  private.has_role(uuid, text[]), private.my_membership_id(uuid), private.client_customer_id(uuid),
  private.org_writable(uuid), private.can_write(uuid, text[]), private.can_see_profile(text)
from public, anon;
grant execute on function
  private.current_user_id(), private.is_platform_admin(), private.my_role(uuid), private.is_member(uuid),
  private.has_role(uuid, text[]), private.my_membership_id(uuid), private.client_customer_id(uuid),
  private.org_writable(uuid), private.can_write(uuid, text[]), private.can_see_profile(text)
to authenticated, service_role;


-- -----------------------------------------------------------------------------
-- 3. Shared trigger functions
-- -----------------------------------------------------------------------------

-- 3.1 updated_at = now() on every update.
create function private.set_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- 3.2 Force a "who did it" column (name given as trigger argument) to the
--     logged-in user. Whatever the browser sent is ignored.
create function private.force_actor_column()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if private.current_user_id() is not null then
    new := jsonb_populate_record(new, jsonb_build_object(tg_argv[0], private.current_user_id()));
  end if;
  return new;
end;
$$;

-- 3.3 organization_id can never change after insert.
create function private.prevent_org_change()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id then
    raise exception 'ORGANIZATION_ID_IMMUTABLE' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- 3.4 Organization checks: valid timezone.
create function private.validate_organization()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'INVALID_TIMEZONE' using errcode = 'check_violation';
  end if;
  new.name := btrim(new.name);
  return new;
end;
$$;

-- 3.5 Membership protections (defence in depth — normal users have no write
--     access to memberships at all; changes go through database functions).
--     Database functions that are allowed to do protected changes set
--     app.membership_change_allowed = 'on' for their own transaction only.
create function private.guard_membership_changes()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_allowed boolean := coalesce(current_setting('app.membership_change_allowed', true), '') = 'on';
begin
  if v_allowed then
    return coalesce(new, old);
  end if;

  if tg_op = 'UPDATE' then
    -- Nobody changes their own role or status.
    if private.current_user_id() is not null and old.user_id = private.current_user_id()
       and (new.role is distinct from old.role or new.status is distinct from old.status) then
      raise exception 'CANNOT_CHANGE_OWN_MEMBERSHIP' using errcode = 'insufficient_privilege';
    end if;
    -- The OWNER row can only change through transfer_ownership.
    if old.role = 'owner'
       and (new.role is distinct from old.role or new.status is distinct from old.status) then
      raise exception 'OWNER_PROTECTED' using errcode = 'insufficient_privilege';
    end if;
    -- Nobody becomes OWNER except through transfer_ownership.
    if new.role = 'owner' and old.role <> 'owner' then
      raise exception 'OWNER_PROTECTED' using errcode = 'insufficient_privilege';
    end if;
    if new.user_id is distinct from old.user_id then
      raise exception 'MEMBERSHIP_USER_IMMUTABLE' using errcode = 'check_violation';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    -- The OWNER row cannot be removed while the organization exists
    -- (e.g. deleting the owner's account is refused until ownership is transferred).
    if old.role = 'owner'
       and exists (select 1 from public.organizations o where o.id = old.organization_id) then
      raise exception 'OWNER_PROTECTED' using errcode = 'insufficient_privilege';
    end if;
    return old;
  end if;

  return new;
end;
$$;

-- 3.6 Invitation rules for OWNER/ADMIN edits (cancel, resend).
create function private.guard_invitation_changes()
returns trigger
language plpgsql set search_path = ''
as $$
declare
  v_allowed boolean := coalesce(current_setting('app.invitation_change_allowed', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    new.email        := lower(btrim(new.email));
    new.status       := 'pending';
    new.expires_at   := now() + interval '7 days'; -- D-23
    new.last_sent_at := now();
    new.send_count   := 1;
    new.accepted_by  := null;
    new.accepted_at  := null;
    new.cancelled_at := null;
    new.cancelled_by := null;
    return new;
  end if;

  -- UPDATE
  if v_allowed or private.current_user_id() is null then
    return new;
  end if;

  if old.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING' using errcode = 'check_violation';
  end if;
  if new.status not in ('pending', 'cancelled') then
    raise exception 'INVITATION_STATUS_NOT_ALLOWED' using errcode = 'insufficient_privilege';
  end if;

  if new.status = 'cancelled' then
    new.cancelled_at := now();
    new.cancelled_by := private.current_user_id();
  elsif new.token_hash is distinct from old.token_hash then
    -- Resend: new link, new 7-day expiry.
    new.expires_at   := now() + interval '7 days';
    new.last_sent_at := now();
    new.send_count   := old.send_count + 1;
  end if;
  return new;
end;
$$;

-- 3.7 Audit log: records every insert/update/delete. Only changed fields are
--     stored for updates. Column names passed as trigger arguments are never
--     logged (e.g. token_hash). IP / browser come from headers our server sends.
create function private.audit_row_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  v_excluded text[] := coalesce(tg_argv, '{}'::text[]) || array['updated_at'];
  v_old      jsonb;
  v_new      jsonb;
  v_row      jsonb;
  v_changes  jsonb := '{}'::jsonb;
  v_key      text;
  v_org      uuid;
  v_headers  jsonb;
  v_ip       inet;
  v_ua       text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_old := to_jsonb(old) - v_excluded;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := to_jsonb(new) - v_excluded;
  end if;
  v_row := coalesce(v_new, v_old);

  if tg_op = 'INSERT' then
    v_changes := v_new;
  elsif tg_op = 'DELETE' then
    v_changes := v_old;
  else
    for v_key in select jsonb_object_keys(v_new) loop
      if (v_new -> v_key) is distinct from (v_old -> v_key) then
        v_changes := v_changes
          || jsonb_build_object(v_key, jsonb_build_object('old', v_old -> v_key, 'new', v_new -> v_key));
      end if;
    end loop;
    if v_changes = '{}'::jsonb then
      return null; -- nothing meaningful changed
    end if;
  end if;

  -- Which organization does this row belong to?
  if tg_table_name = 'organizations' then
    v_org := (v_row ->> 'id')::uuid;
  elsif v_row ? 'organization_id' then
    v_org := (v_row ->> 'organization_id')::uuid;
  end if;

  -- When a whole organization is permanently deleted, its rows disappear with it:
  -- log that event once (as a platform event) and skip the rows inside it.
  if v_org is not null
     and not exists (select 1 from public.organizations o where o.id = v_org) then
    if tg_table_name = 'organizations' then
      v_org := null;
    else
      return null;
    end if;
  end if;

  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    v_headers := null;
  end;
  v_ua := left(v_headers ->> 'x-client-user-agent', 500);
  begin
    v_ip := (v_headers ->> 'x-client-ip')::inet;
  exception when others then
    v_ip := null;
  end;

  insert into public.activity_logs
    (organization_id, actor_user_id, action, table_name, record_id, changes, ip_address, user_agent)
  values (
    v_org,
    private.current_user_id(),
    lower(tg_op),
    tg_table_name,
    coalesce(v_row ->> 'id', v_row ->> 'user_id', v_row ->> 'organization_id'),
    v_changes,
    v_ip,
    v_ua
  );
  return null;
end;
$$;

revoke all on function
  private.set_updated_at(), private.force_actor_column(), private.prevent_org_change(),
  private.validate_organization(), private.guard_membership_changes(),
  private.guard_invitation_changes(), private.audit_row_change()
from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 4. Attach triggers
-- -----------------------------------------------------------------------------

-- updated_at
create trigger set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.organizations
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.organization_settings
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.memberships
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.invitations
  for each row execute function private.set_updated_at();

-- forced "who" columns
create trigger force_created_by before insert on public.organizations
  for each row execute function private.force_actor_column('created_by');
create trigger force_invited_by before insert on public.invitations
  for each row execute function private.force_actor_column('invited_by');

-- organization_id never changes
create trigger prevent_org_change before update on public.organization_settings
  for each row execute function private.prevent_org_change();
create trigger prevent_org_change before update on public.memberships
  for each row execute function private.prevent_org_change();
create trigger prevent_org_change before update on public.invitations
  for each row execute function private.prevent_org_change();

-- table-specific rules
create trigger validate_organization before insert or update on public.organizations
  for each row execute function private.validate_organization();
create trigger guard_membership_changes before update or delete on public.memberships
  for each row execute function private.guard_membership_changes();
create trigger guard_invitation_changes before insert or update on public.invitations
  for each row execute function private.guard_invitation_changes();

-- audit log (after the change, one entry per row)
create trigger audit_row_change after insert or update or delete on public.organizations
  for each row execute function private.audit_row_change();
create trigger audit_row_change after insert or update or delete on public.organization_settings
  for each row execute function private.audit_row_change();
create trigger audit_row_change after insert or update or delete on public.profiles
  for each row execute function private.audit_row_change();
create trigger audit_row_change after insert or update or delete on public.memberships
  for each row execute function private.audit_row_change();
create trigger audit_row_change after insert or update or delete on public.invitations
  for each row execute function private.audit_row_change('token_hash');
create trigger audit_row_change after insert or update or delete on public.platform_admins
  for each row execute function private.audit_row_change();


-- -----------------------------------------------------------------------------
-- 5. Row Level Security + grants
--    anon (not logged in) gets nothing. authenticated gets only the columns and
--    actions listed; RLS policies then decide which rows.
-- -----------------------------------------------------------------------------

alter table public.profiles              enable row level security;
alter table public.organizations         enable row level security;
alter table public.organization_settings enable row level security;
alter table public.memberships           enable row level security;
alter table public.invitations           enable row level security;
alter table public.platform_admins       enable row level security;
alter table public.activity_logs         enable row level security;

revoke all on table
  public.profiles, public.organizations, public.organization_settings, public.memberships,
  public.invitations, public.platform_admins, public.activity_logs
from anon, authenticated;

-- 5.1 profiles
grant select on public.profiles to authenticated;
-- Name and email are managed in Clerk and copied here by the server; users may edit only these:
grant update (phone, last_organization_id) on public.profiles to authenticated;

create policy "profiles: read own, visible team members, or as platform admin"
  on public.profiles for select to authenticated
  using (
    id = (select private.current_user_id())
    or private.can_see_profile(id)
    or private.is_platform_admin()
  );

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select private.current_user_id()))
  with check (id = (select private.current_user_id()));

-- 5.2 organizations (created only by a database function in Step 10)
grant select on public.organizations to authenticated;
grant update (name, timezone, logo_path) on public.organizations to authenticated;

create policy "organizations: members and platform admins read"
  on public.organizations for select to authenticated
  using (private.is_member(id) or private.is_platform_admin());

create policy "organizations: owner and admin update"
  on public.organizations for update to authenticated
  using (private.can_write(id, array['owner', 'admin']))
  with check (private.can_write(id, array['owner', 'admin']));

-- 5.3 organization_settings
grant select on public.organization_settings to authenticated;
grant update (legal_name, address, city, country, phone, email, website, tax_registration_number,
              invoice_prefix, invoice_due_days, invoice_notes, invoice_terms, tax_label,
              default_tax_rate, clients_can_see_tasks)
  on public.organization_settings to authenticated;

create policy "organization_settings: members read"
  on public.organization_settings for select to authenticated
  using (private.is_member(organization_id));

create policy "organization_settings: owner and admin update"
  on public.organization_settings for update to authenticated
  using (private.can_write(organization_id, array['owner', 'admin']))
  with check (private.can_write(organization_id, array['owner', 'admin']));

-- 5.4 memberships (all changes only through database functions — Steps 10–11)
grant select on public.memberships to authenticated;

create policy "memberships: read own, team list, platform admin"
  on public.memberships for select to authenticated
  using (
    user_id = (select private.current_user_id())
    or private.has_role(organization_id, array['owner', 'admin', 'manager', 'accountant'])
    or private.is_platform_admin()
  );

-- 5.5 invitations (token_hash can be written but never read back)
grant select (id, organization_id, email, role, customer_id, status, expires_at, invited_by,
              accepted_by, accepted_at, cancelled_at, cancelled_by, last_sent_at, send_count,
              created_at, updated_at)
  on public.invitations to authenticated;
grant insert (organization_id, email, role, customer_id, token_hash) on public.invitations to authenticated;
grant update (status, token_hash) on public.invitations to authenticated;

create policy "invitations: owner and admin read"
  on public.invitations for select to authenticated
  using (private.has_role(organization_id, array['owner', 'admin']));

create policy "invitations: owner and admin create"
  on public.invitations for insert to authenticated
  with check (private.can_write(organization_id, array['owner', 'admin']));

create policy "invitations: owner and admin cancel or resend"
  on public.invitations for update to authenticated
  using (private.can_write(organization_id, array['owner', 'admin']))
  with check (private.can_write(organization_id, array['owner', 'admin']));

-- 5.6 platform_admins (no insert/update/delete for anyone through the API)
grant select on public.platform_admins to authenticated;

create policy "platform_admins: read own row or as platform admin"
  on public.platform_admins for select to authenticated
  using (user_id = (select private.current_user_id()) or private.is_platform_admin());

-- 5.7 activity_logs (read-only; written only by the audit trigger)
grant select on public.activity_logs to authenticated;

create policy "activity_logs: read by owner/admin or platform admin"
  on public.activity_logs for select to authenticated
  using (
    (organization_id is not null and private.has_role(organization_id, array['owner', 'admin']))
    or (organization_id is null and private.is_platform_admin())
  );
