require 'ruby-prof'

RSpec.configure do |config|
  config.around(:each) do |example|
    profile = RubyProf::Profile.new
    profile.start
    example.run
    result = profile.stop

    printer = RubyProf::FlatPrinter.new(result)
    printer.print(File.open("profile_#{example.full_description.parameterize}.txt", 'w+'))
  end
end