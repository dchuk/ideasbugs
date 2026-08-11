# Security policy

## Supported versions

Security fixes are released for the latest 1.x version. If a report also
affects the newest 0.x release, a backport may be published when the fix is
small and the affected application cannot upgrade immediately.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/yshmarov/ideasbugs/security/advisories/new)
and include the affected version, a minimal reproduction, impact, and any known
workaround. Credentials, session cookies, private application URLs, customer
feedback, screenshots, and production database contents should not be included.

Public disclosure should wait until a fixed version is available and affected
users have had a reasonable opportunity to upgrade.

## Data and deployment boundary

The submission endpoint is available to requests allowed by `config.enabled`,
which defaults to everyone because production feedback collection is the gem's
purpose. Hosts decide whether to narrow that gate. The dashboard is separately
protected by `authorize_admin` and fails closed outside development until the
host explicitly grants access.

A feedback record can store its kind, section, message, status, page URL, user
agent, timestamps, an opaque tenant key, optional host-provided author id and
label, and Active Storage screenshots. A screenshot can contain any data the
user's screen displayed. Screenshots stream through the dashboard gate rather
than public blob URLs, but hosts still own the storage service, bucket policy,
backups, retention period, access controls, and incident response.

Delete feedback with ordinary Active Record when a user request or application
policy requires erasure:

```ruby
Ideasbugs::Feedback.find(id).destroy!
```

That removes the record and lets Rails apply the configured Active Storage
attachment lifecycle. Confirm deletion separately in object storage, replicas,
backups, caches, and exports; deleting the live row does not rewrite them.
