cpe_profiles Cookbook
=====================

Legacy routing only
-------------------
This is an internal-only CPE cookbook, not an open-source profile installer.
Do not add new profiles to `node['cpe_profiles']`. Store profile payloads in
Configerator and select them from Chef through `cpe_cfgr_profiles` instead.

This resource accepts only the existing profiles keyed by:
* `#{node['cpe_profiles']['prefix']}.browsers.chrome` — the combined Chrome and
  Chrome Canary browser policy profile.
* `#{node['cpe_profiles']['prefix']}.mde` — the MDE migration/rollback fallback,
  retained until its static replacement profiles are installed.

The key must exactly match the profile's `PayloadIdentifier`. Other nonempty
profile hashes are rejected with a Chef warning explaining the supported path.
The allowlist is not configurable. It does not permit new per-extension profiles
or a separate Chrome Canary browser profile.

Routing
-------
`cpe_profiles` forwards accepted profile hashes to the cookbook selected by
`default_cookbook`, or a per-profile override in `cookbook_map`. It rewrites the
source prefix in the profile key and payload identifiers to the destination
cookbook's prefix.

The default source prefix is `com.facebook.prefix-rewritten.chef`. The
`cpe_profiles_interngraph` destination prefix is `com.facebook.mdm.chef`, so the
accepted Chrome and MDE profiles are delivered with `.browsers.chrome` and
`.mde` suffixes respectively. The resource must run before the destination
installer.

The retired CPE MDM Canary marker is no longer installed by
`cpe_base_settings::profiles` and is removed through normal
`cpe_profiles_interngraph` reconciliation. Direct writes to destination
cookbooks are outside this resource's guard.

Attributes
----------
* `node['cpe_profiles']`
* `node['cpe_profiles']['prefix']`
* `node['cpe_profiles']['default_cookbook']`
* `node['cpe_profiles']['cookbook_map']`
