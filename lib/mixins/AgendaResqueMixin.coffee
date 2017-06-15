

_             = require 'lodash'
LeanRC        = require 'LeanRC'
os            = require 'os'
Agenda        = require 'agenda'

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

  Module.defineMixin (BaseClass) ->
    class AgendaResqueMixin extends BaseClass
      @inheritProtected()

      ipoAgenda = @private agenda: Object

      @public onRegister: Function,
        default: (args...)->
          @super args...
          {dbAddress:address, jobsCollection:collection} = @getData()# надо использовать не @getData() а обращаться за конфигами к ConfigurationProxy
          name = os.hostname + '-' + process.pid
          @[ipoAgenda] = new Agenda()
            .database address, collection ? 'delayedJobs'
            .name name
            .maxConcurrency 16
            .defaultConcurrency 16
            .lockLimit 16
            .defaultLockLimit 16
            .defaultLockLifetime 5000
          @[ipoAgenda].start()
          return

      @public onRemove: Function,
        default: (args...)->
          @super args...
          @[ipoAgenda].stop()
          return

      @public @async ensureQueue: Function,
        default: (name, concurrency = 1)->
          name = @fullQueueName name
          {queuesCollection} = @getData()
          voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
          if (queue = yield voQueuesCollection.findOne name: name)?
            queue.concurrency = concurrency
            yield voQueuesCollection.update {name}, queue
          else
            yield voQueuesCollection.push {name, concurrency}
          yield return {name, concurrency}

      @public @async getQueue: Function,
        default: (name)->
          name = @fullQueueName name
          {queuesCollection} = @getData()
          voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
          if (queue = yield voQueuesCollection.findOne name: name)?
            {concurrency} = queue
            yield return {name, concurrency}
          else
            yield return

      @public @async removeQueue: Function,
        default: (queueName)->
          queueName = @fullQueueName queueName
          {queuesCollection} = @getData()
          voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
          if (queue = yield voQueuesCollection.findOne name: queueName)?
            yield voQueuesCollection.remove queue._id
          yield return

      @public @async allQueues: Function,
        default: ->
          {queuesCollection} = @getData()
          voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
          result = for {name, concurrency} in yield voQueuesCollection.find()
            {name, concurrency}
          yield return result

      @public @async pushJob: Function,
        default: (queueName, scriptName, data, delayUntil)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            job = @[ipoAgenda].create queueName, {scriptName, data}
            if delayUntil?
              job.schedule delayUntil
            else
              job.now()
            job.save (err)->
              if err?
                reject err
              else
                resolve job._id

      @public @async getJob: Function,
        default: (queueName, jobId)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs {name: queueName, _id: jobId}, (err, [job] = [])->
              if err
                reject err
              else
                resolve job

      @public @async deleteJob: Function,
        default: (queueName, jobId)->
          queueName = @fullQueueName queueName
          job = yield @getJob queueName, jobId
          if job?
            yield Module::Promise.new (resolve, reject)->
              job.remove (err)->
                if err?
                  reject err
                else
                  resolve()
            isDeleted = yes
          else
            isDeleted = no
          yield return isDeleted

      @public @async abortJob: Function,
        default: (queueName, jobId)->
          queueName = @fullQueueName queueName
          job = yield @getJob queueName, jobId
          if job? and job.status is 'scheduled'
            yield Module::Promise.new (resolve, reject)->
              job.fail new Error 'Job has been aborted'
              job.save (err)->
                if err?
                  reject err
                else
                  resolve()
          yield return

      @public @async allJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs {name: queueName, data: {scriptName}}, (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []

      @public @async pendingJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs
              name: queueName
              status: $in: ['scheduled', 'queued']
              data: {scriptName}
            , (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []

      @public @async progressJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs
              name: queueName
              status: 'running'
              data: {scriptName}
            , (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []

      @public @async completedJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs
              name: queueName
              status: 'completed'
              data: {scriptName}
            , (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []

      @public @async failedJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            @[ipoAgenda].jobs
              name: queueName
              status: 'failed'
              data: {scriptName}
            , (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []


    AgendaResqueMixin.initializeMixin()
