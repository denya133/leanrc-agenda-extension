

_             = require 'lodash'
LeanRC        = require 'LeanRC'
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
  {co} = LeanRC::Utils

  class AgendaExecutor extends LeanRC::Mediator
    @inheritProtected()

    @module Module

    @public fullQueueName: Function,
      args: [String]
      return: String
      default: (queueName)-> @[ipoResque].fullQueueName queueName

    ipoAgenda = @private agenda: Object
    ipoResque = @private resqie: Module::ResqueInterface

    @public listNotificationInterests: Function,
      default: ->
        [
          LeanRC::JOB_RESULT
        ]

    @public handleNotification: Function,
      default: (aoNotification)->
        vsName = aoNotification.getName()
        voBody = aoNotification.getBody()
        vsType = aoNotification.getType()
        switch vsName
          when LeanRC::JOB_RESULT
            @getViewComponent().emit vsType, voBody
        return

    @public onRegister: Function,
      default: (args...)->
        @super args...
        {dbAddress:address, jobsCollection:collection} = @getData() # надо использовать не @getData() а обращаться за конфигами к ConfigurationProxy
        @setViewComponent new EventEmitter()
        @[ipoResque] = @facade.retriveProxy LeanRC::RESQUE
        name = os.hostname + '-' + process.pid
        @[ipoAgenda] = new Agenda()
          .database address, collection ? 'delayedJobs'
          .name name
          .maxConcurrency 16
          .defaultConcurrency 16
          .lockLimit 16
          .defaultLockLimit 16
          .defaultLockLifetime 5000
        @ensureIndexes()
        @defineProcessors()
        @[ipoAgenda].start()
        return

    @public ensureIndexes: Function,
      args: []
      return: LeanRC::NILL
      default: ->
        @[ipoAgenda]._db.ensureIndex 'name' # уточнить код. должен быть на коллекции 'delayedQueues'
        return

    @public @async defineProcessors: Function,
      args: []
      return: LeanRC::NILL
      default: ->
        for {name, concurrency} in yield @[ipoResque].allQueues()
          [moduleName] = name.split '|>'
          if moduleName is @moduleName
            @[ipoAgenda].define name, {concurrency}, co.wrap (job, done)=>
              reverse = crypto.randomBytes 32
              @getViewComponent().once reverse, (aoError)=>
                done aoError
              {scriptName, data} = job.attrs.data
              @sendNotification scriptName, data, reverse
          continue
        yield return

    @public onRemove: Function,
      default: (args...)->
        @super args...
        @[ipoAgenda].stop()
        return


  AgendaExecutor.initialize()