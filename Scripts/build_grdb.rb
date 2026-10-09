require_relative 'tools'

module GRDBArtifact
  module_function
  ROOT = File.expand_path('..', __dir__)
  def config
    JSON.parse(File.read(File.join(ROOT, 'GRDBDistribution.json')))
  end
  def fingerprint(environment)
    data = config.reject { |key, _| %w[repository library_version].include?(key) }
    Digest::SHA256.hexdigest(JSON.generate(data) + JSON.generate(environment) + File.binread(__FILE__) + File.binread(File.join(__dir__, 'tools.rb')))
  end
  def prepare
    data = config
    environment = Tools.environment
    input = fingerprint(environment)
    directory = File.join(ROOT, '.distribution', 'grdb', input)
    archive = File.join(directory, 'GRDB.xcframework.zip')
    lock_path = File.join(ROOT, 'GRDBArtifact.lock.json')
    if File.file?(lock_path)
      lock = JSON.parse(File.read(lock_path))
      if lock['input_fingerprint'] == input
        if !File.file?(archive) || Digest::SHA256.file(archive).hexdigest != lock.fetch('checksum')
          FileUtils.mkdir_p(directory)
          Tools.capture('curl', '--fail', '--location', '--retry', '2', lock.fetch('url'), '--output', archive + '.tmp')
          raise 'GRDB checksum mismatch' unless Digest::SHA256.file(archive + '.tmp').hexdigest == lock.fetch('checksum')
          File.rename(archive + '.tmp', archive)
        end
        Tools.capture('ditto', '-x', '-k', archive, directory) unless File.directory?(File.join(directory, 'GRDB.xcframework'))
        return [lock, archive]
      end
    end
    FileUtils.mkdir_p(directory)
    source = File.join(directory, 'source')
    unless File.directory?(File.join(source, '.git'))
      cached = File.join(ROOT, '.build/checkouts/GRDB.swift')
      if File.directory?(File.join(cached, '.git')) && Tools.capture('git', '-C', cached, 'rev-parse', 'HEAD') == data.fetch('revision')
        Tools.capture('git', 'clone', '--no-hardlinks', '--no-checkout', cached, source)
        Tools.capture('git', '-C', source, 'remote', 'set-url', 'origin', data.fetch('source'))
      else
        Tools.capture('git', 'clone', '--depth', '1', '--branch', "v#{data.fetch('version')}", '--no-checkout', data.fetch('source'), source)
      end
    end
    Tools.capture('git', '-C', source, 'checkout', '--detach', data.fetch('revision'))
    raise 'GRDB source revision mismatch' unless Tools.capture('git', '-C', source, 'rev-parse', 'HEAD') == data.fetch('revision')
    frameworks = data.fetch('platforms').map do |platform|
      path = File.join(directory, platform.fetch('name') + '.xcarchive')
      command = ['xcodebuild', 'archive', '-project', 'GRDB.xcodeproj', '-scheme', 'GRDB', '-configuration', 'Release',
                 '-destination', platform.fetch('destination'), '-archivePath', path, 'SKIP_INSTALL=NO',
                 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES', 'CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=NO']
      command += platform.fetch('settings').map { |key, value| "#{key}=#{value}" }
      Tools.run(command, directory: source, log: File.join(directory, platform.fetch('name') + '.log'))
      framework = File.join(path, 'Products/Library/Frameworks/GRDB.framework')
      raise 'Missing GRDB framework/privacy manifest' unless File.file?(File.join(framework, 'GRDB')) && !Dir.glob(File.join(framework, '**/PrivacyInfo.xcprivacy')).empty?
      interfaces = Dir.glob(File.join(framework, '**/*.swiftinterface'))
      raise 'Missing stable Swift interfaces' if interfaces.empty?
      raise 'Undistributed GRDBSQLite module' if interfaces.any? { |file| File.read(file).match?(/^import GRDBSQLite$/) }
      linked = Tools.capture('otool', '-L', File.join(framework, 'GRDB'))
      raise 'Non-portable framework dependency' if linked.lines.any? { |line| line.start_with?("\t") && !line.strip.start_with?('@rpath/GRDB.framework/', '/usr/lib/', '/System/Library/', '@rpath/libswift') }
      framework
    end
    output = File.join(directory, 'GRDB.xcframework')
    FileUtils.rm_rf(output)
    command = ['xcodebuild', '-create-xcframework'] + frameworks.flat_map { |framework| ['-framework', framework] } + ['-output', output]
    Tools.run(command, directory: source, log: File.join(directory, 'create-xcframework.log'))
    license = File.join(ROOT, 'ThirdPartyNotices/GRDB-LICENSE.txt')
    FileUtils.cp(File.join(source, 'LICENSE'), license)
    FileUtils.cp(license, File.join(output, 'LICENSE.txt'))
    FileUtils.rm_f(archive)
    Tools.capture('ditto', '-c', '-k', '--keepParent', output, archive + '.tmp')
    File.rename(archive + '.tmp', archive)
    checksum = Tools.capture('xcrun', 'swift', 'package', 'compute-checksum', archive)
    tag = "grdb-#{data.fetch('version')}-#{input}"
    lock = { 'version' => data.fetch('version'), 'revision' => data.fetch('revision'), 'input_fingerprint' => input,
             'checksum' => checksum, 'release_tag' => tag, 'environment' => environment,
             'url' => "https://github.com/#{data.fetch('repository')}/releases/download/#{tag}/GRDB.xcframework.zip" }
    File.write(lock_path, JSON.pretty_generate(lock) + "\n")
    [lock, archive]
  end
end

GRDBArtifact.prepare if $PROGRAM_NAME == __FILE__
