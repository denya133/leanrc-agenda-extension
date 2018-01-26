EventEmitter  = require 'events'
{ expect, assert } = require 'chai'
sinon = require 'sinon'
_ = require 'lodash'
Agenda = require 'agenda'
LeanRC = require 'LeanRC'
AgendaExtension = require.main.require 'lib'
{ co } = LeanRC::Utils

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
          LeanRC::START_RESQUE
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
        {address, jobsCollection:collection, queuesCollection} = configs.agenda
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
        {address, jobsCollection:collection} = configs.agenda
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
        assert.isUndefined agenda._processInterval
        yield return
  describe '#onRemove', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_EXECUTOR_004'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should handle remove event', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
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
        executor.onRemove()
        agenda = yield executor[TestExecutor.instanceVariables['_agenda'].pointer]
        assert.isUndefined agenda._processInterval
        yield return
