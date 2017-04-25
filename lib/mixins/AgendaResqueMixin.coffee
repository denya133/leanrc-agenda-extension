

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

  class AgendaResqueMixin extends LeanRC::Mixin
    @inheritProtected()

    @module Module

    ipoAgenda = @private agenda: Object

    @public onRegister: Function,
      default: (args...)->
        @super args...
        {dbAddress:address, jobsCollection:collection} = @getData()
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
      return: Module::NILL
      default: ->
        @[ipoAgenda]._db.ensureIndex 'name' # уточнить код. должен быть на коллекции 'delayedQueues'
        return

    @public @async defineProcessors: Function,
      args: []
      return: Module::NILL
      default: ->
        for {name, concurrency} in yield @allQueues()
          @[ipoAgenda].define name, {concurrency}, (job, done)->
            {scriptName, data} = job.attrs.data
            script = require "#{Module.ROOT}/scripts/#{scriptName}"
            # возможно надо вызывать выполнение скрипта внутри отдельного треда
            # надо исследовать модуль 'webworker-threads'
            script data # в аранге внутри скрипта module.context.argv - с этим надо что-то придумать.
          continue
        yield return

    @public onRemove: Function,
      default: (args...)->
        @super args...
        @[ipoAgenda].stop()
        return

    @public @async ensureQueue: Function,
      default: (name, concurrency = 1)->
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
        {queuesCollection} = @getData()
        voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
        if (queue = yield voQueuesCollection.findOne name: name)?
          {concurrency} = queue
          yield return {name, concurrency}
        else
          yield return

    @public @async removeQueue: Function,
      default: (name)->
        {queuesCollection} = @getData()
        voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
        if (queue = yield voQueuesCollection.findOne name: name)?
          yield voQueuesCollection.remove queue._id
        yield return

    @public @async allQueues: Function,
      default: ->
        {queuesCollection} = @getData()
        voQueuesCollection = @[ipoAgenda]._db.collection queuesCollection ? 'delayedQueues'
        yield return for {name, concurrency} in yield voQueuesCollection.find()
          {name, concurrency}

    @public @async pushJob: Function,
      default: (queueName, scriptName, data, delayUntil)->
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
        yield return Module::Promise.new (resolve, reject)->
          @[ipoAgenda].jobs {name: queueName, _id: jobId}, (err, [job] = [])->
            if err
              reject err
            else
              resolve job

    @public @async deleteJob: Function,
      default: (queueName, jobId)->
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
        yield return Module::Promise.new (resolve, reject)->
          @[ipoAgenda].jobs {name: queueName, data: {scriptName}}, (err, jobs)->
            if err
              reject err
            else
              resolve jobs ? []

    @public @async pendingJobs: Function,
      default: (queueName, scriptName)->
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


  AgendaResqueMixin.initialize()
