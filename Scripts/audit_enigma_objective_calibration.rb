#!/usr/bin/env ruby
# frozen_string_literal: true

# Independent Ruby calibration of HELUT's 72-symbol Enigma search objective.
# It neither invokes nor imports Swift or the independent Python implementation.

require "digest"
require "json"

WIDTH = 26
ADD_K = 0.5
SAMPLE_LENGTH = 72
SAMPLE_COUNT = 400
STREAM_DOMAIN = "HELUT dense bigram calibration v2".b.freeze
BIGRAM_SHA256 = "06f8694ec17906e993223e0179c6ca326030e62f77ec86e5c4120fddcf68f111"
TRIGRAM_SHA256 = "e08a56593d1e74b88d300e35b18dd504bc5fffef8ae03db51d72e6270e9509d7"
BIGRAM_MODEL_ID = "helut-german-bigram-add-k-0.5-06f8694e-v2"
TRIGRAM_MODEL_ID = "helut-german-trigram-add-k-0.5-e08a5659-v1"
OBJECTIVE_MODEL_ID = "helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v2"
CONTROL = [
  "VVVUUUVIRSOBENNULEINSXXMITUUUVIRSIBENNULZWOYVIRSIBENNULDREIY",
  "ZWODREISECHSEINSYZWODREIDREIACHTEINSDREIOITNACHWZSTENPASSIRT"
].join.freeze
DENSE_RECOVERED_NONSENSE =
  "LLLWOHLARGULATTUSZITSPAMIROOOLOSTIKETTOLZFFNLIKDIBAKRJLDNRITZAUDHEMZEKKS".freeze
ATTACK_CRIBS = %w[
  EINS ZWO DREI NULL VIER FUENF SECHS ACHT NEUN WETTER CHEF UBOOT MELDUNG MARINE
  QUADRAT KURS FEIND BOOT STANDORT ANGRIFF VONVON
].freeze
GERMAN_IC = 0.0747
IC_PENALTY_SCALE = 8.0
CRIB_BONUS = 0.05

class ObjectiveAuditFailure < StandardError; end

def check(condition, message)
  raise ObjectiveAuditFailure, message unless condition
end

def bits(value)
  format("0x%016x", [value].pack("G").unpack("Q>").fetch(0))
end

def rounded_six(value)
  format("%.6f", value).to_f
end

