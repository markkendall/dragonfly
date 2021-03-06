require 'pathname'

module Dragonfly
  module DataStorage

    class FileDataStore

      include Configurable

      configurable_attr :root_path, '/var/tmp/dragonfly'

      def store(temp_object, opts={})
        meta = opts[:meta] || {}
        relative_path = if opts[:path]
          opts[:path]
        else
          filename = meta[:name] || temp_object.original_filename || 'file'
          relative_path = relative_path_for(filename)
        end

        begin
          path = absolute(relative_path)
          until !File.exist?(path)
            path = disambiguate(path)
          end
          prepare_path(path)
          temp_object.to_file(path).close
          store_meta_data(path, meta)
        rescue Errno::EACCES => e
          raise UnableToStore, e.message
        end

        relative(path)
      end

      def retrieve(relative_path)
        path = absolute(relative_path)
        pathname = path.to_pathname
        raise DataNotFound, "couldn't find file #{path}" unless pathname.exist?
        [
          pathname,
          retrieve_meta_data(path)
        ]
      end

      def destroy(relative_path)
        path = absolute(relative_path)
        FileUtils.rm path
        FileUtils.rm meta_data_path(path)
        purge_empty_directories(relative_path)
      rescue Errno::ENOENT => e
        raise DataNotFound, e.message
      end

      def disambiguate(path)
        dirname = File.dirname(path)
        basename = File.basename(path, '.*')
        extname = File.extname(path)
        "#{dirname}/#{basename}_#{(Time.now.usec*10 + rand(100)).to_s(32)}#{extname}"
      end

      private

      def absolute(relative_path)
        File.join(root_path, relative_path)
      end

      def relative(absolute_path)
        absolute_path[/^#{Regexp.escape root_path}\/?(.*)$/, 1]
      end

      def directory_empty?(path)
        Dir.entries(path) == ['.','..']
      end

      def meta_data_path(data_path)
        "#{data_path}.meta"
      end

      def relative_path_for(filename)
        time = Time.now
        msec = time.usec / 1000
        "#{time.strftime '%Y/%m/%d/%H_%M_%S'}_#{msec}_#{filename.gsub(/[^\w.]+/,'_')}"
      end

      def store_meta_data(data_path, meta)
        File.open(meta_data_path(data_path), 'wb') do |f|
          f.write Marshal.dump(meta)
        end
      end

      def retrieve_meta_data(data_path)
        path = meta_data_path(data_path)
        File.exist?(path) ?  File.open(path,'rb'){|f| Marshal.load(f.read) } : {}
      end

      def prepare_path(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless File.exist?(dir)
      end

      def purge_empty_directories(path)
        containing_directory = Pathname.new(path).dirname
        containing_directory.ascend do |relative_dir|
          dir = absolute(relative_dir)
          FileUtils.rmdir dir if directory_empty?(dir)
        end
      end

    end

  end
end
