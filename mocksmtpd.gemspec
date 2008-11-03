Gem::Specification.new do |s|
  s.name = %q{mocksmtpd}
  s.version = "0.0.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["KOSEKI Kengo"]
  s.date = %q{2008-11-04}
  s.default_executable = %q{mocksmtpd}
  s.description = %q{Mock SMTP server for development/testing.}
  s.email = %q{koseki@gmail.com}
  s.executables = ["mocksmtpd"]
  s.extra_rdoc_files = ["README", "ChangeLog"]
  s.files = ["README", "ChangeLog", "Rakefile", "bin/mocksmtpd", "test/mocksmtpd_test.rb", "test/test_helper.rb", "lib/mocksmtpd-old.rb", "lib/mocksmtpd-old.rb~", "lib/mocksmtpd.rb", "lib/mocksmtpd.rb~", "lib/smtpserver.rb", "templates/html", "templates/html/index.erb", "templates/html/index.erb~", "templates/html/index_entry.erb", "templates/html/index_entry.erb~", "templates/html/mail.erb", "templates/html/mail.html.erb~", "templates/mocksmtpd.conf.erb"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/koseki/mocksmtpd/}
  s.rdoc_options = ["--title", "mocksmtpd documentation", "--charset", "utf-8", "--opname", "index.html", "--line-numbers", "--main", "README", "--inline-source", "--exclude", "^(examples|extras)/"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{mocksmtpd}
  s.rubygems_version = %q{1.2.0}
  s.summary = %q{Mock SMTP server for development/testing.}
  s.test_files = ["test/mocksmtpd_test.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if current_version >= 3 then
    else
    end
  else
  end
end
