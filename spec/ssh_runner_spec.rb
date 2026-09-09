require 'spec_helper'

describe Wordmove::SshRunner do
  let(:ssh_options) { { host: 'staging.example.com', user: 'deploy' } }
  let(:runner) { described_class.new(ssh_options) }
  let(:success) { instance_double(Process::Status, exitstatus: 0) }

  before do
    allow(Open3).to receive(:capture3).and_return(['out', '', success])
  end

  context "#ssh_argv" do
    it "uses batch mode with key authentication when no password is configured" do
      expect(runner.ssh_argv).to eq(
        %w[ssh -o BatchMode=yes deploy@staging.example.com]
      )
    end

    it "omits the user when it is not configured" do
      runner = described_class.new(host: 'staging.example.com')
      expect(runner.ssh_argv).to eq(%w[ssh -o BatchMode=yes staging.example.com])
    end

    it "passes a custom port with -p" do
      runner = described_class.new(ssh_options.merge(port: 2222))
      expect(runner.ssh_argv).to eq(
        %w[ssh -o BatchMode=yes -p 2222 deploy@staging.example.com]
      )
    end

    it "wraps the command with sshpass when a password is configured" do
      runner = described_class.new(ssh_options.merge(password: 's3cret pass'))
      expect(runner.ssh_argv).to eq(
        ['sshpass', '-p', 's3cret pass', 'ssh', 'deploy@staging.example.com']
      )
    end

    it "adds a jump host when a gateway is configured" do
      runner = described_class.new(
        ssh_options.merge(gateway: { host: 'bastion.example.com', user: 'jump', port: 2200 })
      )
      expect(runner.ssh_argv).to eq(
        %w[ssh -o BatchMode=yes -J jump@bastion.example.com:2200 deploy@staging.example.com]
      )
    end
  end

  context "#run" do
    it "executes the command through ssh in a POSIX sh and returns stdout, stderr, exit code" do
      expect(runner.run('ls -la')).to eq(['out', '', 0])
      expect(Open3).to have_received(:capture3).with(
        'ssh', '-o', 'BatchMode=yes', 'deploy@staging.example.com', "sh -c 'ls -la'"
      )
    end

    it "quotes single quotes inside the command for the sh wrapper" do
      runner.run(%q(echo 'it''s' && printf "%s\n" "$HOME"))
      expect(Open3).to have_received(:capture3).with(
        'ssh', '-o', 'BatchMode=yes', 'deploy@staging.example.com',
        %q(sh -c 'echo '\''it'\'''\''s'\'' && printf "%s\n" "$HOME"')
      )
    end

    it "keeps multi-line scripts intact" do
      runner.run("a=1\necho $a")
      expect(Open3).to have_received(:capture3).with(
        'ssh', '-o', 'BatchMode=yes', 'deploy@staging.example.com', "sh -c 'a=1\necho $a'"
      )
    end

    it "returns a non zero exit code without raising" do
      failure = instance_double(Process::Status, exitstatus: 255)
      allow(Open3).to receive(:capture3).and_return(['', 'Permission denied (publickey).', failure])
      expect(runner.run('true')).to eq(['', 'Permission denied (publickey).', 255])
    end

    it "raises UnmetPeerDependencyError when the ssh binary is missing" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'ssh')
      expect { runner.run('true') }.to raise_error(
        Wordmove::UnmetPeerDependencyError, /ssh/
      )
    end

    it "names sshpass when it is missing and a password is configured" do
      runner = described_class.new(ssh_options.merge(password: 'pw'))
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'sshpass')
      expect { runner.run('true') }.to raise_error(
        Wordmove::UnmetPeerDependencyError, /sshpass/
      )
    end
  end

  context "#get" do
    it "downloads with scp using the same authentication options" do
      runner = described_class.new(ssh_options.merge(port: 2222))
      runner.get('/var/www/dump.sql.gz', '/tmp/dump.sql.gz')
      expect(Open3).to have_received(:capture3).with(
        'scp', '-q', '-o', 'BatchMode=yes', '-P', '2222',
        'deploy@staging.example.com:/var/www/dump.sql.gz', '/tmp/dump.sql.gz'
      )
    end
  end

  context "#put" do
    it "uploads with scp" do
      runner.put('/tmp/dump.sql.gz', '/var/www/dump.sql.gz')
      expect(Open3).to have_received(:capture3).with(
        'scp', '-q', '-o', 'BatchMode=yes',
        '/tmp/dump.sql.gz', 'deploy@staging.example.com:/var/www/dump.sql.gz'
      )
    end

    it "escapes remote paths with spaces for the remote shell" do
      runner.put('/tmp/dump.sql.gz', '/var/www/My Site/dump.sql.gz')
      expect(Open3).to have_received(:capture3).with(
        'scp', '-q', '-o', 'BatchMode=yes',
        '/tmp/dump.sql.gz', 'deploy@staging.example.com:/var/www/My\\ Site/dump.sql.gz'
      )
    end
  end

  context "#delete" do
    it "removes the remote path with an escaped rm" do
      runner.delete('/var/www/My Site/dump.sql')
      expect(Open3).to have_received(:capture3).with(
        'ssh', '-o', 'BatchMode=yes', 'deploy@staging.example.com',
        "sh -c 'rm -rf /var/www/My\\ Site/dump.sql'"
      )
    end
  end
end
