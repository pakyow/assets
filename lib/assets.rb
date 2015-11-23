require 'fileutils'

module Pakyow
  module Assets
    def self.register_path_with_name(path, name)
      stores[name] = {
        path: String.normalize_path(path),
        assets: assets_at_path(path)
      }
    end

    def self.assets_at_path(path)
      Dir.glob(File.join(path, '**/[!_]*.[a-z]*')).map { |asset|
        String.normalize_path(asset.gsub(path, ''))
      }
    end

    def self.stores
      @stores ||= {}
    end

    def self.preprocessors
      @preprocessors ||= {}
    end

    def self.compiled_asset_path_for_request_path(path)
      path = String.normalize_path(path)
      ext = File.extname(path)

      return unless path =~ /\.(.*)$/
      return unless preprocessor?(ext)

      path_regex = /#{path.gsub(ext, '')}\.(#{alias_exts(ext).map(&:to_s).join('|')})/

      @stores.each_pair do |name, info|
        if asset = info[:assets].find { |asset| asset =~ path_regex }
          return compile_asset_at_path(asset, info[:path])
        end
      end

      nil
    end

    def self.normalize_ext(ext)
      ext.gsub(/[^a-z]/, '').to_sym
    end

    def self.alias_exts(ext)
      preprocessors.select { |_, info|
        info[:output_ext] == normalize_ext(ext)
      }.keys
    end

    def self.output_ext(ext)
      ".#{preprocessors[normalize_ext(ext)][:output_ext]}"
    end

    def self.preprocessor?(ext)
      preprocessors.values.map { |info| info[:output_ext] }.flatten.include?(normalize_ext(ext))
    end

    def self.compile_asset_at_path(asset, path)
      absolute_path = File.join(path, asset)

      asset_dir = File.dirname(asset)
      asset_ext = output_ext(File.extname(asset))
      asset_file = File.basename(asset, '.*')

      compiled_path = File.join(
        Pakyow::Config.app.root,
        Pakyow::Config.assets.compiled_asset_path,
        asset_dir,
        "#{asset_file + '-' + Digest::MD5.file(absolute_path).hexdigest + asset_ext}"
      )

      unless File.exists?(compiled_path)
        FileUtils.mkdir_p(File.dirname(compiled_path))
        FileUtils.rm(Dir.glob(File.join(Pakyow::Config.app.root, Pakyow::Config.assets.compiled_asset_path, asset_dir, "#{asset_file}-*#{asset_ext}")))
        File.open(compiled_path, 'wb+') { |fp| fp.write(preprocess(absolute_path)) }
      end

      compiled_path
    end

    def self.preprocessor(*exts, output: nil, fingerprint_contents: false, &block)
      exts.each do |ext|
        preprocessors[ext] = {
          block: block,
          output_ext: output || ext,
          fingerprint_contents: fingerprint_contents
        }
      end
    end

    def self.preprocess(path)
      preprocessor = preprocessors[normalize_ext(File.extname(path))]
      block = preprocessor[:block]

      contents = block.nil? ? File.open(path, 'rb').read : block.call(path)
      preprocessor[:fingerprint_contents] ? mixin_fingerprints(contents) : contents
    end

    def self.precompile
      if File.exists?(Pakyow::Config.assets.compiled_asset_path)
        FileUtils.rm_r(Pakyow::Config.assets.compiled_asset_path)
      end

      stores.each do |_, info|
        info[:assets].each do |asset|
          compile_asset_at_path(asset, info[:path])
          absolute_path = File.join(info[:path], asset)

          fingerprint = Digest::MD5.file(absolute_path).hexdigest

          fingerprinted_asset = File.join(
            File.dirname(asset),
            "#{File.basename(asset, '.*')}-#{fingerprint + output_ext(File.extname(asset))}",
          )

          replaceable_asset = File.join(
            File.dirname(asset),
            File.basename(asset, '.*') + output_ext(File.extname(asset)),
          )

          manifest[replaceable_asset] = fingerprinted_asset
        end
      end
    end

    def self.manifest
      @manifest ||= {}
    end

    def self.mixin_fingerprints(content)
      return content if content.nil? || content.empty?

      manifest.each do |asset, fingerprinted_asset|
        content = content.gsub(asset, fingerprinted_asset)
      end

      content
    end
  end
end