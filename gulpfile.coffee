gulp        = require 'gulp'
fse         = require 'fs-extra'

# Define tasks from directory 'gulp/tasks'
tasksPath = "#{__dirname}/gulp/tasks"
fse.readdirSync tasksPath
  .forEach (file) -> require "#{tasksPath}/#{file}"

# Run 'help' task as default
gulp.task 'default', ['help']
