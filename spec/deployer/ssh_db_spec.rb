require 'spec_helper'

describe Wordmove::Deployer::SSH, 'database sync' do
  let(:cli_options) do
    {
      config: movefile_path_for('multi_environments'),
      environment: 'staging'
    }
  end
  let(:copier) { double(:copier) }
  let(:runner) { instance_double(Wordmove::SshRunner) }
  let(:calls) { [] }
  subject(:deployer) { Wordmove::Deployer::Base.deployer_for(cli_options) }

  before do
    allow(copier).to receive(:logger=)
    allow(Photocopier::SSH).to receive(:new).and_return(copier)
    allow(Wordmove::SshRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:run) { |cmd| calls << [:remote, cmd] && ['', '', 0] }
    allow(runner).to receive(:get) { |*args| calls << [:get, *args] && ['', '', 0] }
    allow(runner).to receive(:put) { |*args| calls << [:put, *args] && ['', '', 0] }
    allow(runner).to receive(:delete) { |*args| calls << [:delete, *args] && ['', '', 0] }
    allow(deployer).to receive(:system) { |cmd| calls << [:local, cmd] && true }
    allow(deployer).to receive(:local_delete) { |path| calls << [:local_delete, path] }
    allow(deployer).to receive(:normalize_collations!) { |path| calls << [:normalize, path] }
    allow(deployer).to receive(:wp_in_path?).and_return(true)
    allow_any_instance_of(Wordmove::SqlAdapter::Wpcli).to receive(:load_from_cli).and_return(nil)
    allow_any_instance_of(Wordmove::SqlAdapter::Wpcli).to receive(:wp_in_path?).and_return(true)
  end

  def remote_commands
    calls.select { |c| c.first == :remote }.map(&:last)
  end

  def local_commands
    calls.select { |c| c.first == :local }.map(&:last)
  end

  describe "#push_db" do
    it "never runs wp search-replace against the local database" do
      silence_stream(STDOUT) { deployer.send(:push_db) }
      expect(local_commands.grep(/wp search-replace/)).to be_empty
    end

    it "checks for wp-cli on the remote before touching any database" do
      silence_stream(STDOUT) { deployer.send(:push_db) }
      expect(remote_commands.first).to eq('command -v wp')
    end

    it "aborts without side effects when wp-cli is missing on the remote" do
      allow(runner).to receive(:run).with('command -v wp').and_return(['', '', 1])
      silence_stream(STDOUT) do
        expect { deployer.send(:push_db) }.to raise_error(Wordmove::UnmetPeerDependencyError)
      end
      expect(local_commands).to be_empty
      expect(calls.map(&:first)).not_to include(:get, :put)
    end

    it "backs up the remote, dumps local once, imports remotely, then adapts remotely" do
      silence_stream(STDOUT) { deployer.send(:push_db) }

      dumps = local_commands.grep(/mysqldump|mariadb-dump/)
      expect(dumps.size).to eq(1)

      expect(remote_commands.grep(/wp search-replace/)).to eq(
        [
          "wp search-replace --path=/var/www/your_site http://localhost:8080 " \
          "http://staging.mysite.example.com --quiet --skip-columns=guid --all-tables --allow-root",
          "wp search-replace --path=/var/www/your_site /home/welaika/sites/your_site " \
          "/var/www/your_site --quiet --skip-columns=guid --all-tables --allow-root"
        ]
      )

      order = calls.map(&:first)
      expect(order.index(:get)).to be < order.index(:put)
      import_index = remote_commands.index { |c| c.include?('--init-command') }
      replace_index = remote_commands.index { |c| c.start_with?('wp search-replace') }
      expect(import_index).to be < replace_index
    end

    it "normalizes collations exactly once" do
      silence_stream(STDOUT) { deployer.send(:push_db) }
      expect(calls.count { |c| c.first == :normalize }).to eq(1)
    end

    it "logs recovery instructions and re-raises when the remote search-replace fails" do
      allow(runner).to receive(:run) do |cmd|
        calls << [:remote, cmd]
        cmd.start_with?('wp search-replace') ? ['', 'Error: boom', 1] : ['', '', 0]
      end
      expect do
        expect { deployer.send(:push_db) }.to raise_error(Wordmove::ShellCommandError)
      end.to output(/backup.*staging-backup-\d+\.sql\.gz/m).to_stdout_from_any_process
    end

    context "with --no-adapt" do
      let(:cli_options) { super().merge(no_adapt: true) }

      it "skips the adaptation" do
        silence_stream(STDOUT) { deployer.send(:push_db) }
        expect(remote_commands.grep(/wp search-replace/)).to be_empty
      end
    end

    context "with --simulate" do
      let(:cli_options) { super().merge(simulate: true) }

      it "does nothing" do
        silence_stream(STDOUT) { deployer.send(:push_db) }
        expect(calls).to be_empty
      end
    end
  end

  describe "#pull_db" do
    it "checks for local wp-cli before touching any database" do
      allow(deployer).to receive(:wp_in_path?).and_return(false)
      silence_stream(STDOUT) do
        expect { deployer.send(:pull_db) }.to raise_error(Wordmove::UnmetPeerDependencyError)
      end
      expect(local_commands).to be_empty
      expect(remote_commands).to be_empty
    end

    it "imports locally then adapts locally" do
      silence_stream(STDOUT) { deployer.send(:pull_db) }
      expect(local_commands.grep(/wp search-replace/).size).to eq(2)
      expect(remote_commands.grep(/wp search-replace/)).to be_empty
    end
  end
end
