create table public.reminders (
  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  task_id uuid
    references public.tasks(id)
    on delete cascade,

  calendar_event_id uuid
    references public.calendar_events(id)
    on delete cascade,

  title text not null,

  trigger_type text not null
    default 'absolute',

  offset_minutes integer,

  remind_at timestamptz not null,

  status text not null
    default 'pending',

  created_at timestamptz not null
    default now(),

  updated_at timestamptz not null
    default now(),

  constraint reminders_title_not_empty
    check (length(trim(title)) > 0),

  constraint reminders_title_max_length
    check (length(title) <= 200),

  constraint reminders_status_valid
    check (
      status in (
        'pending',
        'triggered',
        'cancelled'
      )
    ),

  constraint reminders_trigger_type_valid
    check (
      trigger_type in (
        'absolute',
        'relative'
      )
    ),

  constraint reminders_single_parent
    check (
      not (
        task_id is not null
        and calendar_event_id is not null
      )
    ),

  constraint reminders_trigger_configuration_valid
    check (
      (
        trigger_type = 'absolute'
        and offset_minutes is null
      )
      or
      (
        trigger_type = 'relative'
        and offset_minutes is not null
        and (
          task_id is not null
          or calendar_event_id is not null
        )
      )
    )
);

create index reminders_user_remind_at_idx
  on public.reminders(user_id, remind_at);

create index reminders_task_id_idx
  on public.reminders(task_id)
  where task_id is not null;

create index reminders_calendar_event_id_idx
  on public.reminders(calendar_event_id)
  where calendar_event_id is not null;

alter table public.reminders enable row level security;

create policy "Users can view own reminders"
  on public.reminders
  for select
  using (auth.uid() = user_id);

create policy "Users can create own reminders"
  on public.reminders
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own reminders"
  on public.reminders
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own reminders"
  on public.reminders
  for delete
  using (auth.uid() = user_id);

grant select, insert, update, delete
  on public.reminders
  to service_role;