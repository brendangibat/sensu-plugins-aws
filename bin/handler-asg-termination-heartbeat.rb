#!/usr/bin/env ruby
#

require 'sensu-handler'
require 'aws-sdk'
require 'json'
require 'net/http'
require 'uri'
require_relative 'common'

class AsgTerminationHandler < Sensu::Handler
  include Common
  def filter; end

  def handle

    

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
