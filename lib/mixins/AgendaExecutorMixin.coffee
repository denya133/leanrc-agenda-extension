

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
  {
    NILL
    JOB_RESULT
    START_RESQUE
    RESQUE

    Mediator
    ConfigurableMixin
    ResqueInterface
    Utils: { _, co }
  } = Module::

  _agenda = null

  Module.defineMixin 'AgendaExecutorMixin', (BaseClass = Mediator) ->
    class extends BaseClass
      @inheritProtected()
      @include ConfigurableMixin

      @public fullQueueName: Function,
        args: [String]
        return: String
        default: (queueName)-> @[ipoResque].fullQueueName queueName

      # ipoAgenda = @private agenda: Object
      ipoResque = @private resque: ResqueInterface

      @public listNotificationInterests: Function,
        default: ->
          [
            JOB_RESULT
            START_RESQUE
          ]

      @public handleNotification: Function,
        default: (aoNotification)->
          vsName = aoNotification.getName()
          voBody = aoNotification.getBody()
          vsType = aoNotification.getType()
          switch vsName
            when JOB_RESULT
              @getViewComponent().emit vsType, voBody
            when START_RESQUE
              @start()
          return

      @public onRegister: Function,
        default: (args...)->
          @super args...
          {address, jobsCollection:collection} = @configs.agenda
          @setViewComponent new EventEmitter()
          @[ipoResque] = @facade.retrieveProxy RESQUE
          name = "#{os.hostname()}-#{process.pid}"
          self = @
          _agenda = Module::Promise.new (resolve, reject) ->
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
        return: NILL
        default: (aoAgenda) ->
          aoAgenda ?= _agenda
          { queuesCollection } = @configs.agenda
          co ->
            voAgenda = yield aoAgenda
            voQueuesCollection = voAgenda._mdb.collection queuesCollection ? 'delayedQueues'
            yield voQueuesCollection.createIndex 'name'
            yield return

      @public @async defineProcessors: Function,
        args: []
        return: NILL
        default: (aoAgenda) ->
          executor = @
          voAgenda = yield aoAgenda ? _agenda
          for {name, concurrency} in yield @[ipoResque].allQueues()
            [moduleName] = name.split '|>'
            if moduleName is @moduleName()
              voAgenda.define name, {concurrency}, (job, done) ->
                reverse = crypto.randomBytes 32
                executor.getViewComponent().once reverse, ({error = null}) ->
                  done error
                {scriptName, data} = job.attrs.data
                executor.sendNotification scriptName, data, reverse
            continue
          yield return

      @public @async getAgenda: Function,
        default: ->
          return yield _agenda

      @public @async onRemove: Function,
        default: (args...)->
          @super args...
          yield @stop()
          yield return

      @public @async start: Function,
        args: []
        return: NILL
        default: ->
          (yield _agenda).start()
          yield return

      @public @async stop: Function,
        args: []
        return: NILL
        default: ->
          agenda = yield _agenda
          yield Module::Promise.new (resolve, reject) ->
            agenda.stop (err) ->
              if err?
                reject err
              else
                resolve()
              return
            return
          yield return


      @initializeMixin()
