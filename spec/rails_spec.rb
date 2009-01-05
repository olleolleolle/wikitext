#!/usr/bin/env ruby
# Copyright 2009 Wincent Colaiuta
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require File.join(File.dirname(__FILE__), 'spec_helper.rb')
require 'wikitext/version'
require 'fileutils'
require 'pathname'

# TODO: silence stdout for these commands; want the specs to run silently unless errors occur
module RailsSpecs
  TRASH_PATH    = Pathname.new(__FILE__).dirname + 'trash'
  CLONE_PATH    = TRASH_PATH + 'rails.git'
  RAILS_PATH    = CLONE_PATH + 'railties' + 'bin' + 'rails'
  EDGE_APP_PATH = TRASH_PATH + 'edge-app'

  def clone
    if File.exist? CLONE_PATH
      system "cd #{CLONE_PATH} && git fetch"
    else
      system "git clone git://github.com/rails/rails.git #{CLONE_PATH}"
    end
  end

  def app_path version
    TRASH_PATH + "#{version}-app"
  end

  def create_base_app_and_symlinks app, &block
    clone
    FileUtils.rm_r(app) if File.exist?(app)
    yield
    system "ruby #{RAILS_PATH} #{app}"
    vendor = app + 'vendor'
    gems = vendor + 'gems'
    system "cd #{vendor} && ln -s ../../rails.git rails"
    FileUtils.mkdir gems
    system "cd #{gems} && ln -s ../../../../.. wikitext-#{Wikitext::VERSION}"
  end

  def create_release_app version
    create_base_app_and_symlinks app_path(version) do
      system "cd #{CLONE_PATH} && git checkout v#{version} && git clean -f"
    end
  end

  def insert text, after, infile
    output = []
    found   = false
    File.read(infile).split("\n").each do |line|
      output << line
      if found == false && line =~ /#{Regexp.escape(after)}/
        found = true
        output << text
      end
    end
    File.open(infile, 'wb') { |f| f.write(output.join("\n")) }
    raise "text '#{after}' not found" unless found
  end

  def add_text_to_initializer text, infile
    insert text, 'Rails::Initializer.run do', infile
  end

  def create_controller app
    File.open(app + 'app' + 'controllers' + 'wiki_controller.rb', 'w') do |f|
      f.write 'class WikiController < ApplicationController; end'
    end
  end

  def create_template app
    template_dir = app + 'app' + 'views' + 'wiki'
    FileUtils.mkdir template_dir
    File.open(template_dir + 'index.html.wikitext', 'w') do |f|
      f.write '* hello, world!'
    end
  end

  def create_test app
    # integration tests won't run without a schema.rb
    FileUtils.touch app + 'db' + 'schema.rb'

    File.open(app + 'test' + 'integration' + 'wiki_test.rb', 'w') do |f|
      f.write <<'TEST'
require File.join(File.dirname(__FILE__), '..', 'test_helper')

class WikiTest < ActionController::IntegrationTest
  def test_wiki_index
    get "/wiki"
    assert_response :success
    assert_template "wiki/index"
    assert_select 'ul>li', 'hello, world!'
  end
end
TEST
      end
  end

  def create_edge_app
    create_base_app_and_symlinks EDGE_APP_PATH do
      system "cd #{CLONE_PATH} && git checkout master && git merge origin/master && git clean -f"
    end
  end

  def update_environment app
    environment =  app + 'config' + 'environment.rb'
    add_text_to_initializer "  config.gem 'wikitext', :version => '#{Wikitext::VERSION}'", environment
    system "cd #{app} && rake gems:refresh_specs"
  end

  def setup_release_app version
    create_release_app version
    path = app_path(version)
    update_environment path
    create_controller path
    create_template path
    create_test path
  end

  def setup_edge_app
    create_edge_app
    update_environment EDGE_APP_PATH
    create_controller EDGE_APP_PATH
    create_template EDGE_APP_PATH
    create_test EDGE_APP_PATH
  end

  def run_integration_test app
    # TODO: use wopen3 here to capture output nicely
    `cd #{app} && rake test:integration`
  end
end # module RailsSpecs

describe 'Template handler in Rails 2.2.2' do
  include RailsSpecs
  version = '2.2.2'

  before(:all) do
    setup_release_app version
    @path = app_path(version)
  end

  it 'should process the template using the wikitext module' do
    run_integration_test(@path).should =~ /1 tests, 3 assertions, 0 failures, 0 errors/
  end
end