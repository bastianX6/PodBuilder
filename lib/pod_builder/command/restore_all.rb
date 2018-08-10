require 'pod_builder/core'

module PodBuilder
  module Command
    class RestoreAll
      def self.call(options)
        Configuration.check_inited
        PodBuilder::prepare_basepath

        ret = false
        begin
          File.rename(PodBuilder::basepath("Podfile"), PodBuilder::basepath("Podfile.tmp2"))
          File.rename(PodBuilder::basepath("Podfile.restore"), PodBuilder::basepath("Podfile"))

          ARGV << "*"
          ret = Command::Build::call(options)
        rescue Exception => e
          raise e
        ensure
          FileUtils.rm_f(PodBuilder::basepath("Podfile.restore"))
          File.rename(PodBuilder::basepath("Podfile"), PodBuilder::basepath("Podfile.restore"))
          File.rename(PodBuilder::basepath("Podfile.tmp2"), PodBuilder::basepath("Podfile"))
        end

        return ret
      end
    end
  end
end