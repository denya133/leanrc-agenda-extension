

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
        @facade.registerProxy Module::ApplicationResque.new RESQUE,
          dbAddress: 'localhost:27017/resqueDB'
          queuesCollection: 'delayedQueues'
          jobsCollection: 'delayedJobs'
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

      @module Module

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
          ]

      @public handleNotification: Function,
        default: (aoNotification)->
          vsName = aoNotification.getName()
          voBody = aoNotification.getBody()
          vsType = aoNotification.getType()
          switch vsName
            when Module::JOB_RESULT
              @getViewComponent().emit vsType, voBody
          return

      @public onRegister: Function,
        default: (args...)->
          @super args...
          {dbAddress:address, jobsCollection:collection} = @configs
          @setViewComponent new EventEmitter()
          @[ipoResque] = @facade.retriveProxy Module::RESQUE
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
              voAgenda.start()
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
          { queuesCollection } = @configs
          co ->
            voAgenda = yield aoAgenda
            voQueuesCollection = voAgenda._mdb.collection queuesCollection ? 'delayedQueues'
            yield voQueuesCollection.createIndex 'name'
            yield return

      @public @async defineProcessors: Function,
        args: []
        return: Module::NILL
        default: (aoAgenda) ->
          voAgenda = yield aoAgenda ? @[ipoAgenda]
          for {name, concurrency} in yield @[ipoResque].allQueues()
            [moduleName] = name.split '|>'
            if moduleName is @moduleName()
              voAgenda.define name, {concurrency}, co.wrap (job, done)=>
                reverse = crypto.randomBytes 32
                @getViewComponent().once reverse, (aoError) -> done aoError
                {scriptName, data} = job.attrs.data
                @sendNotification scriptName, data, reverse
            continue
          yield return

      @public onRemove: Function,
        default: (args...)->
          @super args...
          @[ipoAgenda]?.then (aoAgenda) -> aoAgenda.stop()
          return


    AgendaExecutorMixin.initializeMixin()
