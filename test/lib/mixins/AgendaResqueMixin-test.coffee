{ expect, assert } = require 'chai'
sinon = require 'sinon'
_ = require 'lodash'
EventEmitter = require 'events'
{ ObjectID } = require 'mongodb'
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

clearTempQueues = co.wrap (aoAgenda, alQueues) ->
  if aoAgenda?
    jobsCollection = aoAgenda._mdb.collection 'delayedJobs'
    queuesCollection = aoAgenda._mdb.collection 'delayedQueues'
    if queuesCollection?
      for name in alQueues
        yield jobsCollection.deleteMany { name }
        yield queuesCollection.deleteOne { name }
  yield return


describe 'AgendaResqueMixin', ->
  describe '.new', ->
    it 'should create resque instance', ->
      co ->
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        assert.instanceOf resque, TestResque
        yield return
  describe '#onRegister', ->
    facade = null
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_001'
    after -> facade?.remove?()
    it 'should run on-register flow', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        resque.initializeNotifier KEY
        resque.onRegister()
        agenda = yield resque.getAgenda() #[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        assert.instanceOf agenda, Agenda
        assert.include agenda._name, require('os').hostname()
        assert.equal agenda._maxConcurrency, 16
        assert.equal agenda._defaultConcurrency, 16
        assert.equal agenda._lockLimit, 16
        assert.equal agenda._defaultLockLimit, 16
        assert.equal agenda._defaultLockLifetime, 5000
        yield return
  describe '#onRemove', ->
    facade = null
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_002'
    after -> facade?.remove?()
    it 'should run on-remove flow', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        resque.initializeNotifier KEY
        resque.onRegister()
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        spyStop = sinon.spy agenda._mdb, 'close'
        yield resque.onRemove()
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        assert.isTrue spyStop.called
        yield return
  describe '#ensureQueue', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_003'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should create queue config', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name, concurrency } = yield resque.ensureQueue 'TEST_QUEUE', 5
        queueNames.push name
        assert.equal name, 'Test|>TEST_QUEUE'
        assert.equal concurrency, 5
        collection = agenda._mdb.collection 'delayedQueues'
        count = yield collection.count { name }
        assert.equal count, 1
        { name, concurrency } = yield resque.ensureQueue 'TEST_QUEUE', 5
        queueNames.push name
        assert.equal name, 'Test|>TEST_QUEUE'
        assert.equal concurrency, 5
        collection = agenda._mdb.collection 'delayedQueues'
        count = yield collection.count { name }
        assert.equal count, 1
        yield return
  describe '#getQueue', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_004'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should get queue', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        yield resque.ensureQueue 'TEST_QUEUE', 5
        queue = yield resque.getQueue 'TEST_QUEUE'
        queueNames.push queue.name
        assert.propertyVal queue, 'name', 'Test|>TEST_QUEUE'
        assert.propertyVal queue, 'concurrency', 5
        yield return
  describe '#removeQueue', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_005'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should remove queue', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE', 5
        queueNames.push name
        queue = yield resque.getQueue 'TEST_QUEUE'
        assert.isDefined queue
        yield resque.removeQueue 'TEST_QUEUE'
        queue = yield resque.getQueue 'TEST_QUEUE'
        assert.isUndefined queue
        yield return
  describe '#allQueues', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_006'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should get all queues', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 2
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_3', 3
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_4', 4
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_5', 5
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_6', 6
        queueNames.push name
        queues = yield resque.allQueues()
        assert.includeDeepMembers queues, [
          name: 'Test|>TEST_QUEUE_1', concurrency: 1
        ,
          name: 'Test|>TEST_QUEUE_2', concurrency: 2
        ,
          name: 'Test|>TEST_QUEUE_3', concurrency: 3
        ,
          name: 'Test|>TEST_QUEUE_4', concurrency: 4
        ,
          name: 'Test|>TEST_QUEUE_5', concurrency: 5
        ,
          name: 'Test|>TEST_QUEUE_6', concurrency: 6
        ]
        yield return
  describe '#pushJob', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_007'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should save new job', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 60000
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT', DATA, DATE
        jobsCollection = agenda?._mdb.collection 'delayedJobs'
        job = yield jobsCollection.findOne _id: ObjectID jobId
        assert.include job,
          name: 'Test|>TEST_QUEUE_1'
          type: 'normal'
          priority: 0
        assert.deepEqual job.data, data: DATA, scriptName: 'TEST_SCRIPT'
        assert.equal "#{job._id}", jobId
        assert.equal job.nextRunAt.toISOString(), DATE.toISOString()
        assert.equal job.lastModifiedBy, agenda._name
        yield return
  describe '#getJob', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_008'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should get saved job', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 60000
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId
        assert.include job,
          name: 'Test|>TEST_QUEUE_1'
          type: 'normal'
          priority: 0
        assert.deepEqual job.data, data: DATA, scriptName: 'TEST_SCRIPT'
        assert.equal "#{job._id}", jobId
        assert.equal job.nextRunAt.toISOString(), DATE.toISOString()
        assert.equal job.lastModifiedBy, agenda._name
        yield return
  describe '#deleteJob', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_009'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should remove saved job', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 60000
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId
        assert.include job,
          name: 'Test|>TEST_QUEUE_1'
          type: 'normal'
          priority: 0
        assert.deepEqual job.data, data: DATA, scriptName: 'TEST_SCRIPT'
        assert.equal "#{job._id}", jobId
        assert.equal job.nextRunAt.toISOString(), DATE.toISOString()
        assert.equal job.lastModifiedBy, agenda._name
        assert.isTrue yield resque.deleteJob 'TEST_QUEUE_1', jobId
        assert.isNull yield resque.getJob 'TEST_QUEUE_1', jobId
        yield return
  describe '#abortJob', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_010'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should discard job', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 60000
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId
        assert.include job,
          name: 'Test|>TEST_QUEUE_1'
          type: 'normal'
          priority: 0
        assert.deepEqual job.data, data: DATA, scriptName: 'TEST_SCRIPT'
        assert.equal "#{job._id}", jobId
        assert.equal job.nextRunAt.toISOString(), DATE.toISOString()
        assert.equal job.lastModifiedBy, agenda._name
        yield resque.abortJob 'TEST_QUEUE_1', jobId
        job = yield resque.getJob 'TEST_QUEUE_1', jobId
        assert.include job,
          name: 'Test|>TEST_QUEUE_1'
          type: 'normal'
          priority: 0
          failReason: 'Job has been aborted'
          failCount: 1
        assert.deepEqual job.data, data: DATA, scriptName: 'TEST_SCRIPT'
        assert.equal "#{job._id}", jobId
        assert.equal job.nextRunAt.toISOString(), DATE.toISOString()
        assert.equal job.lastModifiedBy, agenda._name
        assert.isDefined job.failedAt
        yield return
  describe '#allJobs', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_011'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should list all jobs', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 3600000
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.deleteJob 'TEST_QUEUE_1', jobId
        jobs = yield resque.allJobs 'TEST_QUEUE_1'
        assert.lengthOf jobs, 3
        jobs = yield resque.allJobs 'TEST_QUEUE_1', 'TEST_SCRIPT_2'
        assert.lengthOf jobs, 2
        yield return
  describe '#pendingJobs', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_012'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should list pending jobs', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_1'), 250
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_2'), 450
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 600000
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId, native: yes
        yield LeanRC::Promise.new (resolve, reject) ->
          job.run (err, item) -> if err? then reject err else resolve item
        jobs = yield resque.pendingJobs 'TEST_QUEUE_1'
        assert.lengthOf jobs, 2
        jobs = yield resque.pendingJobs 'TEST_QUEUE_1', 'TEST_SCRIPT_2'
        assert.lengthOf jobs, 1
        yield return
  describe '#progressJobs', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_013'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should list running jobs', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_1'), 2000, trigger
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_2'), 450, trigger
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 600000
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId, native: yes
        promise = LeanRC::Promise.new (resolve, reject) ->
          trigger.once 'started', (processingJob) ->
            if processingJob._id is job._id
              resolve()
            return
        job.run()
        yield promise
        job = yield resque.getJob 'TEST_QUEUE_1', jobId, native: yes
        jobs = yield resque.progressJobs 'TEST_QUEUE_1'
        assert.lengthOf jobs, 1
        jobs = yield resque.progressJobs 'TEST_QUEUE_1', 'TEST_SCRIPT_2'
        assert.lengthOf jobs, 0
        yield return
  describe '#completedJobs', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_014'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should list complete jobs', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_1'), 250, trigger
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_2'), 450, trigger
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 600000
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId, native: yes
        promise = LeanRC::Promise.new (resolve, reject) ->
          trigger.once 'complete', resolve
        yield LeanRC::Promise.new (resolve, reject) ->
          job.run (err, item) -> if err? then reject err else resolve item
        completeJob = yield promise
        jobs = yield resque.completedJobs 'TEST_QUEUE_1'
        assert.lengthOf jobs, 1
        jobs = yield resque.completedJobs 'TEST_QUEUE_1', 'TEST_SCRIPT_2'
        assert.lengthOf jobs, 0
        yield return
  describe '#failedJobs', ->
    facade = null
    agenda = null
    queueNames = []
    KEY = 'TEST_AGENDA_RESQUE_MIXIN_015'
    after ->
      co ->
        yield clearTempQueues agenda, queueNames
        facade?.remove?()
        yield return
    it 'should list failed jobs', ->
      co ->
        facade = LeanRC::Facade.getInstance KEY
        trigger = new EventEmitter
        class Test extends LeanRC
          @inheritProtected()
          @include AgendaExtension
          @root "#{__dirname}/config/root"
          @initialize()
        class TestResque extends LeanRC::Resque
          @inheritProtected()
          @include Test::AgendaResqueMixin
          @module Test
          @initialize()
        configs = Test::Configuration.new Test::CONFIGURATION, Test::ROOT
        facade.registerProxy configs
        resque = TestResque.new 'TEST_AGENDA_RESQUE_MIXIN'
        facade.registerProxy resque
        agenda = yield resque.getAgenda()
        # agenda = yield resque[TestResque.instanceVariables['_agenda'].pointer]
        agenda.start()
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_1'), 250, trigger
        defineJob agenda, resque.fullQueueName('TEST_QUEUE_2'), 450, trigger
        { name } = yield resque.ensureQueue 'TEST_QUEUE_1', 1
        queueNames.push name
        { name } = yield resque.ensureQueue 'TEST_QUEUE_2', 1
        queueNames.push name
        DATA = data: 'data'
        DATE = new Date Date.now() + 600000
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_2', 'TEST_SCRIPT_1', DATA, DATE
        jobId = yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_1', DATA, DATE
        yield resque.pushJob 'TEST_QUEUE_1', 'TEST_SCRIPT_2', DATA, DATE
        job = yield resque.getJob 'TEST_QUEUE_1', jobId, native: yes
        job.fail new Error 'TEST_REASON'
        yield LeanRC::Promise.new (resolve, reject) ->
          job.save (err, item) -> if err? then reject err else resolve item
        jobs = yield resque.failedJobs 'TEST_QUEUE_1'
        assert.lengthOf jobs, 1
        jobs = yield resque.failedJobs 'TEST_QUEUE_1', 'TEST_SCRIPT_2'
        assert.lengthOf jobs, 0
        yield return
