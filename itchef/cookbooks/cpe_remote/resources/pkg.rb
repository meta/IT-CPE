# Cookbook Name:: cpe_remote
# Resource:: cpe_remote_pkg
#
# Copyright (c) Facebook, Inc. and its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

resource_name :cpe_remote_pkg
default_action :install

provides :cpe_remote_pkg, :os => 'darwin'
unified_mode(false) if Chef::VERSION >= 18
property :allow_downgrade, [TrueClass, FalseClass], :default => true
property :app, String, :name_property => true
property :checksum, String
property :backup, [FalseClass, Integer], :default => false
property :force_arm64, [TrueClass, FalseClass], :default => false
property :mpkg, [TrueClass, FalseClass], :default => false
property :pkg_name, String
property :pkg_url, String
property :receipt, String, :desired_state => false
property :remote, [TrueClass, FalseClass], :default => true
property :version, String

action_class do
  include CPE::Remote

  def log_info(msg)
    CPE::Log.log(
      msg,
      :level => :info,
      :type => 'cpe_remote_pkg',
      :action => 'install',
      :status => 'success',
    )
  end

  def log_warn(msg)
    CPE::Log.log(
      msg,
      :level => :warn,
      :type => 'cpe_remote_pkg',
      :action => 'install',
      :status => 'fail',
    )
  end

  def log_unless(msg)
    CPE::Log.unless(
      msg, :type => 'cpe_remote_pkg', :action => 'install', :status => 'fail'
    ) { yield }
  end
end

load_current_value do
  cmd = "/usr/sbin/pkgutil --pkg-info '#{receipt}'"
  version shell_out(cmd).stdout.to_s[/version: (.*)/, 1]
end

action :install do
  return unless log_unless(
    'Distro server inaccessible',
  ) { node['cpe_remote']['server_accessible'] }

  desired_version = new_resource.version
  installed_version = current_resource.version

  unless new_resource.allow_downgrade
    # If the package isn't installed (or the receipt doesn't resolve) there is
    # no installed version to compare against, and `Gem::Version.new(nil)`
    # raises ArgumentError. Treat that as "nothing installed" and proceed.
    if !installed_version.nil? &&
       !desired_version.nil? &&
       Gem::Version.new(installed_version) > Gem::Version.new(desired_version)
      log_info(
        "Installed version (#{installed_version}) is higher than desired " +
        "version (#{desired_version}), but allow_downgrade is false.",
      )
      return
    end
  end

  converge_if_changed :version do
    pkg_name = new_resource.app
    pkg_version_str = "-#{desired_version}"
    if new_resource.pkg_name
      pkg_name = new_resource.pkg_name
      pkg_version_str = ''
    end

    is_mpkg = new_resource.mpkg
    chef_cache = Chef::Config[:file_cache_path]

    # Download vars
    ext = is_mpkg ? 'zip' : 'pkg'
    download_file = "#{pkg_name}#{pkg_version_str}.#{ext}"
    download_file_path = "#{chef_cache}/#{download_file}"

    pkg_source = gen_url(new_resource.app, download_file)
    # someone can choose to override where there pkg is coming from
    pkg_source = new_resource.pkg_url if new_resource.pkg_url

    valid_url = valid_url?(pkg_source)
    cpe_remote_file download_file do
      only_if do
        CPE::Log.unless(
          "Failed to download package since url(#{pkg_source}) is invalid",
          :level => :warn,
          :type => 'cpe_remote_pkg',
          :action => "remote_file/#{download_file}",
          :status => 'fail',
        ) { valid_url }
      end
      path download_file_path
      file_url pkg_source
      folder_name new_resource.app
      backup new_resource.backup
      checksum new_resource.checksum
      unless node['cpe_remote']['additional_headers'].empty?
        headers node['cpe_remote']['additional_headers']
      end
    end

    # Unzip if is_mpkg
    execute "Unzipping #{download_file_path}" do
      only_if { is_mpkg }
      only_if { valid_url }
      command "cd #{chef_cache} && /usr/bin/unzip -o '#{download_file_path}'"
    end

    # install vars
    pkg_file = "#{pkg_name}#{pkg_version_str}.pkg"
    pkg_file_path = "#{chef_cache}/#{pkg_file}"
    pkg_on_disk = pkg_file_path
    if is_mpkg
      pkg_file = "#{pkg_name}#{pkg_version_str}.mpkg"
      pkg_file_path = "#{chef_cache}/#{pkg_name}/#{pkg_file}"
      pkg_on_disk = download_file_path
    end

    force_arm64 = new_resource.force_arm64
    cmd = "/usr/sbin/installer -pkg '#{pkg_file_path}' -target /"
    if force_arm64
      cmd = '/usr/bin/arch --arm64 ' + cmd
    end

    execute "Installing #{pkg_file}" do
      only_if { valid_url }
      only_if { validate_checksum(pkg_on_disk, new_resource.checksum) }
      command cmd
    end

    Chef.event_handler do
      on :resource_failed do |resource, _action, exception|
        if resource.to_s == "cpe_remote_pkg[#{pkg_name}]"
          CPE::Log.log(
            "#{pkg_file} install failed with exception: #{exception}",
            :level => :error,
            :type => 'cpe_remote_pkg',
            :action => 'install',
            :status => 'fail',
          )
        end
      end
    end

    Chef.event_handler do
      on :resource_updated do |resource|
        if resource.to_s == "cpe_remote_pkg[#{pkg_name}]"
          CPE::Log.log(
            "#{pkg_file} install succeeded",
            :level => :debug,
            :type => 'cpe_remote_pkg',
            :action => 'install',
            :status => 'success',
          )
        end
      end
    end

    keep_pkg = new_resource.backup ? true : false
    # Delete Zip if there is a ZIP
    file download_file_path do
      only_if { is_mpkg }
      only_if { valid_url }
      not_if { keep_pkg }
      action :delete
      backup false
    end

    # Delete MPKG
    directory pkg_file_path do
      only_if { is_mpkg }
      only_if { valid_url }
      not_if { keep_pkg }
      action :delete
      recursive true
    end

    # Delete PKG
    file "delete-#{pkg_file_path}" do
      not_if { is_mpkg }
      only_if { valid_url }
      not_if { keep_pkg }
      path pkg_file_path
      action :delete
      backup false
    end
  end
end
