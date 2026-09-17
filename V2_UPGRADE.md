# Ideasbugs 2.0 prerelease

This fork implements boards, moderation, votes, comments and duplicate merging. It is a prerelease candidate; do not describe it as the final upstream 2.0 release. See the validation record below before deploying.

## Install or upgrade

For a fresh install, run `bin/rails generate ideasbugs:install` and `bin/rails db:migrate`. The installer generates **two ordered migrations**: the compatible feedback baseline and the v2 upgrade. Running both produces the final schema and exercises the same backfill path used by existing hosts.

For a v1 install, back up the database and attachments, install this fork, run `bin/rails generate ideasbugs:upgrade`, inspect the generated migration, then migrate. Do not rerun the install or tenant generator. The upgrade recognizes pre-tenant installations too.

The upgrade preserves messages, authors, source context, legacy section values and screenshot attachments. It creates one private default board per existing opaque tenant (including the global nil tenant), assigns all existing feedback to those boards and leaves it **unlisted**. Empty installations get a private global default board. Later tenants get a default board on their first submission, protected by a unique database key.

| Old status | New status |
|---|---|
| open / in_review | under_review |
| resolved | complete |

The other lifecycle statuses are planned, in_progress, in_beta and not_planned. They are string scopes and predicates, not an enum. Moderation (`unlisted`, `listed`, `merged`) is separate from lifecycle.

The migration refuses unknown legacy statuses before changing schema, and refuses a rerun. It supports integer and UUID primary keys. It is intentionally irreversible: restoring the backup or deploying schema-compatible code is the rollback path; discussions and new statuses cannot be mapped losslessly back to v1.

## Required configuration changes

Every submission, vote and comment now requires `current_user` to return an object with a nonblank `id`. Anonymous users may read **public** boards, but private boards require a signed-in user. Configure identity before updating a v1 anonymous widget.

```ruby
Ideasbugs.configure do |config|
  config.current_user = ->(request) { request.env['warden']&.user }
  config.authorize_admin = ->(request) { request.env['warden']&.user&.platform_admin? }
  config.author_label = ->(user) { user.display_name.presence || 'Member' }
  config.tenant = ->(_request) { nil } # one shared product backlog
  config.use_public_ids = true      # optional opaque Board/Feedback URLs
end
```

Hooks receive the raw request, except `author_label` receives the user. Never trust a client-supplied identity, tenant or administrator flag. Labels are now **public** in voter lists and discussion; the default is `Member`, not email. Configure a safe display name. Historical private author metadata, source URLs, browser details and screenshots stay off customer pages. Screenshots remain on the authenticated administrator-only streaming route, even after feedback is listed. New uploads accept PNG, JPEG, WebP and GIF only. Legacy non-raster files download as attachments with a sandbox content-security policy; SVG never renders inline from this route.

`config.sections` has been removed. Remove it from existing initializers. The widget no longer offers or accepts sections, but the old database column remains for historical admin context.

## Surfaces and behavior

- `/feedback` remains the administrator dashboard. Review unlisted submissions, list/unlist independently of status, manage boards, delete comments and inspect voters.
- `/feedback/boards` is the customer entry point. Board lists support message search, kind filters and Trending (votes cast during the last seven days), Top (all current votes) and New. Board/item responses are private/no-store and noindex/nofollow.
- `/feedback/boards/:board_id/items/:item_id` shows discussion and voters. Vote POST adds and DELETE removes idempotently. Comments support one level of replies. Administrator comments are visibly marked using the server authorization hook.
- `ideasbugs_tag(board: board)` reuses the existing widget with board context. Ordinary `ideasbugs_tag` submits to the server-resolved default board. New submissions are unlisted until a moderator reviews the message for publication.
- A private board is for authenticated users in its tenant, not an extra per-board membership system.
- `use_public_ids = true` switches Board/Feedback route parameters to stored 12-character random identifiers. Their internal IDs and foreign keys do not change. Turning it on changes links; numeric URL fallback is deliberately disabled in that mode. Authorization remains tenant/board scoped.

Customer rendering can use `config.board_controller_class` and `config.board_layout`; these are independent of `base_controller_class` / `admin_layout`. Use a customer-safe base controller, never your administrator base. A host controller brings its helpers; changing a layout alone does not import isolated host helpers. The default is the engine's self-contained shell.

## Merge policy

A moderator enters the canonical request ID in the source's merge form. Both requests must be listed, belong to the same tenant and have matching board visibility. The source becomes read-only and points to the canonical request. Unique voters move while preserving original vote dates; duplicate voters count once. Source comments remain on the source. Earlier merged sources are redirected when a canonical request is merged again.

Row locks serialize voting, commenting and moderation with merge. Canonical requests with merged sources cannot be deleted. Default boards and nonempty boards cannot be deleted. Unlisting a canonical request hides its customer backlink. Keep sensitive reports unlisted; write a separate sanitized request when needed, since public editing is out of scope.

## Hooks and limits

```ruby
config.on_submit = ->(feedback) { }
config.on_status_change = ->(feedback, previous_status) { }
config.on_comment = ->(comment) { }
```

Hooks run after successful commit. A hook exception is logged without rolling back saved feedback or reporting a misleading failed submission. No external exactly-once delivery is promised. The host owns notification delivery, retry and any monthly selection process; the engine adds no subscriptions, mailers or notification preferences.

Configured request limits apply to submissions, votes and comments on Rails 7.2+. Rails 7.1 hosts must add an application/proxy limiter (for example their existing Rack middleware). Screenshot count/byte limits remain server-enforced. Comment bodies are limited to 10,000 characters.

## Validation and remaining release work

Implemented and covered locally: SQLite fresh/legacy/empty migration paths and unknown-status preflight; PostgreSQL UUID upgrade; concurrent duplicate votes, vote/merge and default-board creation; tenant/anonymous/moderator privacy boundaries; stable model counters; one-level replies; escaped text; lifecycle hooks; existing screenshot/widget behavior; opaque route mode.

Still required before declaring final 2.0:

- Run every supported Rails/Ruby CI combination; the matrix excludes Rails 8 on Ruby 3.2.
- Complete real-host integration, theme/accessibility and production object-storage checks.
- Extend merge concurrency proof to two simultaneous merges, and exercise all moderation/public privacy transitions in a real host.
- Broaden browser coverage for board management, merging, voter pagination and reply deletion. The automated narrow-width customer journey is a baseline, not a full visual audit.
- Review large-backlog query/HTML limits, and migration duration against a realistic v1 backup before upgrading a busy host. Upgrade backfill is intended for bounded product-feedback backlogs.
- Final translated customer-board copy remains follow-up work; existing widget/dashboard localization is retained, new customer controls currently use English.

No gem has been published and no production database has been migrated by these changes.

### Local prerelease validation — September 16, 2026

Ruby 4.0.5 (repository pin), Rails 8.1.3.1:

- Unit/integration/generated-migration suite: **187 tests, 2,543 assertions, all passed**.
- PostgreSQL separate-connection/UUID suite: **4 tests, 8 assertions, all passed** against disposable `ideasbugs_test_agent_20260916`; no host application database was used.
- Chrome system suite including widget screenshots and a narrow-width board vote/comment journey: **8 tests, 25 assertions, all passed**.
- RuboCop: **60 files, no offenses**. Widget JavaScript syntax and whitespace checks passed.

The supported-version CI matrix has been updated but has not yet run remotely. Real-host integration and the additional release checks above remain open.
