

_             = require 'lodash'
os            = require 'os'
Agenda        = require 'agenda'
EventEmitter  = require 'events'
crypto        = require 'crypto'


###
```coffee
module.exports = (Module)->
  class ApplicationResque extends Module::Resque
    @inheritProtected()
    @include Module::AgendaResqueMixin # в этом миксине должны быть реализованы платформозависимые методы, которые будут посылать нативные запросы к реальной базе данных

    @module Module

  return ApplicationResque.initialize()
```

```coffee
module.exports = (Module)->
  {RESQUE} = Module::

  class PrepareModelCommand extends Module::SimpleCommand
    @inheritProtected()

    @module Module

    @public execute: Function,
      default: ->
        #...
        @facade.registerProxy Module::ApplicationResque.new RESQUE
        #...

  PrepareModelCommand.initialize()
```
###


module.exports = (Module)->
  {co} = Module::Utils

  Module.defineMixin Module::Mediator, (BaseClass) ->
    class AgendaExecutorMixin extends BaseClass
      @inheritProtected()
      @include Module::ConfigurableMixin

      @public fullQueueName: Function,
        args: [String]
        return: String
        default: (queueName)-> @[ipoResque].fullQueueName queueName

      ipoAgenda = @private agenda: Object
      ipoResque = @private resque: Module::ResqueInterface

      @public listNotificationInterests: Function,
        default: ->
          [
            Module::JOB_RESULT
            Module::START_RESQUE
          ]

      @public handleNotification: Function,
        default: (aoNotification)->
          vsName = aoNotification.getName()
          voBody = aoNotification.getBody()
          vsType = aoNotification.getType()
          switch vsName
            when Module::JOB_RESULT
              @getViewComponent().emit vsType, voBody
            when Module::START_RESQUE
              @start()
          return

      @public onRegister: Function,
        default: (args...)->
          @super args...
          {address, jobsCollection:collection} = @configs.agenda
          @setViewComponent new EventEmitter()
          @[ipoResque] = @facade.retrieveProxy Module::RESQUE
          name = "#{os.hostname()}-#{process.pid}"
          self = @
          @[ipoAgenda] = Module::Promise.new (resolve, reject) ->
            voAgenda = new Agenda()
              .database address, collection ? 'delayedJobs'
              .name name
              .maxConcurrency 16
              .defaultConcurrency 16
              .lockLimit 16
              .defaultLockLimit 16
              .defaultLockLifetime 5000
            voAgenda.on 'ready', co.wrap ->
              yield self.ensureIndexes voAgenda
              yield self.defineProcessors voAgenda
              resolve voAgenda
              yield return
            voAgenda.on 'error', (err) ->
              reject err
            return
          return

      @public ensureIndexes: Function,
        args: []
        return: Module::NILL
        default: (aoAgenda) ->
          aoAgenda ?= @[ipoAgenda]
          { queuesCollection } = @configs.agenda
          co ->
            voAgenda = yield aoAgenda
            voQueuesCollection = voAgenda._mdb.collection queuesCollection ? 'delayedQueues'
            yield voQueuesCollection.createIndex 'name'
            yield return

      @public @async defineProcessors: Function,
        args: []
        return: Module::NILL
        default: (aoAgenda) ->
          executor = @
          voAgenda = yield aoAgenda ? @[ipoAgenda]
          for {name, concurrency} in yield @[ipoResque].allQueues()
            [moduleName] = name.split '|>'
            if moduleName is @moduleName()
              voAgenda.define name, {concurrency}, (job, done) ->
                reverse = crypto.randomBytes 32
                executor.getViewComponent().once reverse, (aoError) -> done aoError
                {scriptName, data} = job.attrs.data
                executor.sendNotification scriptName, data, reverse
            continue
          yield return

      @public @async onRemove: Function,
        default: (args...)->
          @super args...
          yield @stop()
          yield return

      @public @async start: Function,
        args: []
        return: Module::NILL
        default: ->
          (yield @[ipoAgenda]).start()
          yield return

      @public @async stop: Function,
        args: []
        return: Module::NILL
        default: ->
          (yield @[ipoAgenda]).stop()
          yield return


    AgendaExecutorMixin.initializeMixin()
