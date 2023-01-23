# typed: true
# frozen_string_literal: true

require "bundler/setup"
require "fileutils"
require "json"
require "minitest/autorun"
require "minitest/hooks/default"
require "minitest/test_task"
require "open3"
require "prettier_print"
require "socket"
require "sorbet-runtime"
require "syntax_tree"
require "syntax_tree/haml"
require "syntax_tree/rbs"
