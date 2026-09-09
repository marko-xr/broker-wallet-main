begin;

create or replace function public.confirm_profile_media_upload(
  p_user_id uuid,
  p_media_id uuid,
  p_observed_size bigint,
  p_observed_content_type text default null
)
returns table(
  previous_media_id uuid,
  profile_media_id uuid
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_owner_id uuid;
  v_status text;
  v_expected_content_type text;
  v_previous_media_id uuid;
begin
  if p_user_id is null or p_media_id is null then
    raise exception 'p_user_id and p_media_id are required';
  end if;

  if p_observed_size is null
     or p_observed_size <= 0
     or p_observed_size > 10485760 then
    raise exception 'Observed object size out of allowed range';
  end if;

  select mo.owner_id, mo.status, mo.content_type
    into v_owner_id, v_status, v_expected_content_type
  from public.media_objects as mo
  where mo.id = p_media_id
  for update;

  if not found then
    raise exception 'Media object not found';
  end if;

  if v_owner_id is distinct from p_user_id then
    raise exception 'Media object owner mismatch';
  end if;

  if p_observed_content_type is not null
     and v_expected_content_type is not null
     and lower(trim(p_observed_content_type))
         <> lower(trim(v_expected_content_type)) then
    raise exception
      'Observed content type does not match expected media content type';
  end if;

  select p.profile_media_id
    into v_previous_media_id
  from public.profiles as p
  where p.id = p_user_id
  for update;

  if not found then
    raise exception 'Profile not found for user';
  end if;

  if v_status = 'pending_upload' then
    update public.media_objects
    set
      status = 'ready',
      size_bytes = p_observed_size
    where id = p_media_id;
  elsif v_status = 'ready' then
    update public.media_objects
    set
      size_bytes = p_observed_size
    where id = p_media_id;
  else
    raise exception 'Unsupported media status for confirm: %', v_status;
  end if;

  if v_previous_media_id is distinct from p_media_id then
    update public.profiles
    set profile_media_id = p_media_id
    where id = p_user_id;
  end if;

  previous_media_id := v_previous_media_id;
  profile_media_id := p_media_id;

  return next;
end;
$function$;

-- Reassert the security boundary after replacing the function.
revoke all on function public.confirm_profile_media_upload(
  uuid,
  uuid,
  bigint,
  text
) from public;

revoke all on function public.confirm_profile_media_upload(
  uuid,
  uuid,
  bigint,
  text
) from anon;

revoke all on function public.confirm_profile_media_upload(
  uuid,
  uuid,
  bigint,
  text
) from authenticated;

grant execute on function public.confirm_profile_media_upload(
  uuid,
  uuid,
  bigint,
  text
) to service_role;

commit;