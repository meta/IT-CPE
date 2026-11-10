# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

# Cookbook Name:: cpe_profiles
# Resource:: cpe_profiles

resource_name :cpe_profiles
provides :cpe_profiles, :os => 'darwin'
unified_mode(false) if Chef::VERSION >= 18
default_action :run

action :run do
  if node['cpe_profiles']['default_cookbook'].empty?
    Chef::Log.warn("#{cookbook_name}: No default profiles cookbook defined")
    return
  end
  map = node['cpe_profiles']['cookbook_map']
  default = node['cpe_profiles']['default_cookbook']
  prefix = node['cpe_profiles']['prefix']
  profiles.each do |k, v|
    # Chef::DelayedEvaluator's need accessed with node
    # if we want the real object type to be returned
    v = node['cpe_profiles'][k] if v.is_a?(Chef::DelayedEvaluator)

    # see if this prefix is overridden with a cookbook or fallback to default
    cookbook = map.key?(k) ? map[k] : default

    # read the 'destination' cookbook prefix
    cb_prefix = node[cookbook]['prefix']

    # replace the prefix name in the main Hash key
    new_prefix = k.sub(prefix, cb_prefix)

    # inject newly replaced profile into destination prefix
    node.default[cookbook][new_prefix] = profile_prefix_sub(v, cb_prefix)
  end
end

action_class do
  def profiles
    prefix = node['cpe_profiles']['prefix']
    allowed_profiles = [
      "#{prefix}.browsers.chrome",
      "#{prefix}.mde",
    ]
    node['cpe_profiles'].to_h.reject do |k, v|
      next true if [
        'prefix',
        'default_cookbook',
        'cookbook_map',
      ].include?(k)

      # Chef::DelayedEvaluator's need accessed with node
      # if we want the real object type to be returned
      v = node['cpe_profiles'][k] if v.is_a?(Chef::DelayedEvaluator)
      next true unless v.is_a?(Hash) && !v.empty?
      next false if allowed_profiles.include?(k) && v['PayloadIdentifier'] == k

      Chef::Log.warn(
        "#{cookbook_name}: Rejecting legacy profile #{k.inspect}. " +
          'cpe_profiles only supports the existing Chrome browser profile ' +
          'and MDE migration fallback. Store new profiles in Configerator ' +
          'and install them with cpe_cfgr_profiles. The profile key must ' +
          'also match its PayloadIdentifier.',
      )
      true
    end
  end

  def profile_prefix_sub(profile, cb_prefix)
    # rewrite prefix for profile
    new_profile = payload_prefix_sub(profile, cb_prefix)

    # rewrite prefix for each payload
    new_profile['PayloadContent'] = new_profile['PayloadContent'].map do |p|
      payload_prefix_sub(p, cb_prefix)
    end

    new_profile
  end

  def payload_prefix_sub(payload, cb_prefix)
    unless payload.key?('PayloadIdentifier')
      Chef::Log.warn(
        "#{cookbook_name}: payload does not contain"\
        " a ProfileIdentifier key: #{payload}",
      )
      return payload
    end

    prefix = node['cpe_profiles']['prefix']
    new_payload = payload.clone

    new_payload['PayloadIdentifier'] = new_payload['PayloadIdentifier'].sub(
      prefix, cb_prefix
    )

    new_payload
  end
end
