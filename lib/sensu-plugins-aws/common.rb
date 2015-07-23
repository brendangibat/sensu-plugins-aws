#
# DESCRIPTION:
#   Common helper methods
#
# DEPENDENCIES:
#   gem: aws-sdk
#   gem: sensu-plugin
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Shane Starcher <shane.starcher@gmail.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

module Common
  def initialize
    super()
    aws_config
  end

  def aws_config
    Aws.config.update(
      credentials: Aws::Credentials.new(config[:aws_access_key], config[:aws_secret_access_key])
    ) if config[:aws_access_key] && config[:aws_secret_access_key]

    Aws.config.update(
      region: config[:aws_region]
    )
  end

  def get_first_instance(instance_id)
    instances_result = ec2.describe_instances({
        instance_ids: [instance_id]
        })
    if(instances_result.nil? || instances_result.reservations.nil? ||
        instances_result.reservations.length == 0 ||
        instances_result.reservations[0].instances.nil? ||
        instances_result.reservations[0].instances.length == 0)
        nil
    else
        instances_result.reservations[0].instances[0]
    end
  end

  def get_first_autoscaling_instance(instance_id)
    instances_result = auto_scaling.describe_instances({
        instance_ids: [instance_id]
        })
    if(instances_result.nil? || instances_result.auto_scaling_instances.nil? ||
        instances_result.auto_scaling_instances.length == 0)
        nil
    else
        instances_result.auto_scaling_instances[0]
    end
  end

  def get_first_autoscaling_group(group_name)
    asg_groups_resp = auto_scaling.describe_auto_scaling_groups({
        auto_scaling_group_names: [group_name]
        })
    if(asg_groups_resp.nil? || asg_groups_resp.auto_scaling_groups.nil? ||
        asg_groups_resp.auto_scaling_groups.length == 0)
        nil
    else
        asg_groups_resp.autoscaling_groups[0]
    end
  end

  def auto_scaling
    @auto_scaling ||= begin
        Aws::AutoScaling::Client.new(region: region)
    end
  end

  def ec2
    @ec2 ||= begin
        Aws::EC2::Client.new(region: region)
    end
  end

  def sqs
    @sqs ||= begin
        Aws::SQS::Client.new(region: region)
    end
  end
end
