class VmInfra < Vm
  SUBCLASSES = %w{
    VmKvm
    VmMicrosoft
    VmRedhat
    VmVmware
    VmXen
  }

  default_value_for :cloud, false

  # Show certain non-generic charts
  def cpu_mhz_available?
    true
  end
  def memory_mb_available?
    true
  end

end

# Preload any subclasses of this class, so that they will be part of the
#   conditions that are generated on queries against this class.
VmInfra::SUBCLASSES.each { |c| require_dependency Rails.root.join("app", "models", "#{c.underscore}.rb").to_s }
