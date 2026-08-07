#!/usr/bin/env ruby
# frozen_string_literal: true

# Independent, read-only Ruby attestation of the dense German-bigram receipt.
# This implementation consumes only the counted fixture and frozen P1030684
# plaintext. It deliberately does not load HELUT, Swift output, or Python output.

require "digest"
require "json"

ALPHABET_WIDTH = 26
SMOOTHING_MASS = 0.5
FIXTURE_DIGEST = "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
LETTER_TOTAL = 28_508_834
OBSERVED_TOTAL = 674
ABSENT_GRAMS = ["JX", "QY"].freeze
PLAINTEXT_DIGEST = "e355b691e78cd71bc1ed816e0808ab4f18aeb73376008b2a71dced197ad07145"
P1030684_PLAINTEXT = [
  "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY",
  "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
].join.freeze

class ReceiptFailure < StandardError; end

def assert_receipt(condition, message)
  raise ReceiptFailure, message unless condition
end

def numeric_double_bits(number)
  [number].pack("G").unpack("Q>").fetch(0)
end

def parse_counted_fixture(filename)
  bytes = File.binread(filename)
  actual_digest = Digest::SHA256.hexdigest(bytes)
  assert_receipt(
    actual_digest == FIXTURE_DIGEST,
    "fixture SHA-256 changed: expected #{FIXTURE_DIGEST}, got #{actual_digest}"
  )

  source = bytes.dup.force_encoding(Encoding::US_ASCII)
  assert_receipt(source.valid_encoding?, "fixture is not strict ASCII")
  records = source.lines.map(&:chomp)
  assert_receipt(!records.empty?, "fixture is empty")

  metadata = /\A# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)\z/.match(records.shift)
  assert_receipt(!metadata.nil?, "fixture metadata header is malformed")
  letters = Integer(metadata[1], 10)
  ic_string = metadata[2]
  declared_entries = Integer(metadata[3], 10)

  by_gram = {}
  encountered_order = []
  records.each_with_index do |record, offset|
    parsed = /\A([A-Z]{2}) ([0-9]+)\z/.match(record)
    assert_receipt(!parsed.nil?, "malformed fixture line #{offset + 2}: #{record.inspect}")
    gram = parsed[1]
    assert_receipt(!by_gram.key?(gram), "duplicate gram #{gram} at fixture line #{offset + 2}")
    count = Integer(parsed[2], 10)
    assert_receipt(count.positive?, "non-positive observed count for #{gram}")
    assert_receipt(count <= 0xffff_ffff, "count for #{gram} exceeds Swift UInt32")
    by_gram[gram] = count
    encountered_order << gram
  end

  assert_receipt(encountered_order == encountered_order.sort, "fixture entries are not lexical")
  assert_receipt(letters == LETTER_TOTAL, "unexpected letters metadata: #{letters}")
  assert_receipt(declared_entries == OBSERVED_TOTAL, "unexpected distinct metadata: #{declared_entries}")
  assert_receipt(by_gram.length == declared_entries, "declared and parsed entry counts differ")

  universe = []
  ALPHABET_WIDTH.times do |first|
    ALPHABET_WIDTH.times do |second|
      universe << (65 + first).chr + (65 + second).chr
    end
  end
  absent = universe.reject { |gram| by_gram.key?(gram) }
  assert_receipt(absent == ABSENT_GRAMS, "unexpected missing grams: #{absent.inspect}")

  pair_total = 0
  by_gram.each_value { |count| pair_total += count }
  assert_receipt(pair_total == letters - 1, "pair total is not letters - 1")

  cells = Array.new(ALPHABET_WIDTH * ALPHABET_WIDTH, 0)
  by_gram.each do |gram, count|
    row = gram.getbyte(0) - 65
    column = gram.getbyte(1) - 65
    cells[row * ALPHABET_WIDTH + column] = count
  end

  details = {
    "sha256" => actual_digest,
    "letters" => letters,
    "ic" => ic_string,
    "declared_distinct" => declared_entries,
    "parsed_distinct" => by_gram.length,
    "counted_pairs" => pair_total,
    "missing" => absent
  }
  [cells, details]
