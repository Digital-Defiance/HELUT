#!/usr/bin/env ruby
# frozen_string_literal: true

# Independent Ruby reconstruction of LanguageScorer's dense calibration v2.
# It neither invokes nor imports the Python calibration implementation.

require "digest"
require "json"

WIDTH = 26
K = 0.5
SAMPLE_SIZE = 72
SAMPLE_QUANTITY = 400
STREAM_DOMAIN = "HELUT dense bigram calibration v2".b.freeze
DENSE_SHA = "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
CONTROL_SHA = "e355b691e78cd71bc1ed816e0808ab4f18aeb73376008b2a71dced197ad07145"
CONTROL = [
  "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY",
  "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
].join.freeze

class CalibrationFailure < StandardError; end

def check(condition, message)
  raise CalibrationFailure, message unless condition
end

def bits(value)
  format("0x%016x", [value].pack("G").unpack("Q>").fetch(0))
end

def fixture_counts(path)
  data = File.binread(path)
  digest = Digest::SHA256.hexdigest(data)
  check(digest == DENSE_SHA, "dense fixture SHA-256 changed: #{digest}")
  ascii = data.dup.force_encoding(Encoding::US_ASCII)
  check(ascii.valid_encoding?, "dense fixture is not ASCII")
  rows = ascii.lines.map(&:chomp)
  metadata = /\A# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)\z/.match(rows.shift)
  check(!metadata.nil?, "malformed dense fixture header")
  letters = Integer(metadata[1], 10)
  corpus_ic = Float(metadata[2])
  declared = Integer(metadata[3], 10)
  check(letters == 28_508_834 && declared == 674, "unexpected dense fixture metadata")

  counts = Array.new(WIDTH) { Array.new(WIDTH, 0) }
  grams = {}
  pair_total = 0
  rows.each_with_index do |line, offset|
    record = /\A([A-Z]{2}) ([0-9]+)\z/.match(line)
    check(!record.nil?, "malformed dense fixture line #{offset + 2}")
    gram = record[1]
    check(!grams.key?(gram), "duplicate dense gram #{gram}")
    count = Integer(record[2], 10)
    check(count.positive?, "non-positive dense count for #{gram}")
    grams[gram] = count
    counts[gram.getbyte(0) - 65][gram.getbyte(1) - 65] = count
    pair_total += count
  end
  check(grams.length == declared, "dense parsed/declared entry count mismatch")
  check(pair_total == letters - 1, "dense pair total is not letters - 1")

  missing = []
  WIDTH.times do |left|
    WIDTH.times do |right|
      gram = (65 + left).chr + (65 + right).chr
      missing << gram unless grams.key?(gram)
    end
  end
  check(missing == ["JX", "QY"], "dense missing-cell set changed")
  [counts, corpus_ic, digest]
end

def probabilities_for(counts)
  table = Array.new(WIDTH) { Array.new(WIDTH, 0.0) }
  row = 0
  while row < WIDTH
    row_total = 0
    column = 0
    while column < WIDTH
      row_total += counts[row][column]
      column += 1
    end
    denominator = row_total.to_f + K * WIDTH.to_f
    column = 0
    while column < WIDTH
      table[row][column] = Math.log((counts[row][column].to_f + K) / denominator)
      column += 1
    end
    row += 1
  end
  table
end

def score_sequence(sequence, table)
  return -10.0 if sequence.length < 2
  total = 0.0
  cursor = 0
  while cursor < sequence.length - 1
    total = total + table[sequence[cursor]][sequence[cursor + 1]]
    cursor += 1
  end
  total / (sequence.length - 1).to_f
end

def coincidence(sequence)
  return 0.0 if sequence.length < 2
  frequencies = Array.new(WIDTH, 0)
  sequence.each { |symbol| frequencies[symbol] += 1 }
  numerator = 0
  frequencies.each { |frequency| numerator += frequency * (frequency - 1) }
  numerator.to_f / (sequence.length * (sequence.length - 1)).to_f
