###
  backbone-orm.js 0.0.1
  Copyright (c) 2013 Vidigami - https://github.com/vidigami/backbone-orm
  License: MIT (http://www.opensource.org/licenses/mit-license.php)
  Dependencies: Backbone.js and Underscore.js.
###

URL = require '../node/url'
DatabaseURL = require './database_url'
Backbone = require 'backbone'
_ = require 'underscore'
inflection = require 'inflection'
moment = require 'moment'
Queue = require './queue'

S4 = -> (((1+Math.random())*0x10000)|0).toString(16).substring(1)

BATCH_DEFAULT_LIMIT = 1500
BATCH_DEFAULT_PARALLELISM = 1

INTERVAL_TYPES = ['milliseconds', 'seconds', 'minutes', 'hours', 'days', 'weeks', 'months', 'years']


module.exports = class Utils
  @bbCallback: (callback) -> return {success: ((model, resp, options) -> callback(null, model, resp, options)), error: ((model, resp, options) -> callback(resp or new Error('Backbone call failed'), model, resp, options))}
  @wrapOptions: (options={}, callback) ->
    options = Utils.bbCallback(options) if _.isFunction(options) # node style callback
    return _.defaults(Utils.bbCallback((err, model, resp, modified_options) -> callback(err, model, resp, options)), options)

  # use signatures as a check in case multiple versions of Backbone have been included
  @isModel: (obj) -> return obj and obj.attributes and ((obj instanceof Backbone.Model) or (obj.parse and obj.fetch))
  @isCollection: (obj) -> return obj and obj.models and ((obj instanceof Backbone.Collection) or (obj.reset and obj.fetch))

  @deepClone: (obj) ->
    return obj if not obj or (typeof obj isnt 'object')
    return String::slice.call(obj) if _.isString(obj)
    return new Date(obj.valueOf()) if _.isDate(obj)
    return (Utils.deepClone(item) for item in obj) if _.isArray(obj)
    if _.isObject(obj) and obj.constructor is {}.constructor # simple object
      result = {}
      result[key] = Utils.deepClone(value) for key, value of obj
      return result
    return obj

  # @private
  @guid = -> return (S4()+S4()+"-"+S4()+"-"+S4()+"-"+S4()+"-"+S4()+S4()+S4())

  @get: (model, key, default_value) ->
    model._orm or= {}
    return if model._orm.hasOwnProperty(key) then model._orm[key] else default_value

  @set: (model, key, value) ->
    model._orm or= {}
    model._orm[key] = value
    return model._orm[key]

  @orSet: (model, key, value) ->
    model._orm or= {}
    model._orm[key] = value unless model._orm.hasOwnProperty(key)
    return model._orm[key]

  @unset: (model, key) ->
    model._orm or= {}
    delete model._orm[key]

  ##############################
  # ModelType
  ##############################
  @findOrGenerateModelName: (model_type) ->
    return model_type.model_name if model_type.model_name
    if url = _.result(model_type.prototype, 'url')
      return model_name if model_name = (new DatabaseURL(url)).modelName()
    return model_type.name if model_type.name
    throw "Could not find or generate model name for #{model_type}"

  @configureCollectionModelType: (type, sync) ->
    modelURL = ->
      url = _.result(@collection or type::, 'url')
      unless @isNew()
        url_parts = URL.parse(url)
        url_parts.pathname = "#{url_parts.pathname}/encodeURIComponent(@id)"
        url = URL.format(url_parts)
      return url

    model_type = type::model
    if not model_type or (model_type is Backbone.Model)
      class ORMModel extends Backbone.Model
        url: modelURL
        sync: sync(ORMModel)
      return type::model = ORMModel
    else if model_type::sync is Backbone.Model::sync # override built-in backbone sync
      model_type::url = modelURL
      model_type::sync = sync(model_type)
    return model_type

  @patchRemoveByJSON: (model_type, model_json, callback) ->
    return callback() unless schema = model_type.schema()
    queue = new Queue(1)
    for key, relation in schema
      do (relation) -> queue.defer (callback) -> relation.patchRemove(model_json, callback)
    queue.await callback

  @presaveBelongsToRelationships: (model, callback) ->
    return callback() if not model.schema
    queue = new Queue(1)
    schema = model.schema()

    for key, relation of schema.relations
      continue if relation.type isnt 'belongsTo' or relation.isVirtual() or not (value = model.get(key))
      related_models = if value.models then value.models else [value]
      for related_model in related_models
        continue if related_model.id # belongsTo require an id
        do (related_model) => queue.defer (callback) => related_model.save {}, Utils.bbCallback callback

    queue.await callback

  ##############################
  # Data to Model Helpers
  ##############################

  # @private
  @dataId: (data) -> return if _.isObject(data) then data.id else data

  @dataIsSameModel: (data1, data2) ->
    return Utils.dataId(data1) is Utils.dataId(data2) if Utils.dataId(data1) or Utils.dataId(data2)
    return _.isEqual(data1, data2)

  # @private
  @dataToModel: (data, model_type) ->
    return null unless data
    return (Utils.dataToModel(item, model_type) for item in data) if _.isArray(data)
    if Utils.isModel(data)
      model = data
    else if Utils.dataId(data) isnt data
      model = new model_type(model_type::parse(data))
    else
      model = new model_type({id: data})
      model.setLoaded(false)

    return model

  @updateModel: (model, data) ->
    return model if not data or (model is data) or data._orm_needs_load
    data = data.toJSON() if Utils.isModel(data)
    if Utils.dataId(data) isnt data
      model.setLoaded(true)
      model.set(data)

      # TODO: handle partial models
      # schema = model.schema()
      # for key of model.attributes
      #   continue unless _.isUndefined(data[key])
      #   if schema and relation = schema.relation(key)
      #     model.unset(key) if relation.type is 'belongsTo' and _.isUndefined(data[relation.virtual_id_accessor]) # unset removed keys
      #   else
      #     model.unset(key)
    return model

  @updateOrNew: (data, model_type) ->
    if (cache = model_type.cache) and (id = Utils.dataId(data))
      Utils.updateModel(model, data) if model = cache.get(id)
    unless model
      model = if Utils.isModel(data) then data else Utils.dataToModel(data, model_type)
      cache.set(model.id, model) if model and cache
    return model

  @modelJSONSave: (model_json, model_type, callback) ->
    model = new Backbone.Model(model_json)
    model._orm_never_cache = true
    model.urlRoot = =>
      try url = _.result(model_type.prototype, 'url') catch e
      return url
    model_type::sync 'update', model, Utils.bbCallback callback

  ##############################
  # Sorting
  ##############################
  # @private
  @isSorted: (models, fields) ->
    fields = _.uniq(fields)
    for model in models
      return false if last_model and @fieldCompare(last_model, model, fields) is 1
      last_model = model
    return true

  # @private
  @fieldCompare: (model, other_model, fields) ->
    field = fields[0]
    field = field[0] if _.isArray(field) # for mongo

    if field.charAt(0) is '-'
      field = field.substr(1)
      desc = true
    if model.get(field) == other_model.get(field)
      return if fields.length > 1 then @fieldCompare(model, other_model, fields.splice(1)) else 0
    if desc
      return if model.get(field) < other_model.get(field) then 1 else -1
    else
      return if model.get(field) > other_model.get(field) then 1 else -1

  # @private
  @jsonFieldCompare: (model, other_model, fields) ->
    field = fields[0]
    field = field[0] if _.isArray(field) # for mongo

    if field.charAt(0) is '-'
      field = field.substr(1)
      desc = true
    if model[field] == other_model[field]
      return if fields.length > 1 then @jsonFieldCompare(model, other_model, fields.splice(1)) else 0
    if desc
      return if JSON.stringify(model[field]) < JSON.stringify(other_model[field]) then 1 else -1
    else
      return if JSON.stringify(model[field]) > JSON.stringify(other_model[field]) then 1 else -1

  ##############################
  # Schema
  ##############################
  @resetSchemas: (model_types, options, callback) ->
    [options, callback] = [{}, options] if arguments.length is 2

    # ensure all models all initialized (reverse relationships may be initialized in a dependent model)
    model_type.schema() for model_type in model_types

    failed_schemas = []
    queue = new Queue(1)
    for model_type in model_types
      do (model_type) -> queue.defer (callback) -> model_type.resetSchema options, (err) ->
        if err
          failed_schemas.push(model_type.model_name)
          console.log "Error when dropping schema for #{model_type.model_name}. #{err}"
        callback()
    queue.await (err) ->
      console.log "#{model_types.length - failed_schemas.length} schemas dropped." if options.verbose
      return callback(new Error("Failed to migrate schemas: #{failed_schemas.join(', ')}")) if failed_schemas.length
      callback()

  ##############################
  # Batch
  ##############################
  # @private
  @batch: (model_type, query, options, callback, fn) ->
    Cursor = require './cursor'

    [query, options, callback, fn] = [{}, {}, query, options] if arguments.length is 3
    [query, options, callback, fn] = [{}, query, options, callback] if arguments.length is 4

    processed_count = 0
    parsed_query = Cursor.parseQuery(query)
    parallelism = if options.hasOwnProperty('parallelism') then options.parallelism else BATCH_DEFAULT_PARALLELISM
    method = options.method or 'toModels'

    runBatch = (batch_cursor, callback) ->
      cursor = model_type.cursor(batch_cursor)
      cursor[method].call cursor, (err, models) ->
        return callback(new Error("Failed to get models. Error: #{err}")) if err or !models
        return callback(null, processed_count) unless models.length

        # batch operations on each
        queue = new Queue(parallelism)
        for model in models
          do (model) -> queue.defer (callback) -> fn(model, callback)
          processed_count++
          break if parsed_query.cursor.$limit and (processed_count >= parsed_query.cursor.$limit)
        queue.await (err) ->
          # model.release() for model in models # clean up memory

          return callback(err) if err
          return callback(null, processed_count) if parsed_query.cursor.$limit and (processed_count >= parsed_query.cursor.$limit)
          batch_cursor.$offset += batch_cursor.$limit
          runBatch(batch_cursor, callback)

    batch_cursor = _.extend({
      $limit: options.$limit or BATCH_DEFAULT_LIMIT
      $offset: parsed_query.cursor.$offset or 0
      $sort: parsed_query.cursor.$sort or 'id' # TODO: generalize sort for different types of sync
    }, parsed_query.find) # add find parameters
    runBatch(batch_cursor, callback)


  ##############################
  # Interval
  ##############################
  # @private
  @interval: (model_type, query, options, callback, fn) ->
    [query, options, callback, fn] = [{}, {}, query, options] if arguments.length is 3
    [query, options, callback, fn] = [{}, query, options, callback] if arguments.length is 4

    throw new Error 'missing option: key' unless key = options.key
    throw new Error 'missing option: type' unless options.type
    throw new Error("type is not recognized: #{options.type}, #{_.contains(INTERVAL_TYPES, options.type)}") unless _.contains(INTERVAL_TYPES, options.type)
    iteration_info = _.clone(options)
    iteration_info.range = {} unless iteration_info.range
    range = iteration_info.range
    no_models = false

    queue = new Queue(1)

    # start
    queue.defer (callback) ->
      # find the first record
      unless start = (range.$gte or range.$gt)
        model_type.cursor(query).limit(1).sort(key).toModels (err, models) ->
          return callback(err) if err
          (no_models = true; return callback()) unless models.length
          range.start = iteration_info.first = models[0].get(key)
          callback()

      # find the closest record to the start
      else
        range.start = start
        model_type.findOneNearestDate start, {key: key, reverse: true}, query, (err, model) ->
          return callback(err) if err
          (no_models = true; return callback()) unless model
          iteration_info.first = model.get(key)
          callback()

    # end
    queue.defer (callback) ->
      return callback() if no_models

      # find the last record
      unless end = (range.$lte or range.$lt)
        model_type.cursor(query).limit(1).sort("-#{key}").toModels (err, models) ->
          return callback(err) if err
          (no_models = true; return callback()) unless models.length
          range.end = iteration_info.last = models[0].get(key)
          callback()

      # find the closest record to the end
      else
        range.end = end
        model_type.findOneNearestDate end, {key: key}, query, (err, model) ->
          return callback(err) if err
          (no_models = true; return callback()) unless model
          iteration_info.last = model.get(key)
          callback()

    # process
    queue.await (err) ->
      return callback(err) if err
      return callback() if no_models

      # interval length
      start_ms = range.start.getTime()
      length_ms = moment.duration((if _.isUndefined(options.length) then 1 else options.length), options.type).asMilliseconds()
      throw Error("length_ms is invalid: #{length_ms} for range: #{util.inspect(range)}") unless length_ms

      query = _.clone(query)
      query.$sort = [key]
      processed_count = 0
      iteration_info.index = 0

      runInterval = (current) ->
        return callback() if current.isAfter(range.end) # done

        # find the next entry
        query[key] = {$gte: current.toDate(), $lte: iteration_info.last}
        model_type.findOne query, (err, model) ->
          return callback(err) if err
          return callback() unless model # done

          # skip to next
          next = model.get(key)
          iteration_info.index = Math.floor((next.getTime() - start_ms) / length_ms)

          current = moment.utc(range.start).add({milliseconds: iteration_info.index * length_ms})
          iteration_info.start = current.toDate()
          next = current.clone().add({milliseconds: length_ms})
          iteration_info.end = next.toDate()

          query[key] = {$gte: current.toDate(), $lt: next.toDate()}
          fn query, iteration_info, (err) ->
            return callback(err) if err
            runInterval(next)

      runInterval(moment(range.start))
