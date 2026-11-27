-- READ-ONLY. Describes the scheduled jobs without printing their commands, so
-- they can be compared with supabase/deploy/notifications_n2_schedule.sql by MD5.
--   supabase db query --linked --output-format json -f cron_jobs.sql
select jobname, schedule, active,
  command ~* 'vault' as uses_vault,
  length(command) as command_length,
  md5(command) as command_md5
from cron.job
order by jobname;