end

def conditional_logs(cells)
  probabilities = Array.new(cells.length, 0.0)
  row = 0
  while row < ALPHABET_WIDTH
    offset = row * ALPHABET_WIDTH
    row_count = 0
    column = 0
    while column < ALPHABET_WIDTH
      row_count += cells[offset + column]
      column += 1
    end

    denominator = row_count.to_f + SMOOTHING_MASS * ALPHABET_WIDTH.to_f
    column = 0
    while column < ALPHABET_WIDTH
      numerator = cells[offset + column].to_f + SMOOTHING_MASS
      probabilities[offset + column] = Math.log(numerator / denominator)
      column += 1
    end
    row += 1
  end
  probabilities
end

def fold_control(cells, probabilities)
  digest = Digest::SHA256.hexdigest(P1030684_PLAINTEXT)
  assert_receipt(digest == PLAINTEXT_DIGEST, "control plaintext digest changed: #{digest}")
  assert_receipt(P1030684_PLAINTEXT.bytesize == 120, "control plaintext is not 120 symbols")

  total = 0.0
  floor_starts = []
  first_index = nil
  last_index = nil
  cursor = 0
  while cursor < P1030684_PLAINTEXT.bytesize - 1
    left = P1030684_PLAINTEXT.getbyte(cursor) - 65
    right = P1030684_PLAINTEXT.getbyte(cursor + 1) - 65
    assert_receipt(left.between?(0, 25) && right.between?(0, 25), "control contains non-A-Z data")
    index = left * ALPHABET_WIDTH + right
    first_index = index if first_index.nil?
    last_index = index
    floor_starts << cursor if cells[index].zero?
    total = total + probabilities[index]
    cursor += 1
  end

  assert_receipt(cursor == 119, "control did not produce 119 windows")
  mean = total / cursor.to_f
  control = {
    "plaintext_sha256" => digest,
    "symbols" => P1030684_PLAINTEXT.bytesize,
    "windows" => cursor,
    "first_index" => first_index,
    "last_index" => last_index,
    "floor_window_starts" => floor_starts
  }
  [control, total, mean]
end

def run_audit
  raise ReceiptFailure, "usage: #{File.basename($PROGRAM_NAME)} [fixture]" if ARGV.length > 1
  default_fixture = File.expand_path("../Fixtures/german_bigrams.txt", __dir__)
  fixture_name = File.expand_path(ARGV.fetch(0, default_fixture))

  cells, fixture = parse_counted_fixture(fixture_name)
  control, total, mean = fold_control(cells, conditional_logs(cells))
  total_bits = numeric_double_bits(total)
  mean_bits = numeric_double_bits(mean)

  {
    "schema" => "helut.dense-bigram-audit.v1",
    "implementation" => "ruby-independent-v1",
    "runtime" => {
      "ruby" => RUBY_DESCRIPTION,
      "platform" => RUBY_PLATFORM
    },
    "fixture" => fixture,
    "control" => control,
    "scoring" => {
      "layout" => "row-major A-Z conditional bigrams",
      "add_k" => SMOOTHING_MASS,
      "logarithm" => "natural",
      "accumulation" => "explicit left fold from +0.0",
      "mean_denominator" => control.fetch("windows")
    },
    "result" => {
      "total_decimal" => format("%.17g", total),
      "mean_decimal" => format("%.17g", mean),
      "total_bit_pattern" => format("0x%016x", total_bits),
      "mean_bit_pattern" => format("0x%016x", mean_bits)
    }
  }
end

begin
  puts JSON.pretty_generate(run_audit)
rescue ReceiptFailure, SystemCallError => error
  warn "dense-bigram audit failed: #{error.message}"
  exit 1
end
