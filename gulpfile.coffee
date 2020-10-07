{ task }    = require 'gulp'
fse         = require 'fs-extra'

# Define tasks from directory 'gulp/tasks'
tasksPath = "#{__dirname}/gulp/tasks"
fse.readdirSync tasksPath
  .forEach (file) -> require "#{tasksPath}/#{file}"

task 'default', task 'build'
