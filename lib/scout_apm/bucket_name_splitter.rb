module ScoutApm
  module BucketNameSplitter
    def bucket
      split_metric_name(metric_name).first
    end

    def name
      split_metric_name(metric_name).last
    end

    def key
      {:bucket => bucket, :name => name}
    end

    private
    def split_metric_name(name)
      name.to_s.split(/\//, 2)
    end

    def scope_hash
      if scope
        scope_bucket, scope_name = split_metric_name(scope)
        {:bucket => scope_bucket, :name => scope_name}
      end
    end
  end
end
