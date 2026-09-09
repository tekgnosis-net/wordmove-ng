describe Wordmove::Doctor::Ssh do
  let(:doctor) { described_class.new(movefile_path_for('multi_environments')) }
  let(:logger) { double("logger", task: nil, success: nil, error: nil) }
  let(:runner) { instance_double(Wordmove::SshRunner, ssh_argv: %w[ssh user@host]) }

  before do
    allow(logger).to receive(:level=)
    allow(Logger).to receive(:new).and_return(logger)
    allow(doctor).to receive(:system).with('which ssh', any_args).and_return(true)
    allow(Wordmove::SshRunner).to receive(:new).and_return(runner)
  end

  context ".new" do
    it "implements #check! method" do
      expect(doctor).to respond_to(:check!)
    end
  end

  context "#check!" do
    it "tests non interactive authentication against every ssh environment" do
      allow(runner).to receive(:run).with('true').and_return(['', '', 0])
      doctor.check!
      expect(Wordmove::SshRunner).to have_received(:new)
        .with(hash_including(host: 'staging.mysite.example.com')).once
      expect(logger).to have_received(:success)
        .with(/authentication to "staging" works/)
    end

    it "reports the failing command and stderr when authentication fails" do
      allow(runner).to receive(:run).with('true').and_return(['', 'Permission denied', 255])
      doctor.check!
      expect(logger).to have_received(:error).with(/Permission denied/)
      expect(logger).to have_received(:error).with(/ssh user@host true/)
    end

    it "skips remote checks when the ssh binary is missing" do
      allow(doctor).to receive(:system).with('which ssh', any_args).and_return(false)
      doctor.check!
      expect(Wordmove::SshRunner).not_to have_received(:new)
    end

    context "without a movefile" do
      let(:doctor) { described_class.new('does_not_exist', Dir.tmpdir) }

      it "only checks the ssh binary" do
        doctor.check!
        expect(Wordmove::SshRunner).not_to have_received(:new)
        expect(logger).to have_received(:success).with("SSH command found")
      end
    end
  end
end
