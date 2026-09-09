describe Wordmove::Doctor::Wpcli do
  let(:movefile) { movefile_path_for('multi_environments') }
  subject(:doctor) { described_class.new(movefile) }
  let(:logger) { double("logger", task: nil, success: nil, error: nil) }
  let(:runner) { instance_double(Wordmove::SshRunner) }

  before do
    allow(logger).to receive(:level=)
    allow(Logger).to receive(:new).and_return(logger)
    allow(Wordmove::SshRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:run).with('command -v wp').and_return(['/usr/bin/wp', '', 0])
  end

  it "responds to #check!" do
    expect(doctor).to respond_to(:check!)
  end

  context "when wp-cli is installed and up to date" do
    before do
      allow(doctor).to receive(:in_path?).and_return(true)
      allow(doctor).to receive(:`)
        .with("wp cli check-update --format=json --allow-root")
        .and_return("")
    end

    it "checks updates using allow-root" do
      doctor.check!
      expect(logger).to have_received(:success).with("wp-cli is correctly installed")
      expect(logger).to have_received(:success).with("wp-cli is up to date")
    end

    it "checks wp-cli on every ssh remote" do
      doctor.check!
      expect(Wordmove::SshRunner).to have_received(:new)
        .with(hash_including(host: 'staging.mysite.example.com')).once
      expect(Wordmove::SshRunner).to have_received(:new)
        .with(hash_including(host: 'production.mysite.example.com')).once
      expect(logger).to have_received(:success).with(/available on "staging"/)
    end

    it "reports a missing remote wp-cli" do
      allow(runner).to receive(:run).with('command -v wp').and_return(['', '', 127])
      doctor.check!
      expect(logger).to have_received(:error).with(/not available on "staging"/)
    end
  end
end
