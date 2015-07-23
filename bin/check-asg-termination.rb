#! /usr/bin/env ruby
#
# check-asg-termination
#
# DESCRIPTION:
#   This plugin checks if an instance has been given a termination notice.
#
# OUTPUT:
#   plain-text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#

require 'sensu-plugin/check/cli'
require 'aws-sdk'
require 'json'
require 'net/http'
require 'rest-client'
require 'uri'
require_relative 'common'


#
# Check SQS Messages
#
class CheckASGTermination < Sensu::Plugin::Check::CLI
  include Common

  option :aws_access_key,
         short: '-a AWS_ACCESS_KEY',
         long: '--aws-access-key AWS_ACCESS_KEY',
         description: "AWS Access Key. Either set ENV['AWS_ACCESS_KEY_ID'] or provide it as an option"

  option :aws_secret_access_key,
         short: '-s AWS_SECRET_ACCESS_KEY',
         long: '--aws-secret-access-key AWS_SECRET_ACCESS_KEY',
         description: "AWS Secret Access Key. Either set ENV['AWS_SECRET_ACCESS_KEY'] or provide it as an option"

  option :aws_region,
         description: 'AWS Region (such as us-east-1)',
         short: '-r AWS_REGION',
         long: '--aws-region AWS_REGION',
         default: 'us-east-1'

  option :queue,
         short: '-q SQS_QUEUE',
         long: '--queue SQS_QUEUE',
         description: 'The name of the SQS you want to check the number of messages for',
         required: true

  option :min_size_notification,
         short: '-m',
         long: '--min_size',
         description: "Only passes notifications if there are fewer terminating instances than the min size of the autoscaling group.",
         boolean: true

  option :sensu_port,
         description: 'Sensu api port. Defaults to 4567',
         short: '-p SENSU_PORT',
         long: '--sensu-port SENSU_PORT',
         default: '4567'

  option :sensu_host,
         description: 'Sensu api host. Defaults to localhost',
         short: '-h SENSU_HOST',
         long: '--sensu-host SENSU_HOST',
         default: 'localhost'

  option :asg_name,
         description: 'Autoscaling group name',
         short: '-g ASG_NAME',
         long: '--asg-name ASG_NAME',
         required: true

  def add_stash_termination_notification(message, asg_name)
    asg_terminations = get_termination_stashes(asg_name)
    updated_terminations = [message]
    if asg_terminations != nil && asg_terminations.kind_of?(Array)
        updated_terminations |= asg_terminations
    end
    update_Stash_termination_notification(updated_terminations, asg_name)
  end

  def update_stash_termination_notification(messages, asg_name)
    uri = get_sensu_api_uri(asg_name)
    RestClient.post uri, messages.to_json,:content_type => :json, :accept => :json
  end

  def delete_stash_termination_notification(asg_name)
    uri = get_sensu_api_uri(asg_name)
    RestClient.delete uri, :accept => :json
  end

  def get_termination_stashes(asg_name)
    uri = get_sensu_api_uri(asg_name)
    begin
        response = RestClient.get uri, , {:accept => :json}
    rescue RestClient::Exception => e
        nil
    end
    begin
        JSON.parse(response.body)
    rescue JSON::ParserError => e
        nil
    end
  end

  def validate_termination_messages()
    asg_terminations = get_termination_stashes(config[:asg_name])
    if asg_terminations != nil && asg_terminations.length > 0
        message_instance_ids = asg_terminations.collect{|message| message['EC2InstanceId']}
        instances_result = ec2.describe_instances({
            instance_ids: message_instance_ids
            })
        if(!instances_result.nil? && instances_result.reservations.nil? &&
            instances_result.reservations.length > 0)

            instances_result.reservations[0].instances[0]
        else
            delete_stash_termination_notification(config[:asg_name])
        end
    end
  end

  def get_sensu_api_uri(asg_name)
    URI("http://#{config[:sensu_host]}:#{config[:sensu_port]}/stashes/termination/#{asg_name}")
  end

  def run
    queue_url_resp = sqs.get_queue_url({
        queue_name: config[:queue]
        })
    queue_url = queue_url_resp.queue_url

    resp = sqs.receive_message({
        queue_url: queue_url,
        max_number_of_messages: 10,
        visibility_timeout: 10,
        })

    if (resp.messages.count == 1)
        begin
            message = JSON.parse(JSON.parse(msg.body)['Message'])

            if message['LifecycleTransition'] == "autoscaling:EC2_INSTANCE_TERMINATING"
                instance_id = message['EC2InstanceId']
                instance = get_first_instance(instance_id)

                if instance != nil
                    if instance.state.name != "stopped" && instance.status != "terminated"
                        auto_scaling_instance = get_first_autoscaling_instance(instance_id)
                        asg_group_name = auto_scaling_instance.auto_scaling_group_name
                        asg_group = get_first_autoscaling_group(asg_group_name)
                        if(config[:min_size_notification] &&
                            asg_group.min_size <= asg_group.instances.count { |instance| instance.lifecycle_state == "Terminating:Wait"})
                        else
                            stash_termination_notification(message, asg_group_name)
                        end
                    end
                end
            end
            msg.delete
        rescue Exception => e
            msg.delete
            warning "Error #{e.message}"
        end
    end


    if check_termination_stashes(config[:asg_name])
        critical "A node in the autoscaling group #{config[:asg_name]} has been given or is currently in a termination waiting state."
    end
  end
end
