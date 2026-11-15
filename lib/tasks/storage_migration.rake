# frozen_string_literal: true

# Copy ActiveStorage files from the local Disk service to DigitalOcean Spaces.
#
#   bin/rails storage:copy_to_spaces   # upload every file not yet in Spaces (safe to re-run)
#   bin/rails storage:verify_spaces    # check every blob exists in Spaces
#
# Both read the `local` and `digitalocean` services from config/storage.yml,
# whatever ACTIVE_STORAGE_SERVICE is set to. DRY_RUN=1 lists without uploading.
namespace :storage do
  build_service = lambda do |name|
    # Rails 6.0 reads config/storage.yml lazily, when ActiveStorage::Blob loads.
    ActiveStorage::Blob
    configs = Rails.configuration.active_storage.service_configurations
    ActiveStorage::Service.configure(name, configs)
  end

  desc "Upload local ActiveStorage files (blobs and variants) to DigitalOcean Spaces"
  task copy_to_spaces: :environment do
    local = build_service.call(:local)
    spaces = build_service.call(:digitalocean)
    root = Pathname.new(local.root)
    dry_run = ENV["DRY_RUN"].present?

    copied = skipped = failed = 0
    Dir.glob(root.join("**", "*")).sort.each do |path|
      next unless File.file?(path)

      # Disk layout is root/ab/cd/<key>; the key may itself contain slashes
      # (variants/<blob key>/<digest>).
      relative = Pathname.new(path).relative_path_from(root).to_s
      parts = relative.split("/", 3)
      next unless parts.size == 3 && parts[0].size == 2 && parts[1].size == 2

      key = parts[2]
      if spaces.exist?(key)
        skipped += 1
        next
      end

      if dry_run
        puts "would copy #{key}"
        copied += 1
        next
      end

      begin
        blob = ActiveStorage::Blob.find_by(key: key)
        File.open(path, "rb") do |io|
          spaces.upload(key, io, checksum: blob&.checksum, content_type: blob&.content_type)
        end
        copied += 1
        puts "copied #{key}" if (copied % 100).zero?
      rescue StandardError => e
        failed += 1
        warn "FAILED #{key}: #{e.class}: #{e.message}"
      end
    end

    puts "#{dry_run ? "Would copy" : "Copied"}: #{copied}, already in Spaces: #{skipped}, failed: #{failed}"
    exit 1 if failed.positive?
  end

  desc "Check that every ActiveStorage blob exists in DigitalOcean Spaces"
  task verify_spaces: :environment do
    spaces = build_service.call(:digitalocean)
    missing = []
    unattached = []
    total = 0

    ActiveStorage::Blob.find_each do |blob|
      total += 1
      next if spaces.exist?(blob.key)

      # Blobs no record points to are not served anywhere; report, don't fail.
      (ActiveStorage::Attachment.exists?(blob_id: blob.id) ? missing : unattached) << blob
    end

    missing.each { |blob| puts "MISSING blob ##{blob.id} #{blob.key} #{blob.filename}" }
    unattached.each { |blob| puts "unattached (ignored) blob ##{blob.id} #{blob.key} #{blob.filename}" }
    puts "Blobs: #{total}, missing in Spaces: #{missing.size}, unattached and missing: #{unattached.size}"
    exit 1 if missing.any?
  end
end
