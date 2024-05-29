# frozen_string_literal: true

desc "Default rake task"
task default: %i[code:security code:quality spec]
