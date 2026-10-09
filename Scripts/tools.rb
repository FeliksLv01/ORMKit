require 'json'
require 'digest'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'time'

module Tools
  module_function
  def capture(*command)
    output, error, status = Open3.capture3(*command)
    raise "Failed: #{command.join(' ')}\n#{error}" unless status.success?
    output.strip
  end
  def run(command, directory:, log:, diagnostic: nil)
    FileUtils.mkdir_p(File.dirname(log))
    pipeline = command.shelljoin + ' 2>&1 | tee ' + log.shellescape
    pipeline += ' | xcbeautify' if command.first == 'xcodebuild'
    success = system('/bin/bash', '-o', 'pipefail', '-c', pipeline, chdir: directory)
    if diagnostic
      raise "Expected compilation failure: #{log}" if success
      raise "Missing expected diagnostic: #{log}" unless File.read(log).include?(diagnostic)
    else
      raise "Failed: #{command.first}; see #{log}" unless success
    end
  end
  def environment
    { 'swift' => capture('xcrun', 'swift', '--version'),
      'xcode' => capture('/usr/libexec/PlistBuddy', '-c', 'Print :DTXcodeBuild', File.expand_path('../Info.plist', capture('xcode-select', '-p'))),
      'sdks' => %w[iphoneos iphonesimulator macosx appletvos appletvsimulator watchos watchsimulator].to_h { |sdk| [sdk, capture('xcrun', '--sdk', sdk, '--show-sdk-version')] } }
  end
end
