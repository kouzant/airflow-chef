#include_recipe "java"

my_ip = my_private_ip()

hops_groups()

group node['sqoop']['group'] do
  action :create
  not_if "getent group #{node['sqoop']['group']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

user node['sqoop']['user'] do
  home "/home/#{node['sqoop']['user']}"
  gid node['sqoop']['group']
  action :create
  shell "/bin/bash"
  manage_home true
  not_if "getent passwd #{node['sqoop']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node["kagent"]["certs_group"] do
  action :manage
  append true
  excluded_members node['sqoop']['user']
  not_if { node['install']['external_users'].casecmp("true") == 0 }
  only_if { conda_helpers.is_upgrade }
end

group node['kagent']['userscerts_group'] do
  action :modify
  members node['sqoop']['user']
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['hops']['group'] do
  action :modify
  members ["#{node['sqoop']['user']}"]
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['sqoop']['group'] do
  action :modify
  members ["#{node['airflow']['user']}"]
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

package_url = "#{node['sqoop']['url']}"
base_package_filename = File.basename(package_url)
cached_package_filename = "#{Chef::Config['file_cache_path']}/#{base_package_filename}"

remote_file cached_package_filename do
  source package_url
  owner "#{node['sqoop']['user']}"
  mode "0644"
  action :create_if_missing
end

# Extract Sqoop
sqoop_downloaded = "#{node['sqoop']['home']}/.sqoop_extracted_#{node['sqoop']['version']}"

bash 'extract-sqoop' do
        user "root"
        group node['sqoop']['group']
        code <<-EOH
                set -e
                rm -rf #{node['sqoop']['base_dir']}
                tar -xf #{cached_package_filename} -C #{node['sqoop']['dir']}
                chown -R #{node['sqoop']['user']}:#{node['sqoop']['group']} #{node['sqoop']['home']}
                chmod 750 #{node['sqoop']['home']}
                touch #{sqoop_downloaded}
                chown -R #{node['sqoop']['user']}:#{node['sqoop']['group']} #{sqoop_downloaded}
        EOH
     not_if { ::File.exists?( "#{sqoop_downloaded}" ) }
end

link node['sqoop']['base_dir'] do
  owner node['sqoop']['user']
  group node['sqoop']['group']
  to node['sqoop']['home']
end

directory node['sqoop']['base_dir'] + "/log"  do
  owner node['sqoop']['user']
  group node['sqoop']['group']
  mode "750"
  action :create
end

exec = "#{node['ndb']['scripts_dir']}/mysql-client.sh"

bash 'create_sqoop_db' do
  user "root"
  code <<-EOF
      set -e
      #{exec} -e \"CREATE DATABASE IF NOT EXISTS sqoop CHARACTER SET latin1\"
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'localhost' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"CREATE USER IF NOT EXISTS '#{node['airflow']['mysql_user']}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '#{node['airflow']['mysql_password']}'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
      #{exec} -e \"GRANT NDB_STORED_USER ON *.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON sqoop.* TO '#{node['airflow']['mysql_user']}'@'localhost'\"
      #{exec} -e \"GRANT ALL PRIVILEGES ON sqoop.* TO '#{node['airflow']['mysql_user']}'@'127.0.0.1'\"
    EOF
  not_if "#{exec} -e 'show databases' | grep sqoop"
end


template "#{node['sqoop']['base_dir']}/conf/sqoop-site.xml" do
  source "sqoop-site.xml.erb"
  owner node['sqoop']['user']
  group node['sqoop']['group']
  mode 0750
  action :create
end

template "#{node['sqoop']['base_dir']}/conf/sqoop-env.sh" do
  source "sqoop-env.sh.erb"
  owner node['sqoop']['user']
  group node['sqoop']['group']
  mode 0750
  action :create
end

remote_file "#{node['sqoop']['base_dir']}/lib/mysql-connector-java-#{node['hive2']['mysql_connector_version']}-bin.jar" do
  source node['hive2']['mysql_connector_url']
  checksum node['hive2']['mysql_connector_checksum']
  owner node['sqoop']['user']
  group node['sqoop']['group']
  mode '0755'
  action :create_if_missing
end



service_name="sqoop"

service service_name do
  provider Chef::Provider::Service::Systemd
  supports :restart => true, :stop => true, :start => true, :status => true
  action :nothing
end

case node['platform_family']
when "rhel"
  systemd_script = "/usr/lib/systemd/system/#{service_name}.service"
else
  systemd_script = "/lib/systemd/system/#{service_name}.service"
end

template systemd_script do
  source "#{service_name}.service.erb"
  owner "root"
  group "root"
  mode 0754
  notifies :start, resources(:service => service_name), :immediately
end

service service_name do
  action :enable
  only_if {node['services']['enabled'] == "true"}
end

kagent_config service_name do
  action :systemd_reload
end

if node['kagent']['enabled'] == "true"
   kagent_config service_name do
     service "airflow"
     log_file "#{node['sqoop']['base_dir']}/log/sqoop-metastore-sqoop-localhost.log"
   end
end

