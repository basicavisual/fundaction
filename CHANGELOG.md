# Unreleased

The main objectives of this release are as follows:
- Moving ActiveStorage files to DigitalOcean Spaces
- Using Redis for the Rails cache

## Additions

- `digitalocean` (S3) and `mirror` services in config/storage.yml
- `storage:copy_to_spaces` and `storage:verify_spaces` rake tasks at lib/tasks/storage_migration.rake
- scripts/daily_chores.sh rewritten for the current setup: runs the four daily tasks Decidim 0.26 expects (`decidim:delete_data_portability_files`, `decidim:metrics:all`, `decidim:open_data:export`, `decidim_meetings:clean_registration_forms`), from any install path, loading env vars from `.rbenv-vars` or `--env-file`. Meant to run once a day from cron
- New env vars: `ACTIVE_STORAGE_SERVICE` (local | mirror | digitalocean, default local), `SPACES_ENDPOINT`, `SPACES_REGION`, `SPACES_BUCKET`, `SPACES_ACCESS_KEY_ID`, `SPACES_SECRET_ACCESS_KEY`, `REDIS_CACHE_URL` (default redis://localhost:6379/2)

## Changes:
- Production cache store is now Redis instead of memcached, namespaced by instance and revision
- Requests to /rails/active_storage (images, attachments) no longer count towards the per-IP throttle that answered "Retry later" (config/initializers/rack_attack.rb). A page with 22 images used about 45 of the 100 requests per minute
- `DECIDIM_THROTTLING_MAX_REQUESTS` and `DECIDIM_THROTTLING_PERIOD` (seconds) are now actually read (config/initializers/decidim.rb); they were ignored before
- Cache namespace revision now comes from `REVISION` env var or the app's git HEAD (was a Capistrano REVISION file)

## Removals:
- Capistrano config (config/deploy.rb); deploys are done manually with scripts
- CarrierWave initializer; the CarrierWave → ActiveStorage migration is complete
- `public/uploads` and its .gitignore entry
- Dockerfile and docker-compose.yml (outdated; Docker deploys will be set up from scratch)

# Release 3.0

The main objectives of this release are as follows:
- Updating to version 0.26
- Ensuring admins are able to invite new people

## Additions

- New module to invite users at decidim-module-admin_invited_users/ it allows an admin to invite a user and resend invitations
- Script to automate migration process at scripts/migration_026.sh

## Changes:
- ForceAuthenticationPatch needed cleanup. Now renamed to HomepageVisibilityPatch. It avoids overriding existing code. Inserts at the application controller level rather than at the concern level.
- Restored values to config/environments/development.rb to ensure mailer is ready for development debugging
- Upgraded to version 0.26.9 (latest)

## Removals:
- Remove user invitations functionality. 
- Cleanup login screen override
- Remove replacement of share modal