def parse_fixture(path, order, expected_sha, expected_entries)
  data = File.binread(path)
  digest = Digest::SHA256.hexdigest(data)
  check(digest == expected_sha, "#{File.basename(path)} SHA-256 changed: #{digest}")
  ascii = data.dup.force_encoding(Encoding::US_ASCII)
  check(ascii.valid_encoding?, "#{File.basename(path)} is not ASCII")
  lines = ascii.lines.map(&:chomp)
  header = /\A# letters=(\d+) ic=([0-9]+(?:\.[0-9]+)?) distinct=(\d+)\z/.match(lines.shift)
  check(!header.nil?, "malformed #{File.basename(path)} header")
  letters = Integer(header[1], 10)
  corpus_ic = Float(header[2])
  declared = Integer(header[3], 10)
  check([letters, corpus_ic, declared] == [28_508_834, 0.0747, expected_entries],
        "unexpected #{File.basename(path)} metadata")

  contexts = WIDTH**(order - 1)
  counts = Array.new(contexts * WIDTH, 0)
  seen = {}
  window_total = 0
  pattern = /\A([A-Z]{#{order}}) ([0-9]+)\z/
  lines.each_with_index do |line, offset|
    record = pattern.match(line)
    check(!record.nil?, "malformed #{File.basename(path)} line #{offset + 2}")
    gram = record[1]
    check(!seen.key?(gram), "duplicate #{File.basename(path)} gram #{gram}")
    count = Integer(record[2], 10)
    check(count.positive?, "non-positive #{File.basename(path)} count for #{gram}")
    index = 0
    gram.bytes.each { |byte| index = index * WIDTH + byte - 65 }
    counts[index] = count
    seen[gram] = true
    window_total += count
  end
  check(seen.length == declared, "#{File.basename(path)} parsed/declared count mismatch")
  check(window_total == letters - order + 1,
        "#{File.basename(path)} total is not letters - order + 1")

  probabilities = Array.new(counts.length, 0.0)
  contexts.times do |context|
    row_start = context * WIDTH
    row_total = 0
    WIDTH.times { |symbol| row_total += counts[row_start + symbol] }
    denominator = row_total.to_f + ADD_K * WIDTH.to_f
    WIDTH.times do |symbol|
      probabilities[row_start + symbol] =
        Math.log((counts[row_start + symbol].to_f + ADD_K) / denominator)
    end
  end

  {
    probabilities: probabilities,
    sha256: digest,
    letters: letters,
    corpus_ic: corpus_ic,
    observed_entries: seen.length,
    window_total: window_total
  }
end

def score(symbols, probabilities, order)
  return -10.0 if symbols.length < order
  total = 0.0
  start = 0
  while start <= symbols.length - order
    index = 0
    offset = 0
    while offset < order
      index = index * WIDTH + symbols[start + offset]
      offset += 1
    end
    total = total + probabilities[index]
    start += 1
  end
  total / (symbols.length - order + 1).to_f
end

def coincidence(symbols)
  return 0.0 if symbols.length < 2
  frequencies = Array.new(WIDTH, 0)
  symbols.each { |symbol| frequencies[symbol] += 1 }
  numerator = 0
  frequencies.each { |frequency| numerator += frequency * (frequency - 1) }
  numerator.to_f / (symbols.length * (symbols.length - 1)).to_f
end

def attack_score(symbols, bigram_score)
  text = symbols.map { |symbol| symbol + 65 }.pack("C*")
  result = bigram_score - (coincidence(symbols) - GERMAN_IC).abs * IC_PENALTY_SCALE
  ATTACK_CRIBS.each { |crib| result += CRIB_BONUS if text.include?(crib) }
  result
end

def deterministic_sample(sample_index)
  output = []
  block_index = 0
  while output.length < SAMPLE_LENGTH
    material = STREAM_DOMAIN + "\x00".b + [sample_index, block_index].pack("N2")
    Digest::SHA256.digest(material).bytes.each do |byte|
      next unless byte < 234
      output << byte % WIDTH
      break if output.length == SAMPLE_LENGTH
    end
    block_index += 1
  end
  output
end

def population_stats(values)
  total = 0.0
  values.each { |value| total = total + value }
  mean = total / values.length.to_f
  squared_total = 0.0
  values.each do |value|
    delta = value - mean
    squared_total = squared_total + delta * delta
  end
  [mean, Math.sqrt(squared_total / values.length.to_f)]
end

def metric(value)
  {"decimal" => format("%.17g", value), "bit_pattern" => bits(value)}
end

def produce_receipt
  check(ARGV.empty?, "usage: #{File.basename($PROGRAM_NAME)}")
  root = File.expand_path("..", __dir__)
  bigram = parse_fixture(
    File.join(root, "Fixtures", "german_bigrams.txt"), 2, BIGRAM_SHA256, 674
  )
  trigram = parse_fixture(
    File.join(root, "Fixtures", "german_trigrams.txt"), 3, TRIGRAM_SHA256, 14_947
  )
  check(bigram[:letters] == trigram[:letters], "fixture letter totals differ")
  check(bigram[:corpus_ic] == trigram[:corpus_ic], "fixture IC values differ")

  reference = CONTROL.bytes.first(SAMPLE_LENGTH).map { |byte| byte - 65 }
  recovered = DENSE_RECOVERED_NONSENSE.bytes.map { |byte| byte - 65 }
  check(reference.length == SAMPLE_LENGTH, "reference is not 72 symbols")
  check(recovered.length == SAMPLE_LENGTH, "recovered control is not 72 symbols")

  samples = Array.new(SAMPLE_COUNT) { |sample_index| deterministic_sample(sample_index) }
  random_corpus = samples.map { |sample| sample.map { |symbol| symbol + 65 }.pack("C*") }.join("\n") + "\n"
  bigram_scores = samples.map { |sample| score(sample, bigram[:probabilities], 2) }
  trigram_scores = samples.map { |sample| score(sample, trigram[:probabilities], 3) }
  attack_scores = samples.zip(bigram_scores).map do |sample, bigram_value|
    attack_score(sample, bigram_value)
  end
  bigram_mean, bigram_deviation = population_stats(bigram_scores)
  trigram_mean, trigram_deviation = population_stats(trigram_scores)
  attack_mean, attack_deviation = population_stats(attack_scores)

  covariance_total = 0.0
  attack_scores.zip(trigram_scores).each do |attack_value, trigram_value|
    covariance_total = covariance_total +
      (attack_value - attack_mean) * (trigram_value - trigram_mean)
  end
  covariance = covariance_total / SAMPLE_COUNT.to_f
  correlation = covariance / (attack_deviation * trigram_deviation)
  production_correlation = rounded_six(correlation)
  trigram_weight = rounded_six(1.0 - production_correlation)

  attack_constants = {
    "randomMean" => rounded_six(attack_mean),
    "randomDeviation" => rounded_six(attack_deviation)
  }
  trigram_reference = score(reference, trigram[:probabilities], 3)
  trigram_constants = {
    "germanMean" => rounded_six(trigram_reference),
    "randomMean" => rounded_six(trigram_mean),
    "randomDeviation" => rounded_six(trigram_deviation)
  }

  objective = lambda do |symbols|
    bigram_value = score(symbols, bigram[:probabilities], 2)
    trigram_value = score(symbols, trigram[:probabilities], 3)
    attack_value = attack_score(symbols, bigram_value)
    attack_component =
      (attack_value - attack_constants["randomMean"]) / attack_constants["randomDeviation"]
    trigram_component =
      (trigram_value - trigram_constants["randomMean"]) / trigram_constants["randomDeviation"]
    (attack_component + trigram_weight * trigram_component) / (1.0 + trigram_weight)
  end

  random_objectives = samples.map { |sample| objective.call(sample) }
  objective_mean, objective_deviation = population_stats(random_objectives)

  candidate_record = lambda do |symbols|
    bigram_value = score(symbols, bigram[:probabilities], 2)
    trigram_value = score(symbols, trigram[:probabilities], 3)
    letters = symbols.map { |symbol| symbol + 65 }.pack("C*")
    {
      "sha256" => Digest::SHA256.hexdigest(letters),
      "bigram" => metric(bigram_value),
      "trigram" => metric(trigram_value),
      "index_of_coincidence" => metric(coincidence(symbols)),
      "attack_score" => metric(attack_score(symbols, bigram_value)),
      "objective" => metric(objective.call(symbols))
    }
  end

  {
    "schema" => "helut.enigma-objective-calibration.v2",
    "implementation" => "ruby-independent-v2",
    "runtime" => {"ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM},
    "models" => {
      "bigram" => {
        "model_id" => BIGRAM_MODEL_ID,
        "source_sha256" => bigram[:sha256],
        "order" => 2,
        "add_k" => ADD_K,
        "observed_entries" => bigram[:observed_entries],
        "window_total" => bigram[:window_total]
      },
      "trigram" => {
        "model_id" => TRIGRAM_MODEL_ID,
        "source_sha256" => trigram[:sha256],
        "order" => 3,
        "add_k" => ADD_K,
        "observed_entries" => trigram[:observed_entries],
        "window_total" => trigram[:window_total]
      }
    },
    "controls" => {
      "generator" => "SHA-256(domain || 0x00 || sample-u32be || block-u32be), reject bytes >= 234, byte mod 26",
      "domain_hex" => STREAM_DOMAIN.unpack("H*").fetch(0),
      "samples" => SAMPLE_COUNT,
      "symbols_per_sample" => SAMPLE_LENGTH,
      "first_sample_sha256" => Digest::SHA256.hexdigest(
        samples.first.map { |symbol| symbol + 65 }.pack("C*")
      ),
      "corpus_sha256" => Digest::SHA256.hexdigest(random_corpus)
    },
    "bigram_calibration" => {
      "german" => metric(score(reference, bigram[:probabilities], 2)),
      "random_mean" => metric(bigram_mean),
      "random_population_deviation" => metric(bigram_deviation)
    },
    "attack_calibration" => {
      "german" => metric(
        attack_score(reference, score(reference, bigram[:probabilities], 2))
      ),
      "random_mean" => metric(attack_mean),
      "random_population_deviation" => metric(attack_deviation),
      "swift_constants" => attack_constants
    },
    "trigram_calibration" => {
      "german" => metric(trigram_reference),
      "random_mean" => metric(trigram_mean),
      "random_population_deviation" => metric(trigram_deviation),
      "swift_constants" => trigram_constants
    },
    "attack_trigram_relationship" => {
      "covariance" => metric(covariance),
      "correlation" => metric(correlation)
    },
    "objective" => {
      "model_id" => OBJECTIVE_MODEL_ID,
      "definition" => "(attackZ + trigramWeight * trigramZ) / (1 + trigramWeight)",
      "attack_score_definition" => "bigram - 8 * abs(IC - 0.0747) + 0.05 per matched configured crib",
      "correlation_discount_definition" => "trigramWeight is the six-decimal non-shared fraction 1 - attack/trigram rho",
      "uses_rounded_production_constants" => true,
      "attack_trigram_correlation" => production_correlation,
      "trigram_weight" => trigram_weight,
      "attack_constants" => attack_constants,
      "trigram_constants" => trigram_constants,
      "random_mean" => metric(objective_mean),
      "random_population_deviation" => metric(objective_deviation),
      "german_reference" => candidate_record.call(reference),
      "dense_recovered_nonsense" => candidate_record.call(recovered)
    }
  }
end

begin
  puts JSON.pretty_generate(produce_receipt)
rescue ObjectiveAuditFailure, SystemCallError, ArgumentError => error
  warn "objective calibration failed: #{error.message}"
  exit 1
end
