assert = assert or require?('chai').assert

BackboneORM = window?.BackboneORM; try BackboneORM or= require?('backbone-orm') catch; try BackboneORM or= require?('../../../../backbone-orm')
_ = BackboneORM._; Backbone = BackboneORM.Backbone
Queue = BackboneORM.Queue
Utils = BackboneORM.Utils
ModelCache = BackboneORM.CacheSingletons.ModelCache
Fabricator = BackboneORM.Fabricator

option_sets = window?.__test__option_sets or require?('../../../option_sets')
parameters = __test__parameters if __test__parameters?
_.each option_sets, exports = (options) ->
  return if options.embed

  # As an alternative to using a global variable (which can be acceptable for testing only), move this code to a 'before' section,
  # and use `this.parent.test_parameters`, since `this` will be set to a testing context by mocha, and that can be shared
  options = _.extend({}, options, parameters) if parameters

  DATABASE_URL = options.database_url or ''
  BASE_SCHEMA = options.schema or {}
  SYNC = options.sync
  BASE_COUNT = 5

  runTest = (collection_type, done) ->
    model_type = collection_type::model

    queue = new Queue(1)
    queue.defer (callback) -> model_type.resetSchema(callback)
    queue.defer (callback) -> Fabricator.create(model_type, BASE_COUNT, {
      name: Fabricator.uniqueId('model_')
      created_at: Fabricator.date
      updated_at: Fabricator.date
    }, callback)
    queue.await (err) ->
      assert.ifError(err)
      collection = new collection_type()
      collection.fetch (err, fetched_collection) ->
        assert.ifError(err)
        assert.equal(BASE_COUNT, collection.models.length, "collection_type Expected: #{BASE_COUNT}\nActual: #{collection.models.length}")
        assert.equal(BASE_COUNT, fetched_collection.models.length, "Fetched collection_type Expected: #{BASE_COUNT}\nActual: #{fetched_collection.models.length}")
        done()

  class Model extends Backbone.Model
    urlRoot: "#{DATABASE_URL}/models"
    schema: BASE_SCHEMA
    sync: SYNC(Model)

  describe "Backbone.Collection #{options.$parameter_tags or ''}#{options.$tags}", ->
    options = _.extend({}, options, @parent.parameters) if @parent.parameters

    after (callback) ->
      queue = new Queue()
      queue.defer (callback) -> ModelCache.reset(callback)
      queue.defer (callback) -> Utils.resetSchemas [Model], callback
      queue.await callback

    beforeEach (callback) ->
      queue = new Queue(1)
      queue.defer (callback) -> ModelCache.configure({enabled: !!options.cache, max: 100}).reset(callback) # configure model cache
      queue.defer (callback) -> Utils.resetSchemas [Model], callback
      queue.await callback

    it 'fetch models using pre-configured model', (done) ->
      class Collection extends Backbone.Collection
        url: "#{DATABASE_URL}/models"
        schema: BASE_SCHEMA
        model: Model
        sync: SYNC(Collection)
      runTest Collection, done

    it 'fetch models using default model', (done) ->
      class Collection extends Backbone.Collection
        url: "#{DATABASE_URL}/models"
        schema: BASE_SCHEMA
        sync: SYNC(Collection)

      runTest Collection, done

    it 'fetch models using upgraded model', (done) ->
      class SomeModel extends Backbone.Model

      class Collection extends Backbone.Collection
        url: "#{DATABASE_URL}/models"
        model: SomeModel
        schema: BASE_SCHEMA
        sync: SYNC(Collection)

      runTest Collection, done

    it 'fetch models using upgraded model', (done) ->
      class Collection extends Backbone.Collection
        url: "#{DATABASE_URL}/models"
        model: Model
        schema: BASE_SCHEMA
        sync: SYNC(Collection)

      runTest Collection, done