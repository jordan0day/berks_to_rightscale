# Copyright (c) 2012 Ryan J. Geyer
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'chef'

module BerksToRightscale
  class Cli < Thor

    desc "release PROJECTNAME RELEASENAME", "Releases the Cookbooks specified by a Berksfile or Berksfile.lock as a [PROJECTNAME]/[RELEASENAME].tar.gz file to the specified location."
    option :except, :desc => "Exclude cookbooks that are in these groups.", :type => :array
    option :only, :desc => "Only cookbooks that are in these groups.", :type => :array
    option :berksfile, :banner => "PATH", :desc => "Path to a Berksfile to operate off of.", :default => File.join(Dir.pwd, ::Berkshelf::DEFAULT_FILENAME)
    option :force, :desc => "Forces the current release with the same name to be overwritten.", :type => :boolean
    option :no_cleanup, :desc => "Skips the removal of the cookbooks directory and the generated tar.gz file", :type => :boolean
    option :provider, :desc => "A provider listed by list_destinations which will be used to upload the cookbook release", :required => true
    option :container, :desc => "The name of the storage container to put the release file in.", :required => true
    option :provider_options, :desc => "A comma-separated list of key=value options to pass to the fog storage provider. i.e. region=us-west-1", :required => false

    def release(projectname, releasename)
      output_path = ::File.join(Dir.pwd, "cookbooks")
      sym_options = {}
      options.each{|k,v| sym_options[k.to_sym] = v }
      final_opts = {:path => output_path, :force => false, :no_cleanup => false}.merge(sym_options)
      tarball = "#{releasename}.tar.gz"
      file_key = "#{projectname}/#{tarball}"

      tarball_path = ::File.join(Dir.pwd, tarball)

      fog_params = { :provider => final_opts[:provider] }

      if final_opts[:provider_options]
        provider_opts = { }
        begin
          # convert comma-separated list to hash
          option_list = final_opts[:provider_options].split(",")
          provider_opts = option_list.inject({}) do |hash, kv_pair|
            kv = kv_pair.split("=")
            raise "ERROR: value not found." unless kv[1]
            hash.merge({ kv[0] => kv[1] })
          end
        rescue
          puts "ERROR: malformed ---provider-options parameter.  Must be in the form of 'opt1=value1,opt2=value2'. Please try again."
          exit 1
        end
        # merge in provider options hash
        fog_params.merge!(provider_opts)
      end


      begin
        @fog = ::Fog::Storage.new(fog_params)
      rescue Exception => e
        puts "ERROR: Fog had a problem initializing storage provider: #{e.message}"
        exit 1
      end

      unless container = @fog.directories.all.detect {|cont| cont.key == final_opts[:container]}
        puts "There was no container named #{final_opts[:container]} for provider #{final_opts[:provider]}"
        exit 1
      end

      if container.files.all.detect {|file| file.key == file_key} && !final_opts[:force]
        puts "There is already a released named #{releasename} for the project #{projectname}.  If you want to overwrite it, specify the --force flag"
        exit 1
      end

      berksfile = ::Berkshelf::Berksfile.from_file(final_opts[:berksfile], final_opts)
      package_path = berksfile.package tarball_path

      file = File.open(tarball_path, 'r')
      fog_file = container.files.create(:key => file_key, :body => file, :acl => 'public-read')
      fog_file.save
      file.close

      puts "Released file can be found at #{fog_file.public_url}"

      # Cleanup
      unless final_opts[:no_cleanup]
        FileUtils.rm package_path if File.exist? package_path
      end

    end

    desc "list_destinations", "Lists all possible release locations.  Basically a list of supported fog storage providers"
    def list_destinations
      puts ::Fog::Storage.providers
    end
  end
end