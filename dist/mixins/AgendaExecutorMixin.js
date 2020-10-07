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
  var Agenda, EventEmitter, crypto, os;

  os = require('os');

  Agenda = require('agenda');

  EventEmitter = require('events');

  crypto = require('crypto');

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
    var ConfigurableMixin, FuncG, JOB_RESULT, Mediator, Mixin, NILL, NotificationInterface, PointerT, PromiseT, RESQUE, ResqueInterface, START_RESQUE, _, _agenda, co;
    ({
      NILL,
      JOB_RESULT,
      START_RESQUE,
      RESQUE,
      PromiseT,
      PointerT,
      FuncG,
      Mixin,
      ResqueInterface,
      NotificationInterface,
      Mediator,
      ConfigurableMixin,
      Utils: {_, co}
    } = Module.prototype);
    _agenda = null;
    return Module.defineMixin(Mixin('AgendaExecutorMixin', function(BaseClass = Mediator) {
      return (function() {
        var _Class, ipoAgenda, ipoResque;

        _Class = class extends BaseClass {};

        _Class.inheritProtected();

        _Class.include(ConfigurableMixin);

        _Class.public({
          fullQueueName: FuncG(String, String)
        }, {
          default: function(queueName) {
            return this[ipoResque].fullQueueName(queueName);
          }
        });

        ipoAgenda = PointerT(_Class.private({
          agenda: PromiseT
        }, {
          get: function() {
            return Module.prototype.Promise.resolve(_agenda);
          }
        }));

        ipoResque = PointerT(_Class.private({
          resque: ResqueInterface
        }));

        _Class.public({
          listNotificationInterests: FuncG([], Array)
        }, {
          default: function() {
            return [JOB_RESULT, START_RESQUE];
          }
        });

        _Class.public({
          handleNotification: FuncG(NotificationInterface)
        }, {
          default: function(aoNotification) {
            var voBody, vsName, vsType;
            vsName = aoNotification.getName();
            voBody = aoNotification.getBody();
            vsType = aoNotification.getType();
            switch (vsName) {
              case JOB_RESULT:
                this.getViewComponent().emit(vsType, voBody);
                break;
              case START_RESQUE:
                this.start();
            }
          }
        });

        _Class.public({
          onRegister: Function
        }, {
          default: function(...args) {
            var address, collection, name, self;
            this.super(...args);
            ({
              address,
              jobsCollection: collection
            } = this.configs.agenda);
            this.setViewComponent(new EventEmitter());
            this[ipoResque] = this.facade.retrieveProxy(RESQUE);
            name = `${os.hostname()}-${process.pid}`;
            self = this;
            _agenda = Module.prototype.Promise.new(function(resolve, reject) {
              var voAgenda;
              voAgenda = new Agenda().database(address, collection != null ? collection : 'delayedJobs').name(name).maxConcurrency(16).defaultConcurrency(16).lockLimit(16).defaultLockLimit(16).defaultLockLifetime(30 * 60 * 1000);
              voAgenda.on('ready', co.wrap(function*() {
                yield self.ensureIndexes(voAgenda);
                yield self.defineProcessors(voAgenda);
                resolve(voAgenda);
              }));
              voAgenda.on('error', function(err) {
                return reject(err);
              });
            });
          }
        });

        _Class.public({
          ensureIndexes: FuncG([Object], PromiseT)
        }, {
          default: function(aoAgenda) {
            var queuesCollection;
            if (aoAgenda == null) {
              aoAgenda = _agenda;
            }
            ({queuesCollection} = this.configs.agenda);
            return co(function*() {
              var voAgenda, voQueuesCollection;
              voAgenda = (yield aoAgenda);
              voQueuesCollection = voAgenda._mdb.collection(queuesCollection != null ? queuesCollection : 'delayedQueues');
              yield voQueuesCollection.createIndex('name');
            });
          }
        });

        _Class.public(_Class.async({
          defineProcessors: FuncG([Object])
        }, {
          default: function*(aoAgenda) {
            var concurrency, executor, i, len, moduleName, name, ref, voAgenda;
            executor = this;
            voAgenda = (yield (aoAgenda != null ? aoAgenda : _agenda));
            ref = (yield this[ipoResque].allQueues());
            for (i = 0, len = ref.length; i < len; i++) {
              ({name, concurrency} = ref[i]);
              [moduleName] = name.split('|>');
              if (moduleName === this.moduleName()) {
                voAgenda.define(name, {concurrency}, function(job, done) {
                  return job.touch(function(err = null) {
                    var data, interval, reverse, scriptName;
                    if (err != null) {
                      done(err);
                      return;
                    }
                    interval = setInterval((function() {
                      return job.touch();
                    }), 5000);
                    reverse = crypto.randomBytes(32).toString('hex');
                    executor.getViewComponent().once(reverse, function({error = null}) {
                      clearInterval(interval);
                      return done(error);
                    });
                    ({scriptName, data} = job.attrs.data);
                    executor.sendNotification(scriptName, data, reverse);
                  });
                });
              }
              continue;
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
          onRemove: Function
        }, {
          default: function*(...args) {
            this.super(...args);
            yield this.stop();
          }
        }));

        _Class.public(_Class.async({
          start: Function
        }, {
          default: function*() {
            ((yield _agenda)).start();
          }
        }));

        _Class.public(_Class.async({
          stop: Function
        }, {
          default: function*() {
            var agenda;
            agenda = (yield _agenda);
            yield Module.prototype.Promise.new(function(resolve, reject) {
              agenda.stop(function(err) {
                if (err != null) {
                  reject(err);
                } else {
                  resolve();
                }
              });
            });
          }
        }));

        _Class.initializeMixin();

        return _Class;

      }).call(this);
    }));
  };

}).call(this);
