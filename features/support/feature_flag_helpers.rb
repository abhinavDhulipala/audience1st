module FeatureFlagHelpers
	def enable_toggle(feature_name)
		Option.enable_feature!(feature_name)
	end
end

World(FeatureFlagHelpers)