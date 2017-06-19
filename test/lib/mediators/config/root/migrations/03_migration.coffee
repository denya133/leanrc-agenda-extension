LeanRC = require.main.require 'lib'

module.exports = (Module) ->
  class Migration3 extends LeanRC::Migration
    @inheritProtected()
    @module Module
  Migration3.initialize()
