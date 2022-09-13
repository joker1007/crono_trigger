D = Steep::Diagnostic

target :lib do
  signature "sig"

  check "lib"
  ignore "lib/generators"
  ignore "lib/crono_trigger/web.rb"

  library "yaml"
  # collection_config "rbs_collection.yaml"

  # configure_code_diagnostics(D::Ruby.strict)       # `strict` diagnostics setting
  # configure_code_diagnostics(D::Ruby.lenient)      # `lenient` diagnostics setting
  configure_code_diagnostics do |hash|
    hash[D::Ruby::MethodDefinitionMissing] = :warning
    hash[D::Ruby::UnknownConstant] = :information
  end
end

target :test do
  # signature "sig", "sig-private"

  # check "spec"

  # library "pathname", "set"       # Standard libraries
end
