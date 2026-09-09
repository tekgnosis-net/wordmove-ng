require 'spec_helper'

describe Wordmove::Deployer::SSH do
  let(:cli_options) do
    {
      config: movefile_path_for('multi_environments'),
      environment: 'staging'
    }
  end
  let(:copier) { double(:copier) }
  let(:runner) { instance_double(Wordmove::SshRunner) }
  subject(:deployer) { Wordmove::Deployer::Base.deployer_for(cli_options) }

  before do
    allow(copier).to receive(:logger=)
    allow(Photocopier::SSH).to receive(:new).and_return(copier)
    allow(Wordmove::SshRunner).to receive(:new).and_return(runner)
  end

  it "builds the runner from the movefile ssh options before Photocopier strips them" do
    deployer
    expect(Wordmove::SshRunner).to have_received(:new).with(
      hash_including(host: 'staging.mysite.example.com', user: 'user')
    )
  end

  context "#remote_run" do
    it "runs the command through the system ssh and returns true on success" do
      allow(runner).to receive(:run).with('ls').and_return(['', '', 0])
      silence_stream(STDOUT) { expect(deployer.send(:remote_run, 'ls')).to be true }
    end

    it "raises ShellCommandError with stderr on a non zero exit code" do
      allow(runner).to receive(:run).with('false').and_return(['', 'boom', 1])
      silence_stream(STDOUT) do
        expect { deployer.send(:remote_run, 'false') }
          .to raise_error(Wordmove::ShellCommandError, /Error code 1.*boom/)
      end
    end

    context "when simulating" do
      let(:cli_options) { super().merge(simulate: true) }

      it "does not run anything" do
        silence_stream(STDOUT) { expect(deployer.send(:remote_run, 'ls')).to be true }
      end
    end
  end

  context "#remote_get / #remote_put / #remote_delete" do
    it "downloads through scp" do
      allow(runner).to receive(:get).with('/r/dump.gz', '/l/dump.gz').and_return(['', '', 0])
      silence_stream(STDOUT) { deployer.send(:remote_get, '/r/dump.gz', '/l/dump.gz') }
      expect(runner).to have_received(:get)
    end

    it "uploads through scp" do
      allow(runner).to receive(:put).with('/l/dump.gz', '/r/dump.gz').and_return(['', '', 0])
      silence_stream(STDOUT) { deployer.send(:remote_put, '/l/dump.gz', '/r/dump.gz') }
      expect(runner).to have_received(:put)
    end

    it "deletes through ssh" do
      allow(runner).to receive(:delete).with('/r/dump.gz').and_return(['', '', 0])
      silence_stream(STDOUT) { deployer.send(:remote_delete, '/r/dump.gz') }
      expect(runner).to have_received(:delete)
    end

    it "raises ShellCommandError when a transfer fails" do
      allow(runner).to receive(:put).and_return(['', 'scp: No such file', 1])
      silence_stream(STDOUT) do
        expect { deployer.send(:remote_put, '/l/dump.gz', '/r/dump.gz') }
          .to raise_error(Wordmove::ShellCommandError, /No such file/)
      end
    end

    context "when simulating" do
      let(:cli_options) { super().merge(simulate: true) }

      it "skips transfers" do
        silence_stream(STDOUT) do
          expect(deployer.send(:remote_put, '/l/dump.gz', '/r/dump.gz')).to be true
        end
      end
    end
  end

  context "#remote_wp_in_path!" do
    it "passes silently when wp is available on the remote" do
      allow(runner).to receive(:run).with('command -v wp').and_return(['/usr/bin/wp', '', 0])
      silence_stream(STDOUT) { expect { deployer.send(:remote_wp_in_path!) }.not_to raise_error }
    end

    it "raises UnmetPeerDependencyError naming the environment when wp is missing" do
      allow(runner).to receive(:run).with('command -v wp').and_return(['', '', 1])
      silence_stream(STDOUT) do
        expect { deployer.send(:remote_wp_in_path!) }
          .to raise_error(Wordmove::UnmetPeerDependencyError, /staging/)
      end
    end
  end
end
