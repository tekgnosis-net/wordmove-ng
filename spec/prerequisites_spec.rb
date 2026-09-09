require 'spec_helper'

describe Wordmove::Prerequisites do
  context ".probe_command" do
    it "tests each requirement and echoes the missing ones" do
      command = described_class.probe_command(['gzip', %w[mysql mariadb]])
      expect(command).to eq(
        "command -v gzip >/dev/null 2>&1 || echo gzip; " \
        "command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || echo mysql\\|mariadb"
      )
    end
  end

  context ".missing_locally" do
    it "returns an empty list when everything is present" do
      expect(described_class.missing_locally(['sh', %w[sh nosuchthing]])).to eq([])
    end

    it "returns the missing requirements, alternatives grouped" do
      missing = described_class.missing_locally(['definitely-not-a-binary', %w[nope-a nope-b]])
      expect(missing).to eq([['definitely-not-a-binary'], %w[nope-a nope-b]])
    end
  end

  context ".missing_remotely" do
    let(:runner) { instance_double(Wordmove::SshRunner) }

    it "parses the probe output from the remote" do
      allow(runner).to receive(:run).and_return(["wp\nmysqldump|mariadb-dump\n", '', 0])
      expect(described_class.missing_remotely(runner, described_class::DB_TARGET))
        .to eq([['wp'], %w[mysqldump mariadb-dump]])
    end

    it "raises ShellCommandError when the probe cannot run" do
      allow(runner).to receive(:run).and_return(['', 'Permission denied', 255])
      expect { described_class.missing_remotely(runner, ['gzip']) }
        .to raise_error(Wordmove::ShellCommandError, /Permission denied/)
    end
  end

  context ".describe" do
    it "renders alternatives readably" do
      expect(described_class.describe([['wp'], %w[mysql mariadb]])).to eq('wp, mysql or mariadb')
    end
  end
end
