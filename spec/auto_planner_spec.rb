require 'spec_helper'

describe Wordmove::AutoPlanner do
  let(:cli_options) { { config: movefile_path_for('multi_environments'), environment: 'staging' } }
  let(:runner) { instance_double(Wordmove::SshRunner) }
  let(:now) { 1_700_000_000 }
  let(:remote) { {} } # command fragment => stdout
  let(:local) { {} }
  let(:planner) { described_class.new(cli_options.deep_symbolize_keys) }

  before do
    allow(Wordmove::SshRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:run) do |cmd|
      key = remote.keys.find { |k| cmd.include?(k) }
      key ? [remote[key], '', 0] : ['', "no stub for #{cmd}", 1]
    end
    allow(planner).to receive(:local_shell) do |cmd|
      key = local.keys.find { |k| cmd.include?(k) }
      key ? [local[key], '', 0] : ['', "no stub for #{cmd}", 1]
    end
    allow(Time).to receive(:now).and_return(Time.at(now))
    local['date +%s'] = now.to_s
    remote['date +%s'] = now.to_s
  end

  def dir_stub(side, rel, epoch)
    side[rel] = epoch.to_s
  end

  context "#plan for directories" do
    it "pulls when the remote is newer by more than the window" do
      dir_stub(local, 'wp-content/themes', now - 10_000)
      dir_stub(remote, 'wp-content/themes', now - 100)
      row = planner.plan(%w[themes]).first
      expect(row.task).to eq('themes')
      expect(row.direction).to eq(:pull)
      expect(row.reason).to match(/remote newer/)
    end

    it "pushes when local is newer" do
      dir_stub(local, 'wp-content/plugins', now - 100)
      dir_stub(remote, 'wp-content/plugins', now - 10_000)
      expect(planner.plan(%w[plugins]).first.direction).to eq(:push)
    end

    it "skips when the difference is inside the window" do
      dir_stub(local, 'wp-content/uploads', now - 100)
      dir_stub(remote, 'wp-content/uploads', now - 200)
      row = planner.plan(%w[uploads]).first
      expect(row.direction).to eq(:skip)
      expect(row.reason).to match(/within 300s/)
    end

    context "with a custom window in the movefile" do
      let(:cli_options) do
        { config: movefile_path_for('with_auto_window'), environment: 'staging' }
      end

      it "treats differences inside that window as in sync" do
        dir_stub(local, 'wp-content/uploads', now - 100)
        dir_stub(remote, 'wp-content/uploads', now - 2000)
        expect(planner.plan(%w[uploads]).first.direction).to eq(:skip)
      end
    end

    it "honours WORDMOVE_AUTO_WINDOW over the movefile" do
      ENV['WORDMOVE_AUTO_WINDOW'] = '10'
      dir_stub(local, 'wp-content/uploads', now - 100)
      dir_stub(remote, 'wp-content/uploads', now - 200)
      expect(planner.plan(%w[uploads]).first.direction).to eq(:push)
    ensure
      ENV.delete('WORDMOVE_AUTO_WINDOW')
    end

    it "treats an empty or missing directory as having no content" do
      dir_stub(local, 'wp-content/languages', now - 100)
      remote['wp-content/languages'] = ''
      row = planner.plan(%w[languages]).first
      expect(row.direction).to eq(:push)
      expect(row.reason).to match(/remote empty/)
    end

    it "skips when both sides are empty" do
      local['wp-content/languages'] = ''
      remote['wp-content/languages'] = ''
      expect(planner.plan(%w[languages]).first.direction).to eq(:skip)
    end
  end

  context "#plan for the database" do
    it "uses the latest of posts and comments on each side" do
      local['wp db query'] = "2024-01-01 10:00:00\n2024-01-02 10:00:00\n"
      remote['wp db query'] = "2024-01-03 10:00:00\n2023-12-01 10:00:00\n"
      row = planner.plan(%w[db]).first
      expect(row.direction).to eq(:pull)
      expect(row.reason).to match(/remote newer/)
    end

    it "treats NULL results as no content" do
      local['wp db query'] = "NULL\nNULL\n"
      remote['wp db query'] = "2024-01-03 10:00:00\nNULL\n"
      expect(planner.plan(%w[db]).first.direction).to eq(:pull)
    end
  end

  context "#plan guard rails" do
    context "when the movefile forbids the chosen direction" do
      let(:cli_options) do
        { config: movefile_path_for('with_forbidden_tasks'), environment: 'remote' }
      end

      it "marks the row as blocked" do
        local['wp db query'] = "2024-01-02 10:00:00\nNULL\n"
        remote['wp db query'] = "2024-01-01 10:00:00\nNULL\n"
        row = planner.plan(%w[db]).first
        expect(row.direction).to eq(:blocked)
        expect(row.reason).to match(/forbid/)
      end
    end

    it "never decides the core directory" do
      row = planner.plan(%w[wordpress]).first
      expect(row.direction).to eq(:skip)
      expect(row.reason).to match(/core/)
    end

    it "marks a side as error when the probe fails" do
      dir_stub(local, 'wp-content/themes', now - 100)
      row = planner.plan(%w[themes]).first
      expect(row.direction).to eq(:error)
      expect(row.reason).to match(/remote probe failed/)
    end

    it "reports garbage from a probe as an error instead of interpreting it" do
      dir_stub(local, 'wp-content/themes', now - 100)
      remote['wp-content/themes'] = "rm -rf /; 12345"
      row = planner.plan(%w[themes]).first
      expect(row.direction).to eq(:error)
      expect(row.reason).to match(/unparseable output/)
    end

    it "reports a malformed database timestamp as an error" do
      local['wp db query'] = "2024-01-02 10:00:00\nNULL\n"
      remote['wp db query'] = "not a date\n"
      row = planner.plan(%w[db]).first
      expect(row.direction).to eq(:error)
    end

    it "raises when clock skew exceeds the maximum" do
      remote['date +%s'] = (now + 120).to_s
      expect { planner.plan(%w[themes]) }
        .to raise_error(Wordmove::AutoPlanner::ClockSkewError, /120s/)
    end

    it "warns but continues on moderate skew" do
      remote['date +%s'] = (now + 30).to_s
      dir_stub(local, 'wp-content/themes', now - 100)
      dir_stub(remote, 'wp-content/themes', now - 10_000)
      expect(planner.plan(%w[themes]).first.direction).to eq(:push)
      expect(planner.warnings).to include(a_string_matching(/skew of 30s/))
    end
  end

  context "#pending?" do
    it "is true when at least one row has a direction" do
      dir_stub(local, 'wp-content/themes', now - 100)
      dir_stub(remote, 'wp-content/themes', now - 10_000)
      rows = planner.plan(%w[themes])
      expect(described_class.pending?(rows)).to be true
    end

    it "is false when everything is skipped or blocked" do
      row = planner.plan(%w[wordpress])
      expect(described_class.pending?(row)).to be false
    end
  end
end
