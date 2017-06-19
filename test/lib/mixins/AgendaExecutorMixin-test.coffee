EventEmitter  = require 'events'
{ expect, assert } = require 'chai'
sinon = require 'sinon'
_ = require 'lodash'
Agenda = require 'agenda'
LeanRC = require 'LeanRC'
AgendaExtension = require.main.require 'lib'
{ co } = LeanRC::Utils

defineJob = (aoAgenda, asName, anDuration = 250, aoTrigger) ->
  aoAgenda?.define asName, (job, done) ->
    aoTrigger?.emit? 'started', job
    setTimeout ->
      aoTrigger?.emit? 'complete', job
      done()
    , anDuration
  return

clearTempQueues = (aoAgenda, alQueues) ->
  if aoAgenda?
    jobsCollection = aoAgenda._mdb.collection 'delayedJobs'
    queuesCollection = aoAgenda._mdb.collection 'delayedQueues'
    if queuesCollection?
      for name in alQueues
        yield jobsCollection.deleteMany { name }
        yield queuesCollection.deleteOne { name }
  yield return

describe 'AgendaExecutorMixin', ->
  describe '.new', ->
    it 'should create new Agenda resque executor', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = TestExecutor.new executorName, viewComponent
        assert.instanceOf executor, TestExecutor
        yield return
  describe '#listNotificationInterests', ->
    it 'should check notification interests list', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = TestExecutor.new executorName, viewComponent
        assert.deepEqual executor.listNotificationInterests(), [
          LeanRC::JOB_RESULT
        ]
        yield return
  describe '#ensureIndexes', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_001'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should start resque', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
        TestResque.initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        {dbAddress:address, jobsCollection:collection, queuesCollection} = configs
        agenda = yield LeanRC::Promise.new (resolve, reject) ->
          voAgenda = new Agenda()
            .database address, collection ? 'delayedJobs'
            .name name
            .maxConcurrency 16
            .defaultConcurrency 16
            .lockLimit 16
            .defaultLockLimit 16
            .defaultLockLifetime 5000
          voAgenda.on 'ready', -> resolve voAgenda
          voAgenda.on 'error', (err) -> reject err
          return
        facade.registerProxy TestResque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        { name } = yield resque.create 'TEST_AGENDA_QUEUE', 4
        queueNames.push name
        executor = TestExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor.initializeNotifier KEY
        yield executor.ensureIndexes agenda
        voQueuesCollection = agenda._mdb.collection queuesCollection ? 'delayedQueues'
        assert.isTrue yield voQueuesCollection.indexExists [ 'name_1' ]
        yield return
  describe '#defineProcessors', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_002'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should start resque', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
        TestResque.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        {dbAddress:address, jobsCollection:collection} = configs
        agenda = yield LeanRC::Promise.new (resolve, reject) ->
          voAgenda = new Agenda()
            .database address, collection ? 'delayedJobs'
            .name name
            .maxConcurrency 16
            .defaultConcurrency 16
            .lockLimit 16
            .defaultLockLimit 16
            .defaultLockLifetime 5000
          voAgenda.on 'ready', -> resolve voAgenda
          voAgenda.on 'error', (err) -> reject err
          return
        facade.registerProxy TestResque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        executor = TestExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor.initializeNotifier KEY
        vpoResque = TestExecutor.instanceVariables['_resque'].pointer
        executor[vpoResque] = resque
        vpoAgenda = TestExecutor.instanceVariables['_agenda'].pointer
        executor[vpoAgenda] = agenda
        yield executor.ensureIndexes agenda
        yield executor.defineProcessors agenda
        assert.property agenda._definitions, resque.fullQueueName 'TEST_QUEUE_1'
        assert.property agenda._definitions, resque.fullQueueName 'TEST_QUEUE_2'
        yield return
  describe '#handleNotification', ->
    it 'should handle notification', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = new EventEmitter
        executor = TestExecutor.new executorName, viewComponent
        promise = LeanRC::Promise.new (resolve, reject) ->
          timeout = setTimeout (-> reject new Error 'Not handled'), 500
          viewComponent.once 'TEST_TYPE', (data) ->
            clearTimeout timeout
            resolve data
        executor.handleNotification Test::Notification.new 'TEST_NAME', 'TEST_BODY', 'TEST_TYPE'
        try
          yield promise
        catch err
        assert.instanceOf err, Error
        assert.propertyVal err, 'message', 'Not handled'
        promise = LeanRC::Promise.new (resolve, reject) ->
          timeout = setTimeout (-> reject new Error 'Not handled'), 500
          viewComponent.once 'TEST_TYPE', (data) ->
            clearTimeout timeout
            resolve data
        executor.handleNotification Test::Notification.new Test::JOB_RESULT, 'TEST_BODY', 'TEST_TYPE'
        result = yield promise
        assert.equal result, 'TEST_BODY'
        yield return
  describe '#fullQueueName', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_003'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should get queue full name', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
        TestResque.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        facade.registerProxy TestResque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        executor = TestExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor.initializeNotifier KEY
        vpoResque = TestExecutor.instanceVariables['_resque'].pointer
        executor[vpoResque] = resque
        assert.equal executor.fullQueueName('TEST_QUEUE_1'), 'Test|>TEST_QUEUE_1'
        assert.equal executor.fullQueueName('TEST_QUEUE_2'), 'Test|>TEST_QUEUE_2'
        yield return
  describe '#onRegister', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_004'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should setup executor on register', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
        TestResque.initialize()
        class TestExecutor extends LeanRC::Mediator
          @inheritProtected()
          @include Test::AgendaExecutorMixin
          @module Test
        TestExecutor.initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        facade.registerProxy TestResque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        executor = TestExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor.initializeNotifier KEY
        executor.onRegister()
        agenda = yield executor[TestExecutor.instanceVariables['_agenda'].pointer]
        assert.instanceOf agenda, Agenda
        assert.include agenda._name, require('os').hostname()
        assert.equal agenda._maxConcurrency, 16
        assert.equal agenda._defaultConcurrency, 16
        assert.equal agenda._lockLimit, 16
        assert.equal agenda._defaultLockLimit, 16
        assert.equal agenda._defaultLockLifetime, 5000
        assert.property agenda._definitions, resque.fullQueueName 'TEST_QUEUE_1'
        assert.property agenda._definitions, resque.fullQueueName 'TEST_QUEUE_2'
        yield return
  ###
  describe '#stop', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should stop executor', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executor.stop()
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        stoppedSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_isStopped)'
        assert.isTrue executor[stoppedSymbol]
        yield return
  describe '#onRemove', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should handle remove event', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executor.onRemove()
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        stoppedSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_isStopped)'
        assert.isTrue executor[stoppedSymbol]
        yield return
  describe '#define', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should define processor (success)', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        concurrencyCountSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_concurrencyCount)'
        executor[definedProcessorsSymbol] = {}
        executor[concurrencyCountSymbol] = {}
        QUEUE_NAME = 'TEST_QUEUE'
        concurrency = 4
        testTrigger = new EventEmitter
        executor.define QUEUE_NAME, { concurrency }, (job, done) ->
          assert job
          testTrigger.once 'DONE', (options) -> done options
        processorData = executor[definedProcessorsSymbol][QUEUE_NAME]
        assert.equal processorData.concurrency, concurrency
        { listener, concurrency: processorConcurrency } = processorData
        assert.equal processorConcurrency, concurrency
        job = status: 'scheduled'
        listener job
        assert.equal executor[concurrencyCountSymbol][QUEUE_NAME], 1
        assert.propertyVal job, 'status', 'running'
        assert.isDefined job.startedAt
        promise = LeanRC::Promise.new (resolve) ->
          testTrigger.once 'DONE', resolve
        testTrigger.emit 'DONE'
        yield promise
        assert.equal executor[concurrencyCountSymbol][QUEUE_NAME], 0
        assert.propertyVal job, 'status', 'completed'
        yield return
    it 'should define processor (fail)', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        concurrencyCountSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_concurrencyCount)'
        executor[definedProcessorsSymbol] = {}
        executor[concurrencyCountSymbol] = {}
        QUEUE_NAME = 'TEST_QUEUE'
        concurrency = 4
        testTrigger = new EventEmitter
        executor.define QUEUE_NAME, { concurrency }, (job, done) ->
          assert job
          testTrigger.once 'DONE', (options) -> done options
        processorData = executor[definedProcessorsSymbol][QUEUE_NAME]
        assert.equal processorData.concurrency, concurrency
        { listener, concurrency: processorConcurrency } = processorData
        assert.equal processorConcurrency, concurrency
        job = status: 'scheduled'
        listener job
        assert.equal executor[concurrencyCountSymbol][QUEUE_NAME], 1
        assert.propertyVal job, 'status', 'running'
        assert.isDefined job.startedAt
        promise = LeanRC::Promise.new (resolve) ->
          testTrigger.once 'DONE', resolve
        testTrigger.emit 'DONE', error: 'error'
        yield promise
        assert.equal executor[concurrencyCountSymbol][QUEUE_NAME], 0
        assert.propertyVal job, 'status', 'failed'
        assert.deepEqual job.reason, error: 'error'
        yield return
  describe '#defineProcessors', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should define processors', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_001'
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create 'TEST_QUEUE_1', 4
        resque.create 'TEST_QUEUE_2', 4
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        concurrencyCountSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_concurrencyCount)'
        resqueSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_resque)'
        executor.initializeNotifier KEY
        executor.setViewComponent new EventEmitter()
        executor[definedProcessorsSymbol] = {}
        executor[concurrencyCountSymbol] = {}
        executor[resqueSymbol] = resque
        yield executor.defineProcessors()
        assert.property executor[definedProcessorsSymbol], 'TEST_QUEUE_1'
        assert.property executor[definedProcessorsSymbol], 'TEST_QUEUE_2'
        facade.remove()
        yield return
  describe '#onRegister', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should setup executor on register', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_002'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
          @public @async defineProcessors: Function,
            default: (args...) ->
              yield @super args...
              trigger.emit 'PROCESSORS_DEFINED'
              yield return
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create 'TEST_QUEUE_1', 4
        resque.create 'TEST_QUEUE_2', 4
        executorName = 'TEST_AGENDA_EXECUTOR'
        viewComponent = { id: 'view-component' }
        executor = Test::AgendaExecutor.new executorName, viewComponent
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'PROCESSORS_DEFINED', resolve
        facade.registerMediator executor
        yield promise
        assert.property executor[definedProcessorsSymbol], 'TEST_QUEUE_1'
        assert.property executor[definedProcessorsSymbol], 'TEST_QUEUE_2'
        facade.remove()
        yield return
  describe '.staticRunner', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should call cycle part', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_003'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        test = null
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
          @public @async defineProcessors: Function,
            default: (args...) ->
              yield @super args...
              trigger.emit 'PROCESSORS_DEFINED'
              yield return
          @public @async cyclePart: Function,
            default: ->
              test = yes
              trigger.emit 'CYCLE_PART'
              yield return
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create 'TEST_QUEUE_1', 4
        resque.create 'TEST_QUEUE_2', 4
        executor = Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'PROCESSORS_DEFINED', resolve
        facade.registerMediator executor
        yield promise
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'CYCLE_PART', resolve
        yield Test::AgendaExecutor.staticRunner KEY
        yield promise
        assert.isNotNull test
        facade.remove()
        yield return
  describe '#recursion', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should recursively call cycle part', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_004'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        test = null
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
          @public @async defineProcessors: Function,
            default: (args...) ->
              yield @super args...
              trigger.emit 'PROCESSORS_DEFINED'
              yield return
          @public @async cyclePart: Function,
            default: ->
              test = yes
              trigger.emit 'CYCLE_PART'
              yield return
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create LeanRC::DELAYED_JOBS_QUEUE, 4
        executor = Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        isStoppedSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_isStopped)'
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'PROCESSORS_DEFINED', resolve
        facade.registerMediator executor
        yield promise
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'CYCLE_PART', resolve
        executor[isStoppedSymbol] = no
        yield executor.recursion()
        yield promise
        assert.isNotNull test
        facade.remove()
        yield return
  describe '#start', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should call recursion', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_005'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        test = null
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
          @public @async defineProcessors: Function,
            default: (args...) ->
              yield @super args...
              trigger.emit 'PROCESSORS_DEFINED'
              yield return
          @public @async cyclePart: Function,
            default: ->
              test = yes
              trigger.emit 'CYCLE_PART'
              yield return
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create LeanRC::DELAYED_JOBS_QUEUE, 4
        executor = Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executorSymbols = Object.getOwnPropertySymbols Test::AgendaExecutor::
        definedProcessorsSymbol = _.find executorSymbols, (item) ->
          item.toString() is 'Symbol(_definedProcessors)'
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'PROCESSORS_DEFINED', resolve
        facade.registerMediator executor
        yield promise
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'CYCLE_PART', resolve
        yield executor.start()
        yield promise
        assert.isNotNull test
        facade.remove()
        yield return
  describe '#handleNotification', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    afterEach ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should start resque', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_006'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        test = null
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
          @public @async start: Function,
            default: ->
              test = yes
              trigger.emit 'CYCLE_PART'
              yield return
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create LeanRC::DELAYED_JOBS_QUEUE, 4
        facade.registerMediator Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor = facade.retrieveMediator LeanRC::MEM_RESQUE_EXEC
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'CYCLE_PART', resolve
        facade.sendNotification LeanRC::START_RESQUE
        yield promise
        assert.isNotNull test
        facade.remove()
        yield return
    it 'should get result', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_007'
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
        Test::AgendaExecutor.initialize()
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        resque.create LeanRC::DELAYED_JOBS_QUEUE, 4
        facade.registerMediator Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor = facade.retrieveMediator LeanRC::MEM_RESQUE_EXEC
        type = 'TEST_TYPE'
        promise = LeanRC::Promise.new (resolve) ->
          executor.getViewComponent().once type, resolve
        body = test: 'test'
        facade.sendNotification LeanRC::JOB_RESULT, body, type
        data = yield promise
        assert.deepEqual data, body
        facade.remove()
        yield return
  describe '#cyclePart', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should start cycle part', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
        Test.initialize()
        KEY = 'TEST_AGENDA_EXECUTOR_008'
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC::Module
          @inheritProtected()
          @root "#{__dirname}/config/root"
        Test.initialize()
        class Test::Resque extends LeanRC::Resque
          @inheritProtected()
          @include LeanRC::MemoryResqueMixin
          @module Test
        Test::Resque.initialize()
        class Test::AgendaExecutor extends Test::AgendaExecutor
          @inheritProtected()
          @module Test
        Test::AgendaExecutor.initialize()
        class TestScript extends LeanRC::Script
          @inheritProtected()
          @module Test
          @do (body) ->
            trigger.emit 'CYCLE_PART', body
            yield return
        TestScript.initialize()
        facade.registerCommand 'TEST_SCRIPT', TestScript
        facade.registerProxy Test::Resque.new LeanRC::RESQUE
        resque = facade.retrieveProxy LeanRC::RESQUE
        yield resque.create LeanRC::DELAYED_JOBS_QUEUE, 4
        queue = yield resque.get LeanRC::DELAYED_JOBS_QUEUE
        facade.registerMediator Test::AgendaExecutor.new LeanRC::MEM_RESQUE_EXEC
        executor = facade.retrieveMediator LeanRC::MEM_RESQUE_EXEC
        promise = LeanRC::Promise.new (resolve) ->
          trigger.once 'CYCLE_PART', resolve
        DELAY_UNTIL = Date.now() + 1000
        body = arg1: 'ARG_1', arg2: 'ARG_2', arg3: 'ARG_3'
        yield queue.push 'TEST_SCRIPT', body, DELAY_UNTIL
        facade.sendNotification LeanRC::START_RESQUE
        data = yield promise
        assert.deepEqual data, body
        facade.remove()
        yield return
  ###
