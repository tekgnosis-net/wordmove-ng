require 'spec_helper'

describe Wordmove::CLI do
  let(:cli) { described_class.new }
  let(:deployer) { double("deployer") }
  let(:options) { {} }

  before do
    allow(Wordmove::Deployer::Base).to receive(:deployer_for).with(options).and_return(deployer)
  end

  context "#init" do
    it "delagates the command to the Movefile Generator" do
      expect(Wordmove::Generators::Movefile).to receive(:start)
      cli.invoke(:init, [], options)
    end
  end

  context "#doctor" do
    it "delagates the command to Doctor class" do
      expect(Wordmove::Doctor).to receive(:start)
      cli.invoke(:doctor, [], options)
    end

    context "without a movefile" do
      before do
        allow(Wordmove::Doctor).to receive(:start)
          .and_raise(Wordmove::MovefileNotFound, "Could not find a valid Movefile.")
      end

      it "rescues from a MovefileNotFound exception" do
        expect do
          expect { cli.invoke(:doctor, [], options) }.to raise_error(SystemExit)
        end.to output(/Could not find a valid Movefile\./).to_stdout_from_any_process
      end
    end

    context "with an invalid movefile" do
      before do
        allow(Wordmove::Doctor).to receive(:start)
          .and_raise(
            Psych::SyntaxError.new(
              nil,
              1,
              1,
              0,
              "found character that cannot start any token",
              nil
            )
          )
      end

      it "rescues from a syntax error" do
        expect do
          expect { cli.invoke(:doctor, [], options) }.to raise_error(SystemExit)
        end.to output(/Your movefile is not parsable due to a syntax error/).to_stdout_from_any_process
      end
    end
  end

  context "#pull" do
    context "without a movefile" do
      let(:options) { { wordpress: true } }

      before do
        allow(Wordmove::Deployer::Base).to receive(:deployer_for).with(options)
                                                                 .and_raise(Wordmove::MovefileNotFound, "Could not find a valid Movefile.")
      end

      it "it rescues from a MovefileNotFound exception" do
        expect do
          expect { cli.invoke(:pull, [], options) }.to raise_error(SystemExit)
        end.to output(/Could not find a valid Movefile\./).to_stdout_from_any_process
      end
    end

    context "with an invalid movefile" do
      let(:options) { { wordpress: true } }

      before do
        allow(Wordmove::Deployer::Base).to receive(:deployer_for).with(options).and_raise(
          Psych::SyntaxError.new(
            nil,
            1,
            1,
            0,
            "found character that cannot start any token",
            nil
          )
        )
      end

      it "rescues from a syntax error" do
        expect do
          expect { cli.invoke(:pull, [], options) }.to raise_error(SystemExit)
        end.to output(/Your movefile is not parsable due to a syntax error/).to_stdout_from_any_process
      end
    end
  end

  context "#list" do
    subject { cli.invoke(:list, []) }
    let(:list_class) { Wordmove::EnvironmentsList }
    # Werdmove::EnvironmentsList.print should be called
    it "delagates the command to EnvironmentsList class" do
      expect(list_class).to receive(:print)
      subject
    end

    context 'without a valid movefile' do
      context "no movefile" do
        it { expect { subject }.to raise_error SystemExit }
      end

      context "syntax error movefile " do
        before do
          # Ref. https://github.com/ruby/psych/blob/master/lib/psych/syntax_error.rb#L8
          # Arguments for initialization: file, line, col, offset, problem, context
          args = [nil, 1, 5, 0,
                  "found character that cannot start any token",
                  "while scanning for the next token"]
          allow(list_class).to receive(:print).and_raise(Psych::SyntaxError.new(*args))
        end

        it { expect { subject }.to raise_error SystemExit }
      end
    end

    context "with a movefile" do
      subject { cli.invoke(:list, [], options) }
      let(:options) { { config: movefile_path_for('Movefile') } }
      it "invoke list without error" do
        expect { subject }.not_to raise_error
      end
    end
  end

  context "#push" do
    context "without a movefile" do
      let(:options) { { wordpress: true } }

      before do
        allow(Wordmove::Deployer::Base).to receive(:deployer_for).with(options)
                                                                 .and_raise(Wordmove::MovefileNotFound, "Could not find a valid Movefile.")
      end

      it "it rescues from a MovefileNotFound exception" do
        expect do
          expect { cli.invoke(:push, [], options) }.to raise_error(SystemExit)
        end.to output(/Could not find a valid Movefile\./).to_stdout_from_any_process
      end
    end

    context "with an invalid movefile" do
      let(:options) { { wordpress: true } }

      before do
        allow(Wordmove::Deployer::Base).to receive(:deployer_for).with(options).and_raise(
          Psych::SyntaxError.new(
            nil,
            1,
            1,
            0,
            "found character that cannot start any token",
            nil
          )
        )
      end

      it "rescues from a syntax error" do
        expect do
          expect { cli.invoke(:push, [], options) }.to raise_error(SystemExit)
        end.to output(/Your movefile is not parsable due to a syntax error/).to_stdout_from_any_process
      end
    end
  end

  context "--all" do
    let(:options) { { all: true, config: movefile_path_for('Movefile') } }
    let(:ordered_components) { %i[wordpress uploads themes plugins mu_plugins languages db] }

    context "#pull" do
      it "invokes commands in the right order" do
        ordered_components.each do |component|
          expect(deployer).to receive("pull_#{component}")
        end
        cli.invoke(:pull, [], options)
      end

      context "with forbidden task" do
        let(:options) { { all: true, config: movefile_path_for('with_forbidden_tasks') } }

        it "does not pull the forbidden task" do
          expected_components = ordered_components - [:db]

          expected_components.each do |component|
            expect(deployer).to receive("pull_#{component}")
          end
          expect(deployer).to_not receive("pull_db")

          silence_stream(STDOUT) { cli.invoke(:pull, [], options) }
        end
      end
    end

    context "#push" do
      it "invokes commands in the right order" do
        ordered_components.each do |component|
          expect(deployer).to receive("push_#{component}")
        end
        cli.invoke(:push, [], options)
      end

      context "with forbidden task" do
        let(:options) { { all: true, config: movefile_path_for('with_forbidden_tasks') } }

        it "does not push the forbidden task" do
          expected_components = ordered_components - [:db]

          expected_components.each do |component|
            expect(deployer).to receive("push_#{component}")
          end
          expect(deployer).to_not receive("push_db")

          silence_stream(STDOUT) { cli.invoke(:push, [], options) }
        end
      end
    end

    context "excluding one of the components" do
      it "does not invoke the escluded component" do
        excluded_component = ordered_components.pop
        options[excluded_component] = false

        ordered_components.each do |component|
          expect(deployer).to receive("push_#{component}")
        end
        expect(deployer).to_not receive("push_#{excluded_component}")

        cli.invoke(:push, [], options)
      end
    end
  end
