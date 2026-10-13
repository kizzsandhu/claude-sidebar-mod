#!/usr/bin/env ruby
# Writes themes/*.json, Claude Code themes for the three Rose Pine variants.
#
# Palette: https://github.com/rose-pine/palette (MIT), source/index.ts.
# Roles follow https://rosepinetheme.com/palette/ingredients: love for errors
# and removals, gold for warnings, foam for additions and info, iris for hints
# and merges, rose as the accent, highlight low/med/high for the cursor line,
# selection and borders.
#
# Run: ruby rose-pine/build.rb

require 'json'

PALETTES = {
  'rose-pine' => {
    name: 'Rosé Pine', base_preset: 'dark',
    base: '#191724', surface: '#1f1d2e', overlay: '#26233a', muted: '#6e6a86', subtle: '#908caa',
    text: '#e0def4', love: '#eb6f92', gold: '#f6c177', rose: '#ebbcba', pine: '#31748f',
    foam: '#9ccfd8', iris: '#c4a7e7', hl_low: '#21202e', hl_med: '#403d52', hl_high: '#524f67'
  },
  'rose-pine-moon' => {
    name: 'Rosé Pine Moon', base_preset: 'dark',
    base: '#232136', surface: '#2a273f', overlay: '#393552', muted: '#6e6a86', subtle: '#908caa',
    text: '#e0def4', love: '#eb6f92', gold: '#f6c177', rose: '#ea9a97', pine: '#3e8fb0',
    foam: '#9ccfd8', iris: '#c4a7e7', hl_low: '#2a283e', hl_med: '#44415a', hl_high: '#56526e'
  },
  'rose-pine-dawn' => {
    name: 'Rosé Pine Dawn', base_preset: 'light',
    base: '#faf4ed', surface: '#fffaf3', overlay: '#f2e9e1', muted: '#9893a5', subtle: '#797593',
    text: '#464261', love: '#b4637a', gold: '#ea9d34', rose: '#d7827e', pine: '#286983',
    foam: '#56949f', iris: '#907aa9', hl_low: '#f4ede8', hl_med: '#dfdad9', hl_high: '#cecacd'
  }
}.freeze

def rgb(hex) = hex.delete('#').scan(/../).map { |c| c.to_i(16) }

# `t` of the way from colour a to colour b.
def mix(a, b, t)
  '#' + rgb(a).zip(rgb(b)).map { |x, y| format('%02x', (x + (y - x) * t).round) }.join
end

def theme(p)
  light = p[:base_preset] == 'light'
  # A shimmer is the paler step of a colour in the spinner's sweep.
  shimmer = ->(c) { mix(c, light ? p[:surface] : p[:text], 0.4) }
  # Line backgrounds: the colour washed into the page.
  wash = ->(c, t) { mix(p[:base], c, t) }
  orange = mix(p[:love], p[:gold], 0.5)

  overrides = {
    # Text and accent
    'claude' => p[:rose], 'claudeShimmer' => shimmer[p[:rose]],
    'text' => p[:text], 'inverseText' => p[:base],
    'inactive' => p[:subtle], 'inactiveShimmer' => shimmer[p[:subtle]],
    'subtle' => p[:muted],
    'suggestion' => p[:foam],
    'permission' => p[:iris], 'permissionShimmer' => shimmer[p[:iris]],
    'remember' => p[:iris],

    # Status
    'success' => p[:foam], 'error' => p[:love],
    'warning' => p[:gold], 'warningShimmer' => shimmer[p[:gold]],
    'merged' => p[:iris],

    # Input box and modes
    'promptBorder' => p[:hl_high], 'promptBorderShimmer' => p[:muted],
    'planMode' => p[:foam], 'autoAccept' => p[:iris], 'bashBorder' => p[:love],
    'ide' => p[:pine],
    'fastMode' => p[:gold], 'fastModeShimmer' => shimmer[p[:gold]],
    'effortUltra' => p[:iris],

    # Diffs
    'diffAdded' => wash[p[:foam], 0.2],
    'diffRemoved' => wash[p[:love], 0.18],
    'diffAddedDimmed' => wash[p[:foam], 0.08],
    'diffRemovedDimmed' => wash[p[:love], 0.08],
    'diffAddedWord' => wash[p[:foam], 0.42],
    'diffRemovedWord' => wash[p[:love], 0.4],

    # Transcript backgrounds
    'userMessageBackground' => p[:overlay],
    'userMessageBackgroundHover' => p[:hl_med],
    'bashMessageBackgroundColor' => mix(p[:overlay], p[:love], 0.1),
    'memoryBackgroundColor' => mix(p[:overlay], p[:iris], 0.1),
    'selectionBg' => p[:hl_med],

    # Usage meter and speaker labels
    'rate_limit_fill' => p[:iris], 'rate_limit_empty' => p[:hl_high],
    'briefLabelYou' => p[:foam], 'briefLabelClaude' => p[:rose],

    # Subagents, by the colour their definition names
    'red_FOR_SUBAGENTS_ONLY' => p[:love], 'blue_FOR_SUBAGENTS_ONLY' => p[:pine],
    'green_FOR_SUBAGENTS_ONLY' => p[:foam], 'yellow_FOR_SUBAGENTS_ONLY' => p[:gold],
    'purple_FOR_SUBAGENTS_ONLY' => p[:iris], 'orange_FOR_SUBAGENTS_ONLY' => orange,
    'pink_FOR_SUBAGENTS_ONLY' => p[:rose], 'cyan_FOR_SUBAGENTS_ONLY' => mix(p[:foam], p[:pine], 0.4)
  }

  # The ultrathink rainbow
  rainbow = { 'red' => p[:love], 'orange' => orange, 'yellow' => p[:gold], 'green' => p[:foam],
              'blue' => p[:pine], 'indigo' => mix(p[:pine], p[:iris], 0.5), 'violet' => p[:iris] }
  rainbow.each do |name, c|
    overrides["rainbow_#{name}"] = c
    overrides["rainbow_#{name}_shimmer"] = shimmer[c]
  end

  { 'name' => p[:name], 'base' => p[:base_preset], 'overrides' => overrides }
end

dir = File.join(__dir__, 'themes')
Dir.mkdir(dir) unless Dir.exist?(dir)
PALETTES.each do |slug, p|
  File.write(File.join(dir, "#{slug}.json"), JSON.pretty_generate(theme(p)) + "\n")
end
