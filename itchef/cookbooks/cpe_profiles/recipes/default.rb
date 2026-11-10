# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

# Cookbook Name:: cpe_profiles
# Recipe:: default

return unless node.macos?

cpe_profiles 'Managing Configuration Profiles'
