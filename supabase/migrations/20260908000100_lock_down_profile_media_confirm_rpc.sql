begin;

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