util = require 'util'
_ = require 'underscore'
Backbone = require 'backbone'

MemoryCursor = require './lib/memory_cursor'
Schema = require './lib/schema'
Utils = require './lib/utils'

STORES = {}

# Backbone Sync for in-memory models.
#
# @example How to configure using a model name
#   class Thing extends Backbone.Model
#     @model_name: 'Thing'
#     sync: require('backbone-orm/memory_sync')(Thing)
#
# @example How to configure using a url
#   class Thing extends Backbone.Model
#     url: '/things'
#     sync: require('backbone-orm/memory_sync')(Thing)
#
class MemorySync
  # @private
  constructor: (@model_type) ->
    @model_type.model_name = Utils.findOrGenerateModelName(@model_type)
    @schema = new Schema(@model_type)
    @store = @model_type.store = STORES[@model_type.model_name] or= {}

  # @private
  initialize: ->
    return if @is_initialized; @is_initialized = true
    @schema.initialize()

  # @private
  read: (model, options) ->
    options.success(if model.models then (json for id, json of @store) else @store[model.id])

  # @private
  create: (model, options) ->
    model.set(id: Utils.guid())
    model_json = @store[model.id] = model.toJSON()
    options.success(_.clone(model_json))

  # @private
  update: (model, options) ->
    return @create(model, options) unless model_json = @store[model.id] # if bootstrapped, it may not yet be in the store
    @store[model.id] = model_json = model.toJSON()
    options.success(_.clone(model_json))

  # @private
  delete: (model, options) ->
    return options.error(new Error('Model not found')) unless model_json = @store[model.id]

    # destroy backlinks

    delete @store[model.id]
    options.success()

  ###################################
  # Backbone ORM - Class Extensions
  ###################################

  # @private
  resetSchema: (options, callback) -> delete @store[key] for key of @store; callback()

  # @private
  cursor: (query={}) -> return new MemoryCursor(query, _.pick(@, ['model_type', 'store']))

  # @private
  destroy: (query, callback) ->
    unless (keys = _.keys(query)).length
      # destroy backlinks
     return @resetSchema({}, callback)

    else
      # destroy specific records
      for id, model_json of @store
        # destroy backlinks
        delete @store[id] if _.isEqual(_.pick(model_json, keys), query)
      callback()

module.exports = (type) ->
  if (new type()) instanceof Backbone.Collection # collection
    model_type = Utils.configureCollectionModelType(type, module.exports)
    return type::sync = model_type::sync

  sync = new MemorySync(type)
  type::sync = sync_fn = (method, model, options={}) -> # save for access by model extensions
    sync.initialize()
    return module.exports.apply(null, Array::slice.call(arguments, 1)) if method is 'createSync' # create a new sync
    return sync if method is 'sync'
    return false if method is 'isRemote'
    return sync.schema if method is 'schema'
    return if sync[method] then sync[method].apply(sync, Array::slice.call(arguments, 1)) else undefined

  require('./lib/model_extensions')(type)
  return require('./lib/cache').configureSync(type, sync_fn)
