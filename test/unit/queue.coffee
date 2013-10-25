assert = require 'assert'

Queue = require '../../lib/queue'
_ = require 'underscore'

runTests = (options, callback) ->

  describe 'Queue', ->

    before (done) -> return done() unless options.before; options.before([], done)
    after (done) -> callback(); done()

    it 'infinite parallelism', (done) ->
      queue = new Queue()

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(!err, "No errors: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '3.0', '1.1', '2.1', '3.1'])
        done()

    it 'infinite parallelism (errors 1)', (done) ->
      queue = new Queue()

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback(new Error('error'))), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '3.0', '1.1'])
        done()

    it 'infinite parallelism (errors 2)', (done) ->
      queue = new Queue()

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback(new Error('error'))), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '3.0', '1.1', '2.1'])
        done()

    it 'parallelism 1', (done) ->
      queue = new Queue(1)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(!err, "No errors: #{err}")
        assert.deepEqual(results, ['1.0', '1.1', '2.0', '2.1', '3.0', '3.1'])
        done()

    it 'parallelism 1 (errors 1)', (done) ->
      queue = new Queue(1)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback(new Error('error'))), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '1.1'])
        done()

    it 'parallelism 1 (errors 2)', (done) ->
      queue = new Queue(1)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback(new Error('error'))), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '1.1', '2.0', '2.1'])
        done()

    it 'parallelism 2', (done) ->
      queue = new Queue(2)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(!err, "No errors: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '1.1', '3.0', '2.1', '3.1'])
        done()

    it 'parallelism 2 (errors 1)', (done) ->
      queue = new Queue(2)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback(new Error('error'))), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback()), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '1.1'])
        done()

    it 'parallelism 2 (errors 2)', (done) ->
      queue = new Queue(2)

      results = []
      queue.defer (callback) -> results.push('1.0'); _.delay (-> results.push('1.1'); callback()), 1*10
      queue.defer (callback) -> results.push('2.0'); _.delay (-> results.push('2.1'); callback(new Error('error'))), 2*10
      queue.defer (callback) -> results.push('3.0'); _.delay (-> results.push('3.1'); callback()), 3*10
      queue.await (err) ->
        assert.ok(err, "Has error: #{err}")
        assert.deepEqual(results, ['1.0', '2.0', '1.1', '3.0', '2.1'])
        done()

module.exports = (options, callback) ->
  runTests(options, callback)
