-- Apply in Supabase SQL editor. Enable Anonymous sign-ins and Email OTP in Auth.
create extension if not exists pgcrypto;
create table public.fieldworks (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 title text not null check (char_length(title) between 1 and 120), created_at timestamptz not null default now()
);
create table public.sessions (
 id uuid primary key default gen_random_uuid(), fieldwork_id uuid not null references public.fieldworks(id) on delete cascade,
 owner_id uuid not null references auth.users(id), code text not null unique default upper(encode(gen_random_bytes(9),'hex')),
 ended_at timestamptz, created_at timestamptz not null default now()
);
create table public.session_members (
 session_id uuid not null references public.sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 joined_at timestamptz not null default now(), primary key(session_id,user_id)
);
create table public.session_state (
 session_id uuid primary key references public.sessions(id) on delete cascade,
 state jsonb not null default '{}'::jsonb,
 version bigint not null default 0, updated_at timestamptz not null default now()
);
create table public.content_items (
 id uuid primary key default gen_random_uuid(), session_id uuid not null references public.sessions(id) on delete cascade,
 title text not null check (char_length(title) between 1 and 120), storage_path text not null unique,
 created_at timestamptz not null default now()
);
create table public.markers (
 id uuid primary key default gen_random_uuid(), session_id uuid not null references public.sessions(id) on delete cascade,
 lng double precision not null check (lng between -180 and 180), lat double precision not null check (lat between -90 and 90),
 title text not null check (char_length(title) between 1 and 120), description text not null default '',
 photo_path text, resource_url text, created_at timestamptz not null default now()
);
create table public.tasks (
 id uuid primary key default gen_random_uuid(), marker_id uuid not null unique references public.markers(id) on delete cascade,
 session_id uuid not null references public.sessions(id) on delete cascade,
 question text not null default '', kind text not null check (kind in ('read','complete','short')),
 access text not null check (access in ('anytime','arrival')), radius_m int not null default 50 check (radius_m in (30,50,100,200))
);
create table public.task_completions (
 task_id uuid not null references public.tasks(id) on delete cascade,
 session_id uuid not null references public.sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id), answer text not null default '' check (char_length(answer)<=2000),
 completed_at timestamptz not null default now(), primary key(task_id,user_id)
);
create table public.annotations (
 id uuid primary key default gen_random_uuid(), session_id uuid not null references public.sessions(id) on delete cascade,
 content_id uuid references public.content_items(id) on delete cascade,
 kind text not null check (kind in ('free','circle','arrow','line','box')),
 points jsonb not null, layer text not null check (layer in ('image','map')),
 created_at timestamptz not null default now(), check (jsonb_array_length(points) between 1 and 600)
);
create table public.teacher_location (
 session_id uuid primary key references public.sessions(id) on delete cascade,
 lat double precision not null check (lat between -90 and 90), lng double precision not null check (lng between -180 and 180),
 updated_at timestamptz not null default now()
);
create index on public.content_items(session_id);
create index on public.markers(session_id);
create index on public.tasks(session_id);
create index on public.task_completions(session_id);
create index on public.annotations(session_id);
create or replace function public.is_teacher(s uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.sessions where id=s and owner_id=(select auth.uid()) and ended_at is null)
$$;
create or replace function public.is_member(s uuid) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.session_members m join public.sessions x on x.id=m.session_id
 where m.session_id=s and m.user_id=(select auth.uid()) and x.ended_at is null)
 or public.is_teacher(s)
$$;
create or replace function public.join_session(join_code text) returns uuid language plpgsql security definer set search_path = '' as $$
declare sid uuid;
begin
 if auth.uid() is null then raise exception 'Sign-in required'; end if;
 select id into sid from public.sessions where code=upper(trim(join_code)) and ended_at is null;
 if sid is null then raise exception 'Invalid or ended session'; end if;
 insert into public.session_members(session_id,user_id) values(sid,auth.uid()) on conflict do nothing;
 return sid;
