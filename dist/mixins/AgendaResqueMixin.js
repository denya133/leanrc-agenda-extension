(function() {
  // This file is part of leanrc-agenda-extension.

  // leanrc-agenda-extension is free software: you can redistribute it and/or modify
  // it under the terms of the GNU Lesser General Public License as published by
  // the Free Software Foundation, either version 3 of the License, or
  // (at your option) any later version.

  // leanrc-agenda-extension is distributed in the hope that it will be useful,
  // but WITHOUT ANY WARRANTY; without even the implied warranty of
  // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  // GNU Lesser General Public License for more details.

  // You should have received a copy of the GNU Lesser General Public License
  // along with leanrc-agenda-extension.  If not, see <https://www.gnu.org/licenses/>.
  var Agenda, MongoClient, ObjectID, os;

  os = require('os');

  Agenda = require('agenda');

  ({MongoClient, ObjectID} = require('mongodb'));

  /*
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
   */
  module.exports = function(Module) {
    var AnyT, ConfigurableMixin, FuncG, ListG, MaybeG, Mixin, PointerT, PromiseT, Resque, StructG, UnionG, _, _agenda, _connection, _consumers, co;
    ({
      AnyT,
      PointerT,
      PromiseT,
      FuncG,
      ListG,
      StructG,
      MaybeG,
      UnionG,
      Mixin,
      Resque,
      ConfigurableMixin,
      Utils: {_, co}
    } = Module.prototype);
    _connection = null;
    _consumers = null;
    _agenda = null;
    return Module.defineMixin(Mixin('AgendaResqueMixin', function(BaseClass = Resque) {
      return (function() {
        var _Class, ipoAgenda;

        _Class = class extends BaseClass {};

        _Class.inheritProtected();

        _Class.include(ConfigurableMixin);

        ipoAgenda = PointerT(_Class.private({
          agenda: PromiseT
        }, {
          get: function() {
            return Module.prototype.Promise.resolve(_agenda);
          }
        }));

        _Class.public({
          connection: PromiseT
        }, {
          get: function() {
            var self;
            self = this;
            if (_connection == null) {
              _connection = co(function*() {
                var address, collection, credentials, name;
                credentials = '';
                ({
                  address,
                  jobsCollection: collection
                } = self.configs.agenda);
                name = `${os.hostname()}-${process.pid}`;
                return (yield Module.prototype.Promise.new(function(resolve, reject) {
                  var connection;
                  connection = null;
                  _agenda = Module.prototype.Promise.new(function(resolveAgenda, rejectAgenda) {
                    MongoClient.connect(address).then(function(conn) {
                      var voAgenda;
                      connection = conn;
                      voAgenda = new Agenda().mongo(connection, collection != null ? collection : 'delayedJobs').name(name).maxConcurrency(16).defaultConcurrency(16).lockLimit(16).defaultLockLimit(16).defaultLockLifetime(5000);
                      voAgenda.on('ready', function() {
                        return resolveAgenda(voAgenda);
                      });
                      voAgenda.on('error', function(err) {
                        return rejectAgenda(err);
                      });
                    });
                  });
                  _agenda.then(function() {
                    return resolve(connection);
                  }).catch(function(err) {
                    return reject(err);
                  });
                }));
              });
            }
            return _connection;
          }
        });

        _Class.public({
          onRegister: Function
        }, {
          default: function(...args) {
            this.super(...args);
            (() => {
              return this.connection;
            })();
            if (_consumers == null) {
              _consumers = 0;
            }
            _consumers++;
          }
        });

        _Class.public(_Class.async({
          onRemove: Function
        }, {
          default: function*(...args) {
            var connection;
            this.super(...args);
            _consumers--;
            if (_consumers === 0) {
              connection = (yield _connection);
              yield connection.close(true);
              _connection = void 0;
            }
          }
        }));

        _Class.public(_Class.async({
          getAgenda: FuncG([], Object)
        }, {
          default: function*() {
            return (yield _agenda);
          }
        }));

        _Class.public(_Class.async({
          ensureQueue: FuncG([String, MaybeG(Number)], StructG({
            name: String,
            concurrency: Number
          }))
        }, {
          default: function*(name, concurrency = 1) {
            var queue, queuesCollection, voQueuesCollection;
            name = this.fullQueueName(name);
            ({queuesCollection} = this.configs.agenda);
            voQueuesCollection = ((yield _agenda))._mdb.collection(queuesCollection != null ? queuesCollection : 'delayedQueues');
            if ((queue = (yield voQueuesCollection.findOne({
              name: name
            }))) != null) {
              queue.concurrency = concurrency;
              yield voQueuesCollection.updateOne({name}, queue);
            } else {
              yield voQueuesCollection.insertOne({name, concurrency});
            }
            return {name, concurrency};
          }
        }));

        _Class.public(_Class.async({
          getQueue: FuncG(String, MaybeG(StructG({
            name: String,
            concurrency: Number
          })))
        }, {
          default: function*(name) {
            var concurrency, queue, queuesCollection, voQueuesCollection;
            name = this.fullQueueName(name);
            ({queuesCollection} = this.configs.agenda);
            voQueuesCollection = ((yield _agenda))._mdb.collection(queuesCollection != null ? queuesCollection : 'delayedQueues');
            if ((queue = (yield voQueuesCollection.findOne({
              name: name
            }))) != null) {
              ({concurrency} = queue);
              return {name, concurrency};
            } else {

            }
          }
        }));

        _Class.public(_Class.async({
          removeQueue: FuncG(String)
        }, {
          default: function*(queueName) {
            var queuesCollection, voQueuesCollection;
            queueName = this.fullQueueName(queueName);
            ({queuesCollection} = this.configs.agenda);
            voQueuesCollection = ((yield _agenda))._mdb.collection(queuesCollection != null ? queuesCollection : 'delayedQueues');
            yield voQueuesCollection.deleteOne({
              name: queueName
            });
          }
        }));

        _Class.public(_Class.async({
          allQueues: FuncG([], ListG(StructG({
            name: String,
            concurrency: Number
          })))
        }, {
          default: function*() {
            var queues, queuesCollection, voQueuesCollection;
            ({queuesCollection} = this.configs.agenda);
            voQueuesCollection = ((yield _agenda))._mdb.collection(queuesCollection != null ? queuesCollection : 'delayedQueues');
            queues = (yield voQueuesCollection.find({}));
            queues = (yield queues.toArray());
            queues = queues.map(function({name, concurrency}) {
              return {name, concurrency};
            });
            return queues;
          }
        }));

        _Class.public(_Class.async({
          pushJob: FuncG([String, String, AnyT, MaybeG(Number)], UnionG(String, Number))
        }, {
          default: function*(queueName, scriptName, data, delayUntil) {
            var createJob, voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            createJob = function(name, data, {delayUntil}, cb) {
              if (delayUntil != null) {
                return voAgenda.schedule(delayUntil, name, data, cb);
              } else {
                return voAgenda.now(name, data, cb);
              }
            };
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var job;
              job = createJob(queueName, {scriptName, data}, {delayUntil}, function(err) {
                if (err != null) {
                  return reject(err);
                } else {
                  return resolve(String(job.attrs._id));
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          getJob: FuncG([String, UnionG(String, Number)], MaybeG(Object))
        }, {
          default: function*(queueName, jobId, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              return voAgenda.jobs({
                name: queueName,
                _id: ObjectID(jobId)
              }, function(err, [job] = []) {
                if (err) {
                  return reject(err);
                } else {
                  return resolve(job != null ? options.native ? job : job.attrs : null);
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          deleteJob: FuncG([String, UnionG(String, Number)], Boolean)
        }, {
          default: function*(queueName, jobId) {
            var isDeleted, job;
            isDeleted = false;
            job = (yield this.getJob(queueName, jobId, {
              native: true
            }));
            if (job != null) {
              yield Module.prototype.Promise.new(function(resolve, reject) {
                return job.remove(function(err) {
                  if (err != null) {
                    return reject(err);
                  } else {
                    return resolve();
                  }
                });
              });
              isDeleted = true;
            }
            return isDeleted;
          }
        }));

        _Class.public(_Class.async({
          abortJob: FuncG([String, UnionG(String, Number)])
        }, {
          default: function*(queueName, jobId) {
            var job;
            job = (yield this.getJob(queueName, jobId, {
              native: true
            }));
            if ((job != null) && (job.attrs.failReason == null) && (job.attrs.failedAt == null)) {
              yield Module.prototype.Promise.new(function(resolve, reject) {
                job.fail(new Error('Job has been aborted'));
                return job.save(function(err) {
                  if (err != null) {
                    return reject(err);
                  } else {
                    return resolve();
                  }
                });
              });
            }
          }
        }));

        _Class.public(_Class.async({
          allJobs: FuncG([String, MaybeG(String)], ListG(Object))
        }, {
          default: function*(queueName, scriptName, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var vhQuery;
              vhQuery = {
                name: queueName
              };
              if (scriptName != null) {
                vhQuery['data.scriptName'] = scriptName;
              }
              return voAgenda.jobs(vhQuery, function(err, jobs) {
                if (err != null) {
                  return reject(err);
                } else {
                  if (!options.native) {
                    jobs = jobs.map(function(job) {
                      return job.attrs;
                    });
                  }
                  return resolve(jobs != null ? jobs : []);
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          pendingJobs: FuncG([String, MaybeG(String)], ListG(Object))
        }, {
          default: function*(queueName, scriptName, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var vhQuery;
              vhQuery = {
                name: queueName,
                lastRunAt: {
                  $exists: false
                },
                lastFinishedAt: {
                  $exists: false
                },
                failedAt: {
                  $exists: false
                }
              };
              if (scriptName != null) {
                vhQuery['data.scriptName'] = scriptName;
              }
              return voAgenda.jobs(vhQuery, function(err, jobs) {
                if (err) {
                  return reject(err);
                } else {
                  if (!options.native) {
                    jobs = jobs.map(function(job) {
                      return job.attrs;
                    });
                  }
                  return resolve(jobs != null ? jobs : []);
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          progressJobs: FuncG([String, MaybeG(String)], ListG(Object))
        }, {
          default: function*(queueName, scriptName, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var vhQuery;
              vhQuery = {
                name: queueName,
                lastRunAt: {
                  $exists: true
                },
                lastFinishedAt: {
                  $exists: false
                },
                failedAt: {
                  $exists: false
                }
              };
              if (scriptName != null) {
                vhQuery['data.scriptName'] = scriptName;
              }
              return voAgenda.jobs(vhQuery, function(err, jobs) {
                if (err) {
                  return reject(err);
                } else {
                  if (!options.native) {
                    jobs = jobs.map(function(job) {
                      return job.attrs;
                    });
                  }
                  return resolve(jobs != null ? jobs : []);
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          completedJobs: FuncG([String, MaybeG(String)], ListG(Object))
        }, {
          default: function*(queueName, scriptName, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var vhQuery;
              vhQuery = {
                name: queueName,
                lastRunAt: {
                  $exists: true
                },
                lastFinishedAt: {
                  $exists: true
                },
                failedAt: {
                  $exists: false
                }
              };
              if (scriptName != null) {
                vhQuery['data.scriptName'] = scriptName;
              }
              return voAgenda.jobs(vhQuery, function(err, jobs) {
                if (err) {
                  return reject(err);
                } else {
                  if (!options.native) {
                    jobs = jobs.map(function(job) {
                      return job.attrs;
                    });
                  }
                  return resolve(jobs != null ? jobs : []);
                }
              });
            }));
          }
        }));

        _Class.public(_Class.async({
          failedJobs: FuncG([String, MaybeG(String)], ListG(Object))
        }, {
          default: function*(queueName, scriptName, options = {}) {
            var voAgenda;
            queueName = this.fullQueueName(queueName);
            voAgenda = (yield _agenda);
            return (yield Module.prototype.Promise.new(function(resolve, reject) {
              var vhQuery;
              vhQuery = {
                name: queueName,
                failedAt: {
                  $exists: true
                }
              };
              if (scriptName != null) {
                vhQuery['data.scriptName'] = scriptName;
              }
              return voAgenda.jobs(vhQuery, function(err, jobs) {
                if (err) {
                  return reject(err);
                } else {
                  if (!options.native) {
                    jobs = jobs.map(function(job) {
                      return job.attrs;
                    });
                  }
                  return resolve(jobs != null ? jobs : []);
                }
              });
            }));
          }
        }));

        _Class.initializeMixin();

        return _Class;

      }).call(this);
    }));
  };

}).call(this);
