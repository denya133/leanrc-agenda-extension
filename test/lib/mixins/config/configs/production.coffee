module.exports =
  port:
    description: 'port'
    type: 'number'
    default: 8888
  test4:
    description: 'test4 test'
    type: 'string'
    default: 'test'
  apiKey:
    description: 'API key'
    type: 'string'
    default: 'TESTTESTTESTTESTTEST123'
  sessionCookie:
    description: 'session cookie name'
    type: 'string'
    default: 'sid'
  agenda:
    description: "Configs for agenda"
    type: "json"
    default: "{\"address\":\"mongodb://localhost:27017/resqueDB\",\"jobsCollection\":\"delayedJobs\",\"queuesCollection\":\"delayedQueues\"}"
  # dbAddress:
  #   description: 'Agenda database address'
  #   type: 'string'
  #   default: '127.0.0.1'
  # jobsCollection:
  #   description: 'Agenda database collection'
  #   type: 'string'
  #   default: 'delayedJobs'
  # queuesCollection:
  #   description: 'Agenda database queues collection'
  #   type: 'string'
  #   default: 'delayedQueues'
