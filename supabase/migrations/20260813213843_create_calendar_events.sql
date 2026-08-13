create table public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  all_day boolean not null default false,
  location text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendar_events_end_at_after_start_at check (end_at >= start_at)
);

create index calendar_events_user_id_start_at_idx
on public.calendar_events (user_id, start_at);

alter table public.calendar_events enable row level security;

create policy "Users can view own calendar events"
on public.calendar_events
for select
to authenticated
using (auth.uid() = user_id);

create policy "Users can create own calendar events"
on public.calendar_events
for insert
to authenticated
with check (auth.uid() = user_id);

create policy "Users can update own calendar events"
on public.calendar_events
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete own calendar events"
on public.calendar_events
for delete
to authenticated
using (auth.uid() = user_id);

grant select, insert, update, delete
on table public.calendar_events
to service_role;
