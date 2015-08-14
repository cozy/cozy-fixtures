require 'colors'
async = require 'async'
Client = require('request-json').JsonClient
Mockaroo = require 'mockaroo'
fs = require 'fs'
S = require 'string'
util = require 'util'
path = require 'path'

DB_NAME = process.env.DB_NAME or 'cozy'

class FixtureManager


    ###
    # The value of those properties are set through @_resetDefaults
    # or @setDefaultValues()
    ###

    # Where the fixture files are
    dirPath: null
    # If the script must be restrain to one doctype, which one
    doctypeTarget: null
    selectedDoctypes: null
    # If true, the script won't output anything
    silent: null
    # If true, use Mockaroo service to generate fixtures from the definiton
    # files ; counter set number of entries wanted
    generate: null
    counter: 10
    # If set, will be executed at the end of the process
    callback: null
    # If true, will removed documents of concerned doctypes before loading docs
    removeBeforeLoad: null
    # Data System URL
    dataSystemUrl: null
    # Authentication
    auth: false

    defaultValues:
        dirPath: './test/fixtures/'
        doctypeTarget: null
        selectedDoctypes: null
        silent: false
        generate: false
        counter: 10
        callback: null
        removeBeforeLoad: true
        dataSystemUrl: "http://localhost:9101/"

    constructor: ->
        @_resetDefaults()
        @client = new Client @dataSystemUrl

        authentifiedEnvs = ['test', 'production']
        if process.env.NODE_ENV in authentifiedEnvs
            @client.setBasicAuth process.env.NAME, process.env.TOKEN
            @auth = true

    # Reset the options to the default values
    _resetDefaults:  ->
        @dirPath = @defaultValues['dirPath']
        @doctypeTarget = @defaultValues['doctypeTarget']
        @selectedDoctypes = @defaultValues['selectedDoctypes']
        @silent = @defaultValues['silent']
        @generate = @defaultValues['generate']
        @counter = @defaultValues['counter']
        @callback = @defaultValues['callback']
        @removeBeforeLoad = @defaultValues['removeBeforeLoad']
        @dataSystemUrl = @defaultValues['dataSystemUrl']

    # Add permissions if it is necessary
    _setPermissions: (callback) =>
        if fs.existsSync('/etc/cozy/controller.token') and not @auth
            # Recover home password
            fs.readFile '/etc/cozy/controller.token', (err, credentials) =>
                if err
                    console.log 'If you are in production environment, you ' +
                        'should have root access'
                    callback()
                else
                    credentials = S(credentials.toString('utf8')).lines()
                    pwd = credentials[0]
                    # Recover application name
                    manifest = fs.readFileSync('./package.json')
                    manifest = JSON.parse(manifest)
                    name = manifest.name.replace('cozy-', '')
                    # Recover application password
                    @client.setBasicAuth 'home', pwd
                    @client.post '/request/application/all/', {key: name}, (err, res, body) =>
                        if body?[0]?.value?.password?
                            pwd = body[0].value.password
                            @client.setBasicAuth name, pwd
                        callback()
        else
            callback()


    # Set the default values
    setDefaultValues: (opts) ->
        for opt, value of opts
            @defaultValues[opt] = value if @defaultValues[opt]?
        @_resetDefaults()

    # Load the fixtures
    load: (opts) ->
        # Handle options
        @dirPath = opts.dirPath if opts?.dirPath?
        if opts?.doctypeTarget?
            @doctypeTarget = opts.doctypeTarget.toLowerCase()
        @silent = opts.silent if opts?.silent?
        if opts?.dataSystemUrl?
            @dataSystemUrl = opts.dataSystemUrl
            @client = new Client @dataSystemUrl
        if opts?.generate?
            @generate = opts.generate
            @counter = opts.counter
        @_setPermissions () =>
            # We want to reset the default parameters at the end of the process
            if opts?.callback?
                @callback = (err) =>
                    @_resetDefaults()
                    opts.callback()
            else
                @callback = (err) => @_resetDefaults()

            @removeBeforeLoad = opts.removeBeforeLoad if opts?.removeBeforeLoad?

            # Seek and open the fixtures files
            try
                if fs.lstatSync(@dirPath).isDirectory()
                    # get the files and data
                    fileList = fs.readdirSync @dirPath
                    async.concat fileList, @_readJSONFile, @onRawFixturesLoad
                else if fs.lstatSync(@dirPath).isFile()
                    @_readJSONFile @dirPath, @onRawFixturesLoad, true
            catch e
                @log "[ERROR] Cannot load fixtures -- #{e}".red

    # Parse the data from files
    onRawFixturesLoad: (err, docs) =>

        # Track malformed documents
        skippedDoctypeMissing = []

        # Store the documents per doctypes
        doctypeSet = {}
        for doc in docs
            doc.docType = doc.docType.toLowerCase() if doc.docType?
            unless doc.docType?
                skippedDoctypeMissing.push doc
            else if (not @doctypeTarget? or @doctypeTarget is "") \
                    or @doctypeTarget is doc.docType
                doctypeSet[doc.docType] = [] unless doctypeSet[doc.docType]?
                doctypeSet[doc.docType].push doc

        if skippedDoctypeMissing.length > 0
            msg = "[WARN] Missing doctype information in " + \
                        "#{skippedDoctypeMissing.length} documents."
            @log msg.red
            for missingDoctypeDoc in skippedDoctypeMissing
                @log util.inspect missingDoctypeDoc

        # prepare addition process
        requests = []
        for doctype, docs of doctypeSet
            requests.push @_processAdditionFactory doctype, docs

        # start addition process for each doctype
        async.series requests, (err, results) =>
            @log "[INFO] End of fixtures importation.".blue

            @callback() if @callback?

    # Process description:
    #  * if removeBeforeLoad option is enabled
    #    - create 'all' request for given doctype
    #    - remove all the documents for given doctype
    #    - remove 'all' request for given doctype
    #  * anyway -> add the documents for given doctype
    _processAdditionFactory: (doctypeName, docs, callback) -> (callback) =>

        msg = "[INFO] DOCTYPE: #{doctypeName} - Starting importation " + \
              "of #{docs.length} documents..."
        @log msg.yellow

        if @removeBeforeLoad
            @removeDocumentsOf doctypeName, (err) =>
                if err
                    callback err
                else
                    @_processAddition docs, callback
        else
            @_processAddition docs, callback

    # Remove the documents of given doctypes
    #  * param can be String (doctype name) or Array (of doctype names)
    removeDocumentsOf: (doctypeNames, callback) ->

        # argument can be string or array but we'll process arrays
        if typeof doctypeNames is 'string' or doctypeNames instanceof String
            doctypeNames = [doctypeNames]

        else if not (doctypeNames instanceof Array)
            util = require 'util'
            msg = "The doctype names list should be an array"
            errorMsg = util.inspect doctypeNames
            callback new Error "#{msg} -- #{errorMsg}"
            return

        doctypeList = doctypeNames.join " "
        msg = "\t* Removing all documents for doctype(s) #{doctypeList}..."
        @log msg

        @_setPermissions () =>
            # create 'all' requests for each doctypes
            @createAllRequestsFor doctypeNames, (err) =>
                if err?
                    callback err
                else
                    # create a new context to avoid the loop bug
                    factory = (doctypeName) => (callback) =>
                        @_removeDocs doctypeName, (err) ->
                            callback err

                    asyncRequests = []
                    for doctypeName in doctypeNames
                        asyncRequests.push factory doctypeName

                    async.parallel asyncRequests, (err) =>
                        if err?
                            msg = "\t[ERRROR] Couldn't delete all the docs"
                            @log "#{msg} -- #{err}".red

                        # TODO: if the request didn't exist before we create it
                        # we must remove it
                        # only useful if removeBeforeLoad is true to isolate tests

                        callback err

    # Create the 'all' requests for given doctypes
    #  * param can be String (doctype name) or Array (of doctype names)
    createAllRequestsFor: (doctypeNames, callback) ->

        # argument can be string or array but we'll process arrays
        if typeof doctypeNames is 'string' or doctypeNames instanceof String
            doctypeNames = [doctypeNames]

        doctypeList = doctypeNames.join " "
        msg = "\t\t* Creating 'all' requests for doctype(s) #{doctypeList}..."
        @log msg

        # create a new context to avoid the loop bug
        factory = (doctypeName) => (callback) =>
            @_createAllRequest doctypeName, callback

        asyncRequests = []
        for doctypeName in doctypeNames
            asyncRequests.push factory doctypeName

        async.parallel asyncRequests, (err) =>
            if err?
                msg = "\t\t\t* Something went wrong during request " + \
                      "creation -- #{err}"
                @log msg.red
            else
                msg = "\t\t\t-> 'all' requests have been successfully created."
                @log msg.green
            callback err

    # Add docs into the data system
    _processAddition: (docs, callback) ->
        # Adding documents
        asyncRequests = []
        for doc in docs
            asyncRequests.push @_addDoc doc

        @log "\t* Adding documents in the Data System..."
        async.parallel asyncRequests, (err, results) =>
            if err?
                msg = "\t\tx One or more documents have not been " + \
                      "added to the Data System -- #{err}"
                @log msg.red
            else
                @log "\t\t-> #{results.length} docs added!".green

            # starts next doctype importation
            callback null, null

    # Parse the JSON file
    _readJSONFile: (filename, callback, absolutePath = false) =>
        if absolutePath
            filePath = filename
        else
            @dirPath = "#{@dirPath}/" if @dirPath[@dirPath.length - 1] isnt '/'
            filePath = @dirPath + filename

        # check it's a .json file
        if filePath.indexOf('.json') isnt -1
            fs.readFile filePath, (err, data) =>

                if err?
                    err = "[ERROR] While reading fixtures files, got #{err}"
                    @log err.red
                else
                    msg = "[INFO] Reading fixtures from #{filePath}..."
                    @log msg.blue

                try
                    data = JSON.parse data
                catch e
                    msg = "[WARN] Skipped #{filePath} because it contains " + \
                                "malformed JSON --- #{e}"
                    data = []
                    @log msg.red

                # use JSON files as definition for Mockaroo if in generate mode
                if @generate
                    try
                        client = new Mockaroo.Client
                            apiKey: process.env.MOCKAROO_API_KEY
                            secure: false

                        client
                            .generate
                                count: @counter
                                fields: data
                            .then (records) ->
                                callback null, records
                            .catch (err) ->
                                if err instanceof Mockaroo.errors.InvalidApiKeyError
                                    err = 'invalid api key'
                                else if err instanceof Mockaroo.errors.UsageLimitExceededError
                                    err = 'usage limit exceeded'
                                else
                                    err = error

                                @log err.red
                                callback err
                    catch e
                        err = "[ERROR] Cannot initialize Mockaroo client -- #{e}".red
                        @log err.red

                else
                    callback err, data

        else
            errorMsg = "[WARN] Skipped #{filePath} because it is not a " + \
                        "JSON file."
            @log errorMsg.red
            callback null, null

    # Generates a 'all' request for given doctype
    _getAllRequest: (doctypeName) ->
        return """
                function (doc) {
                    if (doc.docType.toLowerCase() === "#{doctypeName}") {
                        return emit(doc._id, doc);
                    }
                }
               """

    # Add one document into the data system
    _addDoc: (doc) -> (callback) =>
        _attachments = doc._attachments
        delete doc._attachments
        doc.docType = doc.docType.toLowerCase()
        @client.post 'data/', doc, (err, res, body) =>
            if err?
                if res?
                    statusCode = "#{statusCode} - "
                else
                    statusCode = ""
                callback "#{statusCode}#{err}", null
            else
                if _attachments?
                    filePath = path.resolve _attachments
                    url = "data/#{body._id}/binaries/"
                    filename = _attachments.split '/'
                    filename = filename[filename.length - 1]
                    data = name: 'file'
                    @client.sendFile url, filePath, data, (err, res, body) ->
                        if err? or body.err?
                            err = err or body.err
                            callback err
                        else
                            callback null, true
                else
                    callback null, true

    # Remove documents for a given doctype
    _removeDocs: (doctypeName, callback) ->
        url = "request/#{doctypeName}/all/destroy/"
        @client.put url, {}, (err, res, body) ->
            err = body.error if body? and body.error?
            if err?
                if res?
                    statusCode = "#{statusCode} - "
                else
                    statusCode = ""
                callback "#{statusCode}#{err}", null
            else
                callback null, true

    # Create a 'all' request for given doctype
    _createAllRequest: (doctypeName, callback) ->
        all = map: @_getAllRequest doctypeName.toLowerCase()
        @client.put "request/#{doctypeName}/all/", all, (err, res, body) =>
            @log  "Error occurred during  -- #{err}".red if err?
            callback err

    # Removes all the documents from database
    # option removeAllViews to true triggers views removal
    resetDatabase: (opts) ->

        @silent = opts.silent if opts?.silent?
        callback = opts.callback if opts?.callback?

        if opts?.removeAllViews?
            removeAllViews = opts.removeAllViews
        else
            removeAllViews = false

        @client.get 'doctypes', (err, res, body) =>
            msg = "[INFO] Removing all document from the database..."
            @log msg.yellow

            if err? or not body? or (body? and body.error?)
                msg = "An error occurred while retrieving the doctypes list"
                errorInfo = err or require('util').inspect body
                msgError = "#{msg} -- #{msgError}"
                @log msgError.red
                callback new Error msgError
                return

            @removeDocumentsOf body, =>
                @log "\tAll documents have been removed.".green if not err?
                if removeAllViews
                    @removeEveryViews callback: (err) =>
                        @_resetDefaults()
                        callback err if callback?
                else
                    @_resetDefaults()
                    callback err if callback?

    # Remove every views (views are attached to design documents)
    #  * a design can be precised
    #  * if no design is given, they will all be deleted
    removeEveryViews: (opts) ->
        callback = opts.callback if opts?.callback?
        if opts?.designsToRemove?
            designsToRemove = opts.designsToRemove
        else
            designsToRemove = []

        if designsToRemove.length > 0
            designList = "design " + designsToRemove.join " "
        else
            designList = "all the designs"
        @log "[INFO] Removing views for #{designList}...".yellow

        designsToRemove = designsToRemove.map (single) -> "_design/#{single}"

        # Get all the design documents
        @clientCouch = new Client "http://localhost:5984/"
        url = DB_NAME + '/_all_docs?startkey="_design/"&endkey="_design0"' + \
              '&include_docs=true'
        @clientCouch.get url, (err, res, body) =>
            deleteFactory = (id, rev) => (callback) =>
                url = "#{DB_NAME}/#{id}?rev=#{rev}"
                @clientCouch.del url, (err, res, body) =>
                    callback err, body

            # Design docs needed by the data system in order to work
            requiredDesignDocs = [
                '_design/doctypes'
                '_design/device'
                '_design/tags'
            ]
            asyncRequests = []
            for row in body.rows
                mustRemove =  (designsToRemove.length is 0 or \
                              row.key in designsToRemove) and \
                              not (row.key in requiredDesignDocs)
                if mustRemove
                    asyncRequests.push deleteFactory row.id, row.value.rev

            async.parallel asyncRequests, (err) =>
                if err?
                    msg = "\tx An error occurred while removing the designs."
                    @log "#{msg} -- #{err}".red
                else
                    @log "\t -> The views have been successfully removed.".green

                callback err if callback?

    # Custom log function to allow silence mode
    log: -> console.log.apply console, arguments unless @silent

module.exports = new FixtureManager()
