# frozen_string_literal: true

# Old Mill's WordPress import, one task per stage of Importers::OldMillImport
# (which the Old Mill adapter runs in its job). Media first, so the binaries
# are ours before the source site goes away:
#
#   bin/rails import:wordpress:media                    # default xml=tmp/oldmill.xml
#   bin/rails import:wordpress:media[path/to/wp.xml,storage/imports/foo]
#   bin/rails import:wordpress:all[path/to/wp.xml,storage/imports/foo]
#
# Arguments fall back to WP_XML, WP_DEST and (for beers) WP_MODE.

namespace :import do
  namespace :wordpress do
    wordpress_import = lambda do |xml_path: nil, dest_dir: nil, mode: nil|
      Importers::OldMillImport.new(xml_path || ENV["WP_XML"], dest_dir || ENV["WP_DEST"], mode: mode || ENV["WP_MODE"])
    end

    run = lambda do |stage, **options|
      wordpress_import.call(**options).public_send(stage)
    rescue Importers::WordpressImport::Error => e
      abort e.message
    end

    desc "Mirror media from a WordPress WXR export. Args: [xml_path,dest_dir]"
    task :media, [:xml_path, :dest_dir] => :environment do |_, args|
      run.call(:media, xml_path: args[:xml_path], dest_dir: args[:dest_dir])
    end

    desc "Create Asset records from the mirrored media. Args: [dest_dir]"
    task :assets, [:dest_dir] => :environment do |_, args|
      run.call(:assets, dest_dir: args[:dest_dir])
    end

    desc "Populate the general Global from the WP export + live-site scrape."
    task globals: :environment do
      run.call(:globals)
    end

    desc "Import 'beer' WP custom posts as a 'beers' collection. Args: [xml_path,dest_dir,mode]"
    task :beers, [:xml_path, :dest_dir, :mode] => :environment do |_, args|
      run.call(:beers, xml_path: args[:xml_path], dest_dir: args[:dest_dir], mode: args[:mode])
    end

    desc "Import 'food' WP posts as a 'food' collection. Args: [xml_path,dest_dir]"
    task :food, [:xml_path, :dest_dir] => :environment do |_, args|
      run.call(:food, xml_path: args[:xml_path], dest_dir: args[:dest_dir])
    end

    desc "Import 'special' WP custom posts as a 'specials' collection. Args: [xml_path,dest_dir]"
    task :specials, [:xml_path, :dest_dir] => :environment do |_, args|
      run.call(:specials, xml_path: args[:xml_path], dest_dir: args[:dest_dir])
    end

    desc "Import WP 'page' posts as Pages. Args: [xml_path,dest_dir]"
    task :pages, [:xml_path, :dest_dir] => :environment do |_, args|
      run.call(:pages, xml_path: args[:xml_path], dest_dir: args[:dest_dir])
    end

    desc "Run the full WordPress import (media → assets → globals → beers → food → specials → pages)"
    task :all, [:xml_path, :dest_dir] => :environment do |_, args|
      run.call(:all, xml_path: args[:xml_path], dest_dir: args[:dest_dir])
    end
  end
end
