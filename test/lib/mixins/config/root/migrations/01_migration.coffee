LeanRC = require.main.require 'lib'

module.exports = (Module) ->
  class Migration1 extends LeanRC::Migration
    @inheritProtected()
    @module Module
  Migration1.initialize()
