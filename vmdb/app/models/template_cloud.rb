class TemplateCloud < MiqTemplate
  SUBCLASSES = %w{
    TemplateAmazon
    TemplateOpenstack
  }

  default_value_for :cloud, true
end

# Preload any subclasses of this class, so that they will be part of the
#   conditions that are generated on queries against this class.
TemplateCloud::SUBCLASSES.each { |c| require_dependency Rails.root.join("app", "models", "#{c.underscore}.rb").to_s }
