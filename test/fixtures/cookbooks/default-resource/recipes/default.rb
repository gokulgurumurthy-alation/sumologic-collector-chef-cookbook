# frozen_string_literal: true

sumo_dir = node['platform_family'] == 'windows' ? 'c:\sumo' : '/opt/SumoCollector'

sumologic_collector sumo_dir do
  sumo_access_id node['SUMO_ACCESS_ID']
  sumo_access_key node['SUMO_ACCESS_KEY']
  ephemeral true
  skip_registration true
end
