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
    allow(Wordmove::Prerequisites).to receive(:missing_locally).and_return([])
    allow(Wordmove::Prerequisites).to receive(:missing_remotely) do |r, reqs|
      calls << [:remote_probe, reqs]
      []
    end
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

    it "probes the remote for the target prerequisites before touching any database" do
      silence_stream(STDOUT) { deployer.send(:push_db) }
      expect(calls.first).to eq([:remote_probe, Wordmove::Prerequisites::DB_TARGET])
    end

    it "aborts without side effects when wp-cli is missing on the remote" do
      allow(Wordmove::Prerequisites).to receive(:missing_remotely).and_return([['wp']])
      silence_stream(STDOUT) do
        expect { deployer.send(:push_db) }
          .to raise_error(Wordmove::UnmetPeerDependencyError, /on "staging": wp/)
      end
      expect(local_commands).to be_empty
      expect(calls.map(&:first)).not_to include(:get, :put, :remote)
    end

    it "aborts when mysqldump is missing locally" do
      allow(Wordmove::Prerequisites).to receive(:missing_locally)
        .and_return([%w[mysqldump mariadb-dump]])
      silence_stream(STDOUT) do
        expect { deployer.send(:push_db) }
          .to raise_error(Wordmove::UnmetPeerDependencyError, /locally: mysqldump or mariadb-dump/)
      end
      expect(local_commands).to be_empty
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

    context "with prefix collisions between search terms" do
      let(:cli_options) { super().merge(config: movefile_path_for('with_prefix_collision')) }

      it "warns and continues" do
        # paths are movefile secrets, so the deployer logger masks them
        expect { deployer.send(:push_db) }
          .to output(/"\[secret\]" is a prefix of "\[secret\]-staging"/)
          .to_stdout_from_any_process
        expect(remote_commands.grep(/wp search-replace/).size).to eq(2)
      end
    end

    it "does not touch maintenance mode by default" do
      silence_stream(STDOUT) { deployer.send(:push_db) }
      expect(remote_commands.grep(/maintenance-mode/)).to be_empty
    end

    context "with global.maintenance_mode enabled" do
      let(:cli_options) { super().merge(config: movefile_path_for('with_maintenance_mode')) }
      let(:activate) { 'wp maintenance-mode activate --path=/var/www/your_site --allow-root' }
      let(:deactivate) { 'wp maintenance-mode deactivate --path=/var/www/your_site --allow-root' }

      it "wraps the remote import and search-replace in maintenance mode" do
        silence_stream(STDOUT) { deployer.send(:push_db) }
        import_index = remote_commands.index { |c| c.include?('--init-command') }
        replace_index = remote_commands.rindex { |c| c.start_with?('wp search-replace') }
        expect(remote_commands.index(activate)).to be < import_index
        expect(remote_commands.index(deactivate)).to be > replace_index
        expect(remote_commands.index(deactivate)).to eq(remote_commands.rindex(deactivate))
      end

      it "deactivates maintenance mode even when the adaptation fails" do
        allow(runner).to receive(:run) do |cmd|
          calls << [:remote, cmd]
          cmd.start_with?('wp search-replace') ? ['', 'Error: boom', 1] : ['', '', 0]
        end
        silence_stream(STDOUT) do
          expect { deployer.send(:push_db) }.to raise_error(Wordmove::ShellCommandError)
        end
        expect(remote_commands.last).to eq(deactivate)
      end
    end

    context "with WORDMOVE_MAINTENANCE_MODE=1 in the environment" do
      around do |example|
        previous = ENV['WORDMOVE_MAINTENANCE_MODE']
        ENV['WORDMOVE_MAINTENANCE_MODE'] = '1'
        example.run
      ensure
        ENV['WORDMOVE_MAINTENANCE_MODE'] = previous
      end

      it "enables maintenance mode without a movefile setting" do
        silence_stream(STDOUT) { deployer.send(:push_db) }
        expect(remote_commands.grep(/maintenance-mode activate/).size).to eq(1)
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
      allow(Wordmove::Prerequisites).to receive(:missing_locally).and_return([['wp']])
      silence_stream(STDOUT) do
        expect { deployer.send(:pull_db) }
          .to raise_error(Wordmove::UnmetPeerDependencyError, /locally: wp/)
      end
      expect(local_commands).to be_empty
      expect(remote_commands).to be_empty
    end

    it "probes the remote for the source prerequisites" do
      silence_stream(STDOUT) { deployer.send(:pull_db) }
      expect(calls.first).to eq([:remote_probe, Wordmove::Prerequisites::DB_SOURCE])
    end

    it "imports locally then adapts locally" do
      silence_stream(STDOUT) { deployer.send(:pull_db) }
      expect(local_commands.grep(/wp search-replace/).size).to eq(2)
      expect(remote_commands.grep(/wp search-replace/)).to be_empty
    end

    context "with global.maintenance_mode enabled" do
      let(:cli_options) { super().merge(config: movefile_path_for('with_maintenance_mode')) }

      it "wraps the local import and search-replace in maintenance mode on the local install" do
        silence_stream(STDOUT) { deployer.send(:pull_db) }
        activate = 'wp maintenance-mode activate --path=/home/welaika/sites/your_site --allow-root'
        deactivate = 'wp maintenance-mode deactivate --path=/home/welaika/sites/your_site ' \
                     '--allow-root'
        import_index = local_commands.index { |c| c.include?('--init-command') }
        expect(local_commands.index(activate)).to be < import_index
        expect(local_commands.last).to eq(deactivate)
        expect(remote_commands.grep(/maintenance-mode/)).to be_empty
      end
    end
  end
end