end; $$;
grant execute on function public.join_session(text) to authenticated;
revoke execute on function public.join_session(text) from anon;
create or replace function public.on_session_insert() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.session_state(session_id,state) values(new.id,'{}');
 return new;
end; $$;
create trigger sessions_create_state after insert on public.sessions for each row execute function public.on_session_insert();
create or replace function public.prevent_reopen() returns trigger language plpgsql as $$
begin if old.ended_at is not null then raise exception 'Ended session cannot be changed'; end if; return new; end; $$;
create trigger prevent_session_reopen before update on public.sessions for each row execute function public.prevent_reopen();
create or replace function public.state_stamp() returns trigger language plpgsql set search_path = '' as $$
begin new.version=old.version+1; new.updated_at=now(); return new; end; $$;
create trigger stamp_state before update on public.session_state for each row execute function public.state_stamp();
create or replace function public.ensure_session_owner() returns trigger language plpgsql set search_path = '' as $$
begin
 if not exists(select 1 from public.fieldworks where id=new.fieldwork_id and owner_id=new.owner_id and owner_id=auth.uid())
 then raise exception 'Invalid fieldwork owner'; end if;
 return new;
end; $$;
create trigger session_owner_check before insert on public.sessions for each row execute function public.ensure_session_owner();
create or replace function public.clear_ended_location() returns trigger language plpgsql security definer set search_path = '' as $$
begin if new.ended_at is not null then delete from public.teacher_location where session_id=new.id; end if; return new; end; $$;
create trigger clear_location_on_end after update on public.sessions for each row execute function public.clear_ended_location();
create or replace function public.validate_task_relation() returns trigger language plpgsql set search_path = '' as $$
begin
 if not exists(select 1 from public.markers where id=new.marker_id and session_id=new.session_id)
 then raise exception 'Marker and task session mismatch'; end if; return new;
end; $$;
create or replace function public.validate_marker_photo() returns trigger language plpgsql as $$
begin if new.photo_path is not null and new.photo_path not like new.session_id::text || '/%' then raise exception 'Invalid photo path'; end if; return new; end; $$;
create trigger marker_photo_relation before insert or update on public.markers for each row execute function public.validate_marker_photo();
create trigger task_relation before insert or update on public.tasks for each row execute function public.validate_task_relation();
create or replace function public.validate_completion_relation() returns trigger language plpgsql set search_path = '' as $$
begin
 if not exists(select 1 from public.tasks where id=new.task_id and session_id=new.session_id)
 then raise exception 'Task and completion session mismatch'; end if; return new;
end; $$;
create trigger completion_relation before insert or update on public.task_completions for each row execute function public.validate_completion_relation();
create or replace function public.validate_annotation_relation() returns trigger language plpgsql set search_path = '' as $$
begin
 if new.layer='image' and (new.content_id is null or not exists(select 1 from public.content_items where id=new.content_id and session_id=new.session_id))
 then raise exception 'Invalid image'; end if; return new;
end; $$;
create trigger annotation_relation before insert or update on public.annotations for each row execute function public.validate_annotation_relation();
-- Never permit changing immutable ownership/linkage identifiers on an existing row.
create or replace function public.protect_ids() returns trigger language plpgsql as $$
begin
 if row_to_json(new)::jsonb - array['state','version','updated_at','ended_at','title','lat','lng','description','photo_path','resource_url','question','kind','access','radius_m','answer']
 <> row_to_json(old)::jsonb - array['state','version','updated_at','ended_at','title','lat','lng','description','photo_path','resource_url','question','kind','access','radius_m','answer']
 then raise exception 'Immutable identity'; end if; return new;
