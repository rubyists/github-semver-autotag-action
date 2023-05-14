#!/usr/bin/env ruby

# frozen_string_literal: true

require 'octokit'
require 'pry'
require 'semverse'

module Semverse
  # Monkey patching the Version class for two things we'll use
  class Version
    # returns a new Version array suitable for bumping
    def to_a
      [major, minor, patch, pre_release, build]
    end

    # returns a new Version with the bump reflected
    def bump!(type)
      version_array = to_a
      case type
      when :major
        version_array[0] += 1
      when :minor
        version_array[1] += 1
      when :patch
        version_array[2] += 1
      end
      self.class.new(version_array)
    end
  end
end

module Rubyists
  module Github
    module Action
      # Tag the repo with the next version
      class AutoTag
        DEFAULT_BUMP_TYPE = ENV.fetch('DEFAULT_BUMP_TYPE', :minor).to_sym
        DEFAULT_VERSION = Semverse::Version.new('0.0.0')
        TOKEN = ENV.fetch('GITHUB_TOKEN', nil)

        def with_v
          @with_v ||= ENV.fetch('WITH_V', 'v') # default to leading v
        end

        def self.run!
          new.run!
        end

        def org_name
          @org_name ||= ENV['GITHUB_ORG'] || 'rubyists'
        end

        def repo_name
          @repo_name ||= ENV['GITHUB_REPOSITORY'] || 'rubyists/github-semver-autotag-action'
        end

        def client
          @client ||= if TOKEN
                        Octokit::Client.new(auto_paginate: true, access_token: TOKEN)
                      else
                        Octokit::Client.new(auto_paginate: true)
                      end
        end

        def repo
          @repo ||= client.repository repo_name
        rescue Octokit::NotFound
          warn ''
          warn "Yo, that repository (#{repo_name}) doesn't seem to exist, or you don't have accees"
          warn 'Bailing and stuff'
        end

        def run!
          puts "Running for #{repo_name}"
          return self unless repo

          tag_it!
          self
        end

        def latest_version
          @latest_version ||= Semverse::Version.new(latest_tag.to_s)
        end

        def latest_tag
          @latest_tag ||= repo.rels[:tags].get.data.first || DEFAULT_VERSION
        end

        def this_commit
          @this_commit ||= repo.rels[:commits].get.data.first
        end

        def this_commit_message
          @this_commit_message ||= this_commit.commit.message
        end

        def last_tag_commit_message
          @last_tag_commit_message ||= ''
        end

        def bump_from_regex
          case this_commit_message
          when /#(?:major|breaking)\b/i
            :major
          when /#(?:minor|normal)\b/i
            :minor
          when /#(?:patch|trivial)\b/i
            :patch
          end
        end

        def pull_request
          false
        end

        def bump_from_label
          return unless pull_request

          case pull_request.labels
          when /(?:major|breaking)\b/i
            :major
          when /(?:minor|normal)\b/i
            :minor
          when /(?:patch|trivial)\b/i
            :patch
          end
        end

        def bump_type
          @bump_type ||= bump_from_regex || bump_from_label || DEFAULT_BUMP_TYPE
        end

        def next_tag
          @next_tag ||= with_v + latest_version.bump!(bump_type).to_s
        end

        def logged_in?
          if client.login.nil?
            logger.error 'You are not logged in, you must be logged in to push a tag'
            logger.error 'Please set the GITHUB_TOKEN environment variable'
            return false
          end
          true
        end

        def create_ref!
          client.create_ref(repo_name, "tags/#{next_tag}", this_commit.sha)
        rescue Octokit::NotFound => e
          if logged_in?
            logger.error "Failed to tag #{repo_name} with #{next_tag}, #{e.message}"
          else
            logger.error "Can't push a tag when you are not logged in. Would have tagged #{repo_name} with #{next_tag}"
          end
          false
        end

        def tag_it!
          logger.debug "Tagging with #{next_tag}"
          if create_ref!
            logger.debug "Tagged #{repo_name} with #{next_tag}"
          else
            logger.debug "Unable to #{repo_name} with #{next_tag}"
            exit 1
          end
        end

        def logger
          @logger ||= Logger.new($stderr)
        end
      end
    end
  end
end

Rubyists::Github::Action::AutoTag.run! if $PROGRAM_NAME == __FILE__
