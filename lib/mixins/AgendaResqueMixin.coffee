

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

  Module.defineMixin Module::Resque, (BaseClass) ->
    class AgendaResqueMixin extends BaseClass
      @inheritProtected()

      @include Module::ConfigurableMixin

      ipoAgenda = @private agenda: Object

      @public onRegister: Function,
        default: (args...)->
          @super args...
          {dbAddress:address, jobsCollection:collection} = @configs
          name = os.hostname() + '-' + process.pid
          @[ipoAgenda] = Module::Promise.new (resolve, reject) ->
            voAgenda = new Agenda()
              .database address, collection ? 'delayedJobs'
              .name name
              .maxConcurrency 16
              .defaultConcurrency 16
              .lockLimit 16
              .defaultLockLimit 16
              .defaultLockLifetime 5000
            voAgenda.on 'ready', ->
              voAgenda.start()
              resolve voAgenda
            voAgenda.on 'error', (err) ->
              reject err
            return
          return

      @public onRemove: Function,
        default: (args...)->
          @super args...
          @[ipoAgenda].then (aoAgenda) ->
            aoAgenda.stop()
          return

      @public @async ensureQueue: Function,
        default: (name, concurrency = 1)->
          name = @fullQueueName name
          {queuesCollection} = @configs
          voQueuesCollection = (yield @[ipoAgenda])._mdb.collection queuesCollection ? 'delayedQueues'
          if (queue = yield voQueuesCollection.findOne name: name)?
            queue.concurrency = concurrency
            yield voQueuesCollection.updateOne {name}, queue
          else
            yield voQueuesCollection.insertOne {name, concurrency}
          yield return {name, concurrency}

      @public @async getQueue: Function,
        default: (name)->
          name = @fullQueueName name
          {queuesCollection} = @configs
          voQueuesCollection = (yield @[ipoAgenda])._mdb.collection queuesCollection ? 'delayedQueues'
          if (queue = yield voQueuesCollection.findOne name: name)?
            {concurrency} = queue
            yield return {name, concurrency}
          else
            yield return

      @public @async removeQueue: Function,
        default: (queueName)->
          queueName = @fullQueueName queueName
          {queuesCollection} = @configs
          voQueuesCollection = (yield @[ipoAgenda])._mdb.collection queuesCollection ? 'delayedQueues'
          yield voQueuesCollection.deleteOne name: queueName
          yield return

      @public @async allQueues: Function,
        default: ->
          {queuesCollection} = @configs
          voQueuesCollection = (yield @[ipoAgenda])._mdb.collection queuesCollection ? 'delayedQueues'
          queues = yield voQueuesCollection.find {}
          queues = yield queues.toArray()
          queues = queues.map ({ name, concurrency }) -> { name, concurrency }
          yield return queues

      @public @async pushJob: Function,
        default: (queueName, scriptName, data, delayUntil)->
          queueName = @fullQueueName queueName
          voAgenda = yield @[ipoAgenda]
          createJob = (name, data, { delayUntil }, cb) ->
            if delayUntil?
              voAgenda.schedule delayUntil, name, data, cb
            else
              voAgenda.now name, data, cb
          yield return Module::Promise.new (resolve, reject)->
            job = createJob queueName, {scriptName, data}, { delayUntil }, (err) ->
              if err?
                reject err
              else
                resolve job.attrs._id
            return

      @public @async getJob: Function,
        default: (queueName, jobId, options = {})->
          queueName = @fullQueueName queueName
          voAgenda = yield @[ipoAgenda]
          yield return Module::Promise.new (resolve, reject)->
            voAgenda.jobs {name: queueName, _id: jobId}, (err, [job] = [])->
              if err
                reject err
              else
                resolve if job?
                  if options.native then job else job.attrs
                else
                  null

      @public @async deleteJob: Function,
        default: (queueName, jobId)->
          job = yield @getJob queueName, jobId, native: yes
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
          job = yield @getJob queueName, jobId, native: yes
          if job? and not job.attrs.failReason? and not job.attrs.failedAt?
            yield Module::Promise.new (resolve, reject)->
              job.fail new Error 'Job has been aborted'
              job.save (err)->
                if err?
                  reject err
                else
                  resolve()
          yield return

      @public @async allJobs: Function,
        default: (queueName, scriptName, options = {})->
          queueName = @fullQueueName queueName
          voAgenda = yield @[ipoAgenda]
          yield return Module::Promise.new (resolve, reject)->
            vhQuery = name: queueName
            if scriptName?
              vhQuery['data.scriptName'] = scriptName
            voAgenda.jobs vhQuery, (err, jobs)->
              if err?
                reject err
              else
                unless options.native
                  jobs = jobs.map (job) -> job.attrs
                resolve jobs ? []

      @public @async pendingJobs: Function,
        default: (queueName, scriptName, options = {})->
          queueName = @fullQueueName queueName
          voAgenda = yield @[ipoAgenda]
          yield return Module::Promise.new (resolve, reject)->
            vhQuery =
              name: queueName
              lastRunAt: $exists: no
              failedAt: $exists: no
            if scriptName?
              vhQuery['data.scriptName'] = scriptName
            voAgenda.jobs vhQuery, (err, jobs)->
              if err
                reject err
              else
                unless options.native
                  jobs = jobs.map (job) -> job.attrs
                resolve jobs ? []

      @public @async progressJobs: Function,
        default: (queueName, scriptName)->
          queueName = @fullQueueName queueName
          yield return Module::Promise.new (resolve, reject)->
            (yield @[ipoAgenda]).jobs
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
            (yield @[ipoAgenda]).jobs
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
            (yield @[ipoAgenda]).jobs
              name: queueName
              status: 'failed'
              data: {scriptName}
            , (err, jobs)->
              if err
                reject err
              else
                resolve jobs ? []


    AgendaResqueMixin.initializeMixin()
