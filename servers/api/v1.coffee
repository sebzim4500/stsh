express = require("express")
_ = require("underscore")._


app = module.exports = express.createServer()

config = _.defaults require("../../config"),
  store: "memory"
  ttl: 60 * 60 * 24 * 2 # 2 days

app.configure ->
  app.use require("../../lib/plunker").middleware(config)

  app.use express.methodOverride()
  app.use express.bodyParser()
  app.use express.cookieParser()



fetchPlunk = (req, res, next) ->
  req.plunker.read req.params.id, (err, plunk) ->
    if err then return apiError(err)
    else
      req.plunk = plunk
      next()

apiError = (res, err) ->
  body = _.extend({}, err)
  if err.message then body.message = err.message
  if err.errors then body.errors = err.errors
  if err.stack then body.stack = err.stack
  
  delete body.statusCode

  res.json(body, err.statusCode or 500)

checkToken = (req, res, next) ->
  req.token =
    if req.query.token? then req.query.token
    else if auth = req.header("Authorization")
      [token] = auth.match(/^token (\S+)$/i)
      token
    else if req.params.id and req.cookies[req.params.id.toLowerCase()]? then req.cookies[req.params.id.toLowerCase()]
  if req.plunk
    req.authorized = (req.token == req.plunk.token)

  next()

app.error (err, req, res, next) -> apiError(res, err)

# CORS Headers
app.all "*", (req, res, next) ->
  res.header("Access-Control-Allow-Origin", "*")

  #if req.method == "OPTIONS"
  res.header("Access-Control-Allow-Headers", req.header("Access-Control-Request-Headers")) # I hear an echo. Do you?
  res.header("Access-Control-Allow-Methods", "GET, POST, PATCH, PUT, DELETE")
  res.header("Access-Control-Max-Age", 60 * 60 * 24 * 2) # 2 days

  next()

# Index
app.get "/plunks", (req, res) ->
  req.plunker.index (err, plunks) ->
    if err then return apiError(res, err)
    else
      for plunk in plunks
        # TODO: WTF Express, why are all cookies lowercase?
        unless req.cookies[plunk.id.toLowerCase()] == plunk.token
          delete plunk.token
      res.json(plunks, 200)

# Create
app.post "/plunks", (req, res) ->
  req.plunker.create req.body, (err, plunk) ->
    if err then return apiError(res, err)
    else
      res.cookie plunk.id, plunk.token, { expires: new Date(plunk.expires), httpOnly: true, path: "/api/v1/" }
      res.json(plunk, 201) # Created

# Read
app.get "/plunks/:id", fetchPlunk, checkToken, (req, res) ->
  unless req.plunk then return apiError res,
    statusCode: 404
    message: "Not found"
  else
    unless req.authorized then delete req.plunk.token
    res.json(req.plunk, 200)

# Update
app.post "/plunks/:id", fetchPlunk, checkToken, (req, res) ->
  unless req.plunk then return apiError res,
    statusCode: 404
    message: "Not found"
  else unless req.authorized then return apiError res,
    statusCode: 403 # Forbidden
    message: "Unauthorized"
  else
    req.plunker.update req.plunk, req.body, (err, plunk) ->
      if err then return apiError(res, err)
      else res.json(plunk, 200)

# Delete
app.del "/plunks/:id", fetchPlunk, checkToken, (req, res) ->
  unless req.authorized then return apiError res,
    statusCode: 403 # Forbidden
    message: "Unauthorized"
  else
    req.plunker.remove req.params.id, (err) ->
      if err then return apiError(res, err)
      else
        res.clearCookie req.params.id, { path: "/api/v1/plunks" }
        res.send(204) # No content

if require.main == module
  app.listen process.env.PORT || 8080
  console.log "API listening on port %d", process.env.PORT || 8080