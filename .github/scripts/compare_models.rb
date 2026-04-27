#!/usr/bin/env ruby
# frozen_string_literal: true

# compare_models.rb <old_tag> <new_tag>
#
# Diffs solid_queue model files between two upstream tags (old vs new).
# For each file that changed upstream, also shows the local Mongoid equivalent
# so developers can decide if a corresponding change is needed.
#
# Outputs a Markdown PR body to STDOUT.

require "net/http"
require "json"
require "tmpdir"

OLD_TAG = ARGV[0] || abort("Usage: compare_models.rb <old_tag> <new_tag>")
NEW_TAG = ARGV[1] || abort("Usage: compare_models.rb <old_tag> <new_tag>")

UPSTREAM_REPO = "rails/solid_queue"
UPSTREAM_BASE = "app/models/solid_queue"
LOCAL_BASE    = File.expand_path("../../lib/solid_queue_mongoid/models", __dir__)

def github_api(path)
  uri = URI("https://api.github.com/#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Accept"]               = "application/vnd.github+json"
  req["X-GitHub-Api-Version"] = "2022-11-28"
  req["Authorization"]        = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV["GITHUB_TOKEN"]
  resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  JSON.parse(resp.body)
end

def raw_content(path, ref)
  uri = URI("https://raw.githubusercontent.com/#{UPSTREAM_REPO}/#{ref}/#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV["GITHUB_TOKEN"]
  resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
  resp.code == "200" ? resp.body : nil
end

def collect_upstream_files(dir_path, ref)
  entries = github_api("repos/#{UPSTREAM_REPO}/contents/#{dir_path}?ref=#{ref}")
  return [] unless entries.is_a?(Array)
  files = []
  entries.each do |entry|
    case entry["type"]
    when "file"
      files << entry["path"] if entry["name"].end_with?(".rb")
    when "dir"
      files.concat(collect_upstream_files(entry["path"], ref))
    end
  end
  files
rescue => e
  warn "Warning: could not list #{dir_path} at #{ref}: #{e.message}"
  []
end

$stderr.puts "Fetching upstream file list for #{OLD_TAG} and #{NEW_TAG}..."

old_files = collect_upstream_files(UPSTREAM_BASE, OLD_TAG)
new_files = collect_upstream_files(UPSTREAM_BASE, NEW_TAG)

all_relative = (old_files + new_files)
                 .map { |f| f.delete_prefix("#{UPSTREAM_BASE}/") }
                 .uniq
                 .sort

results = { modified: [], added: [], removed: [] }
diffs   = {}

Dir.mktmpdir("sqm_compare") do |tmpdir|
  all_relative.each do |relative|
    old_upstream_path = "#{UPSTREAM_BASE}/#{relative}"
    new_upstream_path = "#{UPSTREAM_BASE}/#{relative}"

    in_old = old_files.include?(old_upstream_path)
    in_new = new_files.include?(new_upstream_path)

    if in_old && in_new
      old_content = raw_content(old_upstream_path, OLD_TAG)
      new_content = raw_content(new_upstream_path, NEW_TAG)

      next if old_content.nil? || new_content.nil?
      next if old_content == new_content  # unchanged — skip entirely

      old_tmp = File.join(tmpdir, "old_#{relative.gsub('/', '__')}")
      new_tmp = File.join(tmpdir, "new_#{relative.gsub('/', '__')}")
      File.write(old_tmp, old_content)
      File.write(new_tmp, new_content)

      diff = `diff -u --label "solid_queue@#{OLD_TAG}/#{relative}" --label "solid_queue@#{NEW_TAG}/#{relative}" "#{old_tmp}" "#{new_tmp}" 2>&1`
      results[:modified] << relative
      diffs[relative] = { status: :modified, upstream_diff: diff }

    elsif in_new && !in_old
      new_content = raw_content(new_upstream_path, NEW_TAG)
      results[:added] << relative
      diffs[relative] = { status: :added, upstream_diff: new_content.to_s }

    elsif in_old && !in_new
      results[:removed] << relative
      diffs[relative] = { status: :removed, upstream_diff: nil }
    end
  end
end

# ── Generate Markdown report ──────────────────────────────────────────────────

lines = []
lines << "## solid_queue `#{NEW_TAG}` — Upstream Model Changes"
lines << ""
lines << "Comparing `rails/solid_queue` models between `#{OLD_TAG}` → `#{NEW_TAG}`."
lines << "Each section shows **what changed upstream** alongside **our current Mongoid model** for context."
lines << "Review each diff and decide if the corresponding Mongoid model needs updating."
lines << ""

total = results.values.sum(&:size)

if total.zero?
  lines << "> ✅ No model file changes detected between `#{OLD_TAG}` and `#{NEW_TAG}`. No action needed."
else
  lines << "### Summary"
  lines << ""
  lines << "| File | Upstream Change |"
  lines << "|------|-----------------|"
  results[:modified].each { |f| lines << "| `#{f}` | 🔄 Modified |" }
  results[:added].each    { |f| lines << "| `#{f}` | 🆕 Added in upstream |" }
  results[:removed].each  { |f| lines << "| `#{f}` | 🗑️ Removed from upstream |" }
  lines << ""

  lines << "### Review Checklist"
  lines << ""
  results[:modified].each { |f| lines << "- [ ] `lib/solid_queue_mongoid/models/#{f}` — review upstream changes" }
  results[:added].each    { |f| lines << "- [ ] `lib/solid_queue_mongoid/models/#{f}` — new upstream file, consider adding" }
  results[:removed].each  { |f| lines << "- [ ] `lib/solid_queue_mongoid/models/#{f}` — removed upstream, consider removing" }
  lines << ""

  lines << "---"
  lines << ""
  lines << "### Detailed Diffs"
  lines << ""

  diffs.each do |relative, info|
    local_path = File.join(LOCAL_BASE, relative)
    local_content = File.exist?(local_path) ? File.read(local_path) : nil

    status_label = case info[:status]
                   when :modified then "🔄 Modified upstream"
                   when :added    then "🆕 New upstream file"
                   when :removed  then "🗑️ Removed from upstream"
                   end

    lines << "---"
    lines << ""
    lines << "#### `#{relative}` — #{status_label}"
    lines << ""

    # What changed in upstream
    lines << "<details>"
    lines << "<summary>📥 What changed in upstream (#{OLD_TAG} → #{NEW_TAG})</summary>"
    lines << ""
    if info[:status] == :removed
      lines << "_This file was removed from upstream solid_queue._"
    else
      lines << "```diff"
      lines << info[:upstream_diff].to_s.strip
      lines << "```"
    end
    lines << ""
    lines << "</details>"
    lines << ""

    # Our current local Mongoid model for reference
    lines << "<details>"
    lines << "<summary>📄 Our current Mongoid model — `lib/solid_queue_mongoid/models/#{relative}`</summary>"
    lines << ""
    if local_content
      lines << "```ruby"
      lines << local_content.strip
      lines << "```"
    else
      lines << "_No local equivalent exists for this file._"
    end
    lines << ""
    lines << "</details>"
    lines << ""
  end
end

puts lines.join("\n")