end

describe Wordmove::CLI, "#auto" do
  let(:cli) { described_class.new }
  let(:options) { { "themes" => true, "db" => true, "environment" => "staging" } }
  let(:planner) { instance_double(Wordmove::AutoPlanner, warnings: [], environment: :staging) }
  let(:deployer) { double("deployer") }
  let(:row) { Wordmove::AutoPlanner::Row }

  before do
    allow(Wordmove::AutoPlanner).to receive(:new).and_return(planner)
    allow(Wordmove::Deployer::Base).to receive(:deployer_for).and_return(deployer)
    allow(Wordmove::Hook).to receive(:run)
    guardian = instance_double(Wordmove::Guardian, allows: true)
    allow(Wordmove::Guardian).to receive(:new).and_return(guardian)
  end

  it "prints the plan and exits 3 without --apply when something is pending" do
    allow(planner).to receive(:plan).with(%w[themes db]).and_return(
      [row.new('themes', 1, 2, :push, 'local newer by 1s'), row.new('db', 1, 1, :skip, 'in sync')]
    )
    expect do
      expect { cli.invoke(:auto, [], options) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(3) }
    end.to output(/themes\s+PUSH[\s\S]*db\s+SKIP/).to_stdout_from_any_process
    expect(Wordmove::Deployer::Base).not_to have_received(:deployer_for)
  end

  it "exits 0 and changes nothing when everything is in sync" do
    allow(planner).to receive(:plan).and_return([row.new('themes', 1, 1, :skip, 'in sync')])
    expect { cli.invoke(:auto, [], options) }.to output(/Nothing to do/).to_stdout_from_any_process
    expect(Wordmove::Deployer::Base).not_to have_received(:deployer_for)
  end

  it "exits 1 and changes nothing when a probe failed, even with --apply" do
    allow(planner).to receive(:plan).and_return([row.new('themes', nil, nil, :error, 'remote probe failed')])
    expect do
      expect { cli.invoke(:auto, [], options.merge("apply" => true)) }
        .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end.to output(/could not be compared/).to_stdout_from_any_process
    expect(Wordmove::Deployer::Base).not_to have_received(:deployer_for)
  end

  it "dispatches pushes and pulls with hooks around each direction when --apply is given" do
    allow(planner).to receive(:plan).and_return(
      [
        row.new('themes', 2, 1, :push, 'local newer'),
        row.new('db', 1, 2, :pull, 'remote newer'),
        row.new('plugins', 1, 1, :skip, 'in sync')
      ]
    )
    calls = []
    allow(Wordmove::Hook).to receive(:run) { |action, step, _| calls << [action, step] }
    allow(deployer).to receive(:push_themes) { calls << :push_themes }
    allow(deployer).to receive(:pull_db) { calls << :pull_db }
    silence_stream(STDOUT) { cli.invoke(:auto, [], options.merge("apply" => true)) }
    expect(calls).to eq(
      [%i[push before], :push_themes, %i[push after], %i[pull before], :pull_db, %i[pull after]]
    )
  end

  it "reports clock skew as an error" do
    allow(planner).to receive(:plan).and_raise(Wordmove::AutoPlanner::ClockSkewError, "clock skew of 500s")
    expect do
      expect { cli.invoke(:auto, [], options) }.to raise_error(SystemExit)
    end.to output(/clock skew of 500s/).to_stdout_from_any_process
  end
end
