-- Mentor-Mentee Portal: run this whole file once in Supabase > SQL Editor.

create table departments (name text primary key);
insert into departments values ('Information Science'), ('Computer Science');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('mentee','mentor','admin')),
  name text not null,
  email text not null unique,
  dept text references departments(name) on update cascade,
  disabled boolean not null default false,
  title text, hours text,
  created_at timestamptz not null default now()
);

create table mentees (
  id uuid primary key references profiles(id) on delete cascade,
  mentor_id uuid references profiles(id) on delete set null,
  hobbies text[] not null default '{}',
  endorsed boolean not null default false,
  sems jsonb not null default '[null,null,null,null,null,null,null,null]',
  skills jsonb not null default '[]',
  goals jsonb not null default '[]',
  tasks jsonb not null default '[]',
  meetings jsonb not null default '[]',
  notif jsonb not null default '[]'
);

create table notes (
  id bigint generated always as identity primary key,
  mentee_id uuid not null references mentees(id) on delete cascade,
  mentor_id uuid not null references profiles(id),
  tag text not null check (tag in ('Praise','Advice','Concern')),
  text text not null,
  created_at timestamptz not null default now()
);

-- Helpers (a disabled account has no role, so every policy below rejects it)
create function my_role() returns text language sql stable security definer set search_path = public
as $$ select role from profiles where id = auth.uid() and not disabled $$;

create function is_my_mentee(mid uuid) returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from mentees where id = mid and mentor_id = auth.uid()) $$;

-- Guards: stop users from promoting themselves or self-endorsing
create function guard_profiles() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or my_role() = 'admin' then return new; end if;
  new.id := old.id; new.role := old.role; new.email := old.email;
  new.disabled := old.disabled; new.dept := old.dept;
  return new;
end $$;
create trigger t_guard_profiles before update on profiles for each row execute function guard_profiles();

create function guard_mentees() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or my_role() = 'admin' then return new; end if;
  if my_role() = 'mentee' then new.mentor_id := old.mentor_id; end if;
  if new.endorsed and not old.endorsed then new.endorsed := false; end if;
  return new;
end $$;
create trigger t_guard_mentees before update on mentees for each row execute function guard_mentees();

-- Row level security
alter table departments enable row level security;
alter table profiles enable row level security;
alter table mentees enable row level security;
alter table notes enable row level security;

create policy dept_read on departments for select to authenticated using (true);
create policy dept_admin on departments for all to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');

create policy prof_read on profiles for select to authenticated using (true);
create policy prof_self on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy prof_admin on profiles for all to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');

create policy mentee_read on mentees for select to authenticated using (
  my_role() = 'admin' or id = auth.uid()
  or (my_role() = 'mentor' and (mentor_id = auth.uid() or mentor_id is null)));
create policy mentee_update on mentees for update to authenticated
  using (my_role() = 'admin' or (my_role() = 'mentee' and id = auth.uid())
         or (my_role() = 'mentor' and (mentor_id = auth.uid() or mentor_id is null)))
  with check (my_role() = 'admin' or (my_role() = 'mentee' and id = auth.uid())
         or (my_role() = 'mentor' and (mentor_id = auth.uid() or mentor_id is null)));
create policy mentee_admin on mentees for all to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');

create policy notes_read on notes for select to authenticated using (
  my_role() = 'admin' or mentee_id = auth.uid() or mentor_id = auth.uid());
create policy notes_insert on notes for insert to authenticated
  with check (my_role() = 'mentor' and mentor_id = auth.uid() and is_my_mentee(mentee_id));
create policy notes_admin on notes for all to authenticated using (my_role() = 'admin') with check (my_role() = 'admin');

-- FIRST ADMIN: create the user under Authentication > Users (tick Auto Confirm), then run this
-- with that email:
-- insert into profiles (id, role, name, email, dept)
--   select id, 'admin', 'HOD', email, 'Information Science' from auth.users where email = 'YOUR_EMAIL';
