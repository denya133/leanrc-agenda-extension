# This file is part of leanrc-agenda-extension.
#
# leanrc-agenda-extension is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# leanrc-agenda-extension is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with leanrc-agenda-extension.  If not, see <https://www.gnu.org/licenses/>.

LeanRC = require 'LeanRC'

###
Example of use

```coffee
LeanRC = require 'LeanRC'
AgendaExtension = require 'leanrc-agenda-extension'

class TestApp extends LeanRC
  @inheritProtected()
  @include AgendaExtension

  @const ANIMATE_ROBOT: Symbol 'animateRobot'
  @const ROBOT_SPEAKING: Symbol 'robotSpeaking'

  require('./controller/command/StartupCommand') TestApp
  require('./controller/command/PrepareControllerCommand') TestApp
  require('./controller/command/PrepareViewCommand') TestApp
  require('./controller/command/PrepareModelCommand') TestApp
  require('./controller/command/AnimateRobotCommand') TestApp

  require('./view/component/ConsoleComponent') TestApp
  require('./view/mediator/ConsoleComponentMediator') TestApp

  require('./model/proxy/RobotDataProxy') TestApp

  require('./AppFacade') TestApp


module.exports = TestApp.initialize().freeze()
```
###

Extension = (BaseClass) ->
  class extends BaseClass
    @inheritProtected()

    require('./mixins/AgendaResqueMixin') @Module
    require('./mixins/AgendaExecutorMixin') @Module
    @initializeMixin()

Reflect.defineProperty Extension, 'name',
  value: 'AgendaExtension'


module.exports = Extension