end; $$;
create trigger protect_sessions before update on public.sessions for each row execute function public.protect_ids();
create trigger protect_state before update on public.session_state for each row execute function public.protect_ids();
create trigger protect_markers before update on public.markers for each row execute function public.protect_ids();
create trigger protect_tasks before update on public.tasks for each row execute function public.protect_ids();
create trigger protect_completions before update on public.task_completions for each row execute function public.protect_ids();
create trigger protect_location before update on public.teacher_location for each row execute function public.protect_ids();
alter table public.fieldworks enable row level security;
alter table public.sessions enable row level security;
alter table public.session_members enable row level security;
alter table public.session_state enable row level security;
alter table public.content_items enable row level security;
alter table public.markers enable row level security;
alter table public.tasks enable row level security;
alter table public.task_completions enable row level security;
alter table public.annotations enable row level security;
alter table public.teacher_location enable row level security;
create policy fw_select on public.fieldworks for select to authenticated using(owner_id=auth.uid());
create policy fw_insert on public.fieldworks for insert to authenticated with check(owner_id=auth.uid() and coalesce(auth.jwt() ->> 'is_anonymous','false') = 'false');
create policy sess_select on public.sessions for select to authenticated using(public.is_member(id));
create policy sess_insert on public.sessions for insert to authenticated with check(owner_id=auth.uid());
create policy sess_update on public.sessions for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy member_select on public.session_members for select to authenticated using(public.is_teacher(session_id) or user_id=auth.uid());
create policy state_select on public.session_state for select to authenticated using(public.is_member(session_id));
create policy state_update on public.session_state for update to authenticated using(public.is_teacher(session_id)) with check(public.is_teacher(session_id));
create policy content_select on public.content_items for select to authenticated using(public.is_member(session_id));
create policy content_insert on public.content_items for insert to authenticated with check(public.is_teacher(session_id) and storage_path like session_id::text || '/%');
create policy content_delete on public.content_items for delete to authenticated using(public.is_teacher(session_id));
create policy marker_select on public.markers for select to authenticated using(public.is_member(session_id));
create policy marker_insert on public.markers for insert to authenticated with check(public.is_teacher(session_id));
create policy marker_update on public.markers for update to authenticated using(public.is_teacher(session_id)) with check(public.is_teacher(session_id));
create policy marker_delete on public.markers for delete to authenticated using(public.is_teacher(session_id));
create policy task_select on public.tasks for select to authenticated using(public.is_member(session_id));
create policy task_insert on public.tasks for insert to authenticated with check(public.is_teacher(session_id));
create policy task_update on public.tasks for update to authenticated using(public.is_teacher(session_id)) with check(public.is_teacher(session_id));
create policy task_delete on public.tasks for delete to authenticated using(public.is_teacher(session_id));
create policy completion_select on public.task_completions for select to authenticated using(public.is_teacher(session_id) or user_id=auth.uid());
create policy completion_insert on public.task_completions for insert to authenticated with check(public.is_member(session_id) and user_id=auth.uid());
create policy completion_update on public.task_completions for update to authenticated using(user_id=auth.uid() and public.is_member(session_id)) with check(user_id=auth.uid() and public.is_member(session_id));
create policy annotation_select on public.annotations for select to authenticated using(public.is_member(session_id));
create policy annotation_insert on public.annotations for insert to authenticated with check(public.is_teacher(session_id));
create policy annotation_delete on public.annotations for delete to authenticated using(public.is_teacher(session_id));
create policy loc_select on public.teacher_location for select to authenticated using(public.is_member(session_id));
create policy loc_insert on public.teacher_location for insert to authenticated with check(public.is_teacher(session_id));
create policy loc_update on public.teacher_location for update to authenticated using(public.is_teacher(session_id)) with check(public.is_teacher(session_id));
create policy loc_delete on public.teacher_location for delete to authenticated using(public.is_teacher(session_id));
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('fieldwork-images','fieldwork-images',false,10485760,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
create policy image_read on storage.objects for select to authenticated using(bucket_id='fieldwork-images' and public.is_member((split_part(name,'/',1))::uuid));
create policy image_write on storage.objects for insert to authenticated with check(bucket_id='fieldwork-images' and public.is_teacher((split_part(name,'/',1))::uuid));
create policy image_delete on storage.objects for delete to authenticated using(bucket_id='fieldwork-images' and public.is_teacher((split_part(name,'/',1))::uuid));
alter publication supabase_realtime add table public.session_state, public.content_items, public.markers, public.tasks, public.task_completions, public.annotations, public.teacher_location, public.sessions;
