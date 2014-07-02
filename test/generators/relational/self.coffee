assert = assert or require?('chai').assert

BackboneORM = window?.BackboneORM or require?('backbone-orm')
_ = BackboneORM._; Backbone = BackboneORM.Backbone
Queue = BackboneORM.Queue
ModelCache = BackboneORM.CacheSingletons.ModelCache
Utils = BackboneORM.Utils
JSONUtils = BackboneORM.JSONUtils
Fabricator = BackboneORM.Fabricator

module.exports = (options, callback) ->
  DATABASE_URL = options.database_url or ''
  BASE_SCHEMA = options.schema or {}
  SYNC = options.sync
  BASE_COUNT = 5

  ModelCache.configure({enabled: !!options.cache, max: 100}).hardReset() # configure model cache

  OMIT_KEYS = ['owner_id', '_rev', 'created_at', 'updated_at']

  class SelfReference extends Backbone.Model
    urlRoot: "#{DATABASE_URL}/self_references"
    schema: _.defaults({
      owner: -> ['belongsTo', SelfReference, foreign_key: 'owner_id', as: 'self_references']
      self_references: -> ['hasMany', SelfReference, as: 'owner']
    }, BASE_SCHEMA)
    sync: SYNC(SelfReference)

  describe "self model relations (cache: #{options.cache}, query_cache: #{options.query_cache}, embed: #{options.embed})", ->

    before (done) -> return done() unless options.before; options.before([SelfReference], done)
    after (done) -> callback(); done()
    beforeEach (done) ->
      MODELS = {}

      queue = new Queue(1)

      # reset caches
      queue.defer (callback) -> ModelCache.configure({enabled: !!options.cache, max: 100}).reset(callback) # configure model cache

      # destroy all
      queue.defer (callback) -> Utils.resetSchemas [SelfReference], callback

      # create all
      queue.defer (callback) ->
        create_queue = new Queue()

        create_queue.defer (callback) -> Fabricator.create(SelfReference, BASE_COUNT, {
          name: Fabricator.uniqueId('self_reference_')
          created_at: Fabricator.date
          is_base: true
        }, (err, models) -> MODELS.self_references = models; callback(err))
        create_queue.defer (callback) -> Fabricator.create(SelfReference, BASE_COUNT, {
          name: Fabricator.uniqueId('self_reference_target_')
          created_at: Fabricator.date
        }, (err, models) -> MODELS.self_reference_targets = models; callback(err))
        create_queue.defer (callback) -> Fabricator.create(SelfReference, BASE_COUNT, {
          name: Fabricator.uniqueId('self_reference_inverse_')
          created_at: Fabricator.date
        }, (err, models) -> MODELS.self_reference_inverses = models; callback(err))

        create_queue.await callback

      # link and save all
      queue.defer (callback) ->
        save_queue = new Queue()

        for self_reference in MODELS.self_references
          do (self_reference) ->
            save_queue.defer (callback) ->
              self_reference_inverse = MODELS.self_reference_inverses.pop()
              self_reference_inverse.set({
                owner: self_reference
              })
              self_reference_inverse.save callback
            save_queue.defer (callback) ->
              self_references = self_reference.get('self_references') or []
              self_references.push MODELS.self_reference_targets.pop()
              self_reference.set({
                self_references: self_references
              })
              self_reference.save callback

        save_queue.await callback

      queue.await done

    it 'Can create a model and update the relationship (self reference, belongsTo)', (done) ->
      related_key = 'self_references'
      related_id_accessor = 'self_reference_ids'

      SelfReference.cursor({$one: true, is_base: true}).include(related_key).toModels (err, owner) ->
        assert.ok(!err, "No errors: #{err}")
        assert.ok(owner, 'found model')
        owner_id = owner.id
        relateds = owner.get(related_key).models
        related_ids = (related.id for related in relateds)
        assert.equal(2, relateds.length, "Loaded relateds. Expected: #{2}. Actual: #{relateds.length}")
        assert.ok(!_.difference(related_ids, owner.get(related_id_accessor)).length, "Got related_id from previous related. Expected: #{related_ids}. Actual: #{owner.get(related_id_accessor)}")

        (attributes = {})[related_key] = relateds
        new_owner = new SelfReference(attributes)
        owner1 = null; new_owner1 = null; new_owner_id = null

        assert.equal(0, owner.get(related_key).models.length, "Loaded related from previous related. Expected: #{0}. Actual: #{owner.get(related_key).models.length}")
        assert.equal(0, owner.get(related_id_accessor).length, "Loaded related from previous related. Expected: #{0}. Actual: #{owner.get(related_id_accessor).length}")
        assert.ok(!_.difference(related_ids, (related.id for related in new_owner.get(related_key).models)).length, "Loaded related from previous related. Expected: #{related_ids}. Actual: #{(related.id for related in new_owner.get(related_key).models)}")
        assert.ok(!_.difference(related_ids, new_owner.get(related_id_accessor)).length, "Got related_id from copied related. Expected: #{related_ids}. Actual: #{new_owner.get(related_id_accessor)}")

        queue = new Queue(1)
        queue.defer (callback) -> new_owner.save callback
        queue.defer (callback) -> owner.save callback

        # make sure nothing changed after save
        queue.defer (callback) ->
          new_owner_id = new_owner.id
          assert.ok(new_owner_id, 'had an id after after')

          assert.equal(0, owner.get(related_key).models.length, "Loaded related from previous related. Expected: #{0}. Actual: #{owner.get(related_key).models.length}")
          assert.equal(0, owner.get(related_id_accessor).length, "Loaded related from previous related. Expected: #{0}. Actual: #{owner.get(related_id_accessor).length}")
          assert.ok(!_.difference(related_ids, (related.id for related in new_owner.get(related_key).models)).length, "Loaded related from previous related. Expected: #{related_ids}. Actual: #{(related.id for related in new_owner.get(related_key).models)}")
          assert.ok(!_.difference(related_ids, new_owner.get(related_id_accessor)).length, "Got related_id from copied related. Expected: #{related_ids}. Actual: #{new_owner.get(related_id_accessor)}")
          callback()

        # load
        queue.defer (callback) -> SelfReference.find owner_id, (err, _owner) -> callback(err, owner1 = _owner)
        queue.defer (callback) -> SelfReference.find new_owner_id, (err, _owner) -> callback(err, new_owner1 = _owner)

        # check
        queue.defer (callback) ->

          owner1.get related_key, (err, relateds) ->
            assert.ok(!err, "No errors: #{err}")
            assert.equal(0, relateds.length, "Loaded related from previous related. Expected: #{0}. Actual: #{relateds.length}")
            assert.equal(0, owner.get(related_id_accessor).length, "Loaded related from previous related. Expected: #{0}. Actual: #{owner.get(related_id_accessor).length}")

            new_owner1.get related_key, (err, relateds) ->
              assert.ok(!err, "No errors: #{err}")
              assert.ok(!_.difference(related_ids, (related.id for related in relateds)).length, "Loaded related from previous related. Expected: #{related_ids}. Actual: #{(related.id for related in relateds)}")
              assert.ok(!_.difference(related_ids, new_owner1.get(related_id_accessor)).length, "Got related_id from reloaded previous related. Expected: #{related_ids}. Actual: #{new_owner1.get(related_id_accessor)}")
              callback()

        queue.await done