end

def deterministic_uniform_letters(sample_number)
  output = []
  block_number = 0
  while output.length < SAMPLE_SIZE
    material = STREAM_DOMAIN + "\x00".b + [sample_number, block_number].pack("N2")
    Digest::SHA256.digest(material).bytes.each do |byte|
      next unless byte < 234
      output << byte % WIDTH
      break if output.length == SAMPLE_SIZE
    end
    block_number += 1
  end
  output
end

def as_letters(symbols)
  symbols.map { |symbol| symbol + 65 }.pack("C*")
end

def produce_receipt
  check(ARGV.empty?, "usage: #{File.basename($PROGRAM_NAME)}")
  fixture = File.expand_path("../Fixtures/german_bigrams.txt", __dir__)
  counts, corpus_ic, fixture_sha = fixture_counts(fixture)
  check(Digest::SHA256.hexdigest(CONTROL) == CONTROL_SHA, "control plaintext digest changed")
  reference = CONTROL.bytes.first(SAMPLE_SIZE).map { |byte| byte - 65 }
  check(reference.length == SAMPLE_SIZE && reference.all? { |value| value.between?(0, 25) },
        "German reference is not exactly 72 A-Z symbols")

  table = probabilities_for(counts)
  german_score = score_sequence(reference, table)
  generated = []
  scores = []
  SAMPLE_QUANTITY.times do |sample_number|
    sample = deterministic_uniform_letters(sample_number)
    generated << sample
    scores << score_sequence(sample, table)
  end

  random_mean = 0.0
  scores.each { |value| random_mean = random_mean + value }
  random_mean /= scores.length.to_f
  square_sum = 0.0
  scores.each do |value|
    delta = value - random_mean
    square_sum = square_sum + delta * delta
  end
  deviation = Math.sqrt(square_sum / scores.length.to_f)
  corpus_bytes = generated.map { |sample| as_letters(sample) }.join("\n") + "\n"

  {
    "schema" => "helut.bigram-calibration.v2",
    "implementation" => "ruby-independent-v2",
    "runtime" => {"ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM},
    "model" => {
      "source" => "bigrams",
      "source_sha256" => fixture_sha,
      "add_k" => K,
      "corpus_ic" => corpus_ic
    },
    "german_reference" => {
      "definition" => "first 72 symbols of ControlMessageP1030684 plaintext",
      "symbols" => reference.length,
      "sha256" => Digest::SHA256.hexdigest(as_letters(reference)),
      "score_decimal" => format("%.17g", german_score),
      "score_bit_pattern" => bits(german_score),
      "ic_decimal" => format("%.17g", coincidence(reference))
    },
    "random_reference" => {
      "generator" => "SHA-256(domain || 0x00 || sample-u32be || block-u32be), reject bytes >= 234, byte mod 26",
      "domain_hex" => STREAM_DOMAIN.unpack("H*").fetch(0),
      "samples" => SAMPLE_QUANTITY,
      "symbols_per_sample" => SAMPLE_SIZE,
      "first_sample_sha256" => Digest::SHA256.hexdigest(as_letters(generated.first)),
      "corpus_sha256" => Digest::SHA256.hexdigest(corpus_bytes),
      "mean_decimal" => format("%.17g", random_mean),
      "mean_bit_pattern" => bits(random_mean),
      "population_deviation_decimal" => format("%.17g", deviation),
      "population_deviation_bit_pattern" => bits(deviation)
    },
    "swift_constants" => {
      "germanMean" => german_score.round(6),
      "randomMean" => random_mean.round(6),
      "randomDeviation" => deviation.round(6),
      "germanIC" => corpus_ic.round(4)
    }
  }
end

begin
  puts JSON.pretty_generate(produce_receipt)
rescue CalibrationFailure, SystemCallError => error
  warn "calibration failed: #{error.message}"
  exit 1
end
