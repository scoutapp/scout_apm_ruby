# Queue/Critical (implicit count)
#   Job/PasswordResetJob Scope=Queue/Critical (implicit count, & total time)
#     JobMetric/Latency 10 Scope=Job/PasswordResetJob
#     ActiveRecord/User/find Scope=Job/PasswordResetJob
#     ActiveRecord/Message/find Scope=Job/PasswordResetJob
#     HTTP/request Scope=Job/PasswordResetJob
#     View/message/text Scope=Job/PasswordResetJob
#       ActiveRecord/Config/find Scope=View/message/text

module ScoutApm
  module LayerConverters
    class JobConverter < ConverterBase
      def call

      end
    end
  end
end
