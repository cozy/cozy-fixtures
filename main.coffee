require 'colors'
async = require 'async'
Client = require('request-json').JsonClient
fs = require 'fs'
util = require 'util'


# TODO
##handling one file parameter
##fs.readFileSync filePath


class FixtureManager

    # Where the fixture files are
    dirPath: './tests/fixtures/'
    # If the script must be restrain to one doctype, which one
    doctypeTarget: null
    # If true, the script won't output anything
    silent: false
    # If set, will be executed at the end of the process
    callback: null
    # If true, will removed documents of concerned doctypes before loading docs
    removeBeforeLoad: true

    dataSystemUrl: "http://localhost:9101/"

    constructor: ->
        @client = new Client @dataSystemUrl


    load: (opts) ->

        # initialize the fixture manager with option
        @dirPath = opts.dirPath if opts?.dirPath?
        if opts?.doctypeTarget?
            @doctypeTarget = opts.doctypeTarget.toLowerCase()
        @silent = opts.silent if opts?.silent?
        if opts?.dataSystemUrl?
            @dataSystemUrl = opts.dataSystemUrl
            @client = new Client @dataSystemUrl

        # We want to reset the default parameters at the end of the process
        if opts?.callback?
            @callback = (err) =>
                @_resetDefaults()
                opts.callback()
        else
            @callback = (err) =>
                @_resetDefaults()

        @removeBeforeLoad = opts.removeBeforeLoad if opts?.removeBeforeLoad?

        # start the whole process
        try
            if fs.lstatSync(@dirPath).isDirectory()
                # get the files and data
                fileList = fs.readdirSync(@dirPath)
                async.concat fileList, @_readJSONFile, @onRawFixturesLoad
            else if fs.lstatSync(@dirPath).isFile()
                @_readJSONFile @dirPath, @onRawFixturesLoad, true
        catch e
            @log "[ERROR] Cannot load fixtures -- #{e}".red

    _resetDefaults:  ->
        @dirPath = './tests/fixtures/'
        @doctypeTarget = null
        @silent = false
        @callback = null
        @removeBeforeLoad = true

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
                currentDoctype = doc.docType.toLowerCase()
                unless doctypeSet[currentDoctype]?
                    doctypeSet[currentDoctype] = []
                doctypeSet[currentDoctype].push doc

        if skippedDoctypeMissing.length > 0
            msg = "[WARN] Missing doctype information in " + \
                        "#{skippedDoctypeMissing.length} documents."
            @log msg.red
            for missingDoctypeDoc in skippedDoctypeMissing
                @log util.inspect missingDoctypeDoc

        # prepare process
        requests = []
        for doctype, docs of doctypeSet
            requests.push @_processFactory doctype, docs

        # start process for each doctype
        async.series requests, (err, results) =>
            @log "[INFO] End of fixtures importation.".blue

            @callback() if @callback?

    # Process description:
    ## create the "all" request
    ## remove the document relative to the "all" request
    ## add the documents again
    _processFactory: (doctypeName, docs, callback) -> (callback) =>

        msg = "[INFO] DOCTYPE: #{doctypeName} - Starting importation " + \
              "of #{docs.length} documents..."
        @log msg.yellow

        # Creating request
        @log  "\t* Creating the \"all\" request..."
        @_createAllRequest doctypeName, (err) =>

            if err?
                msg = "\t\tx Couldn't create the \"all\" request -- #{err}"
                @log msg.red
            else
                @log "\t\t-> \"all\" request successfully created.".green

            if @removeBeforeLoad
                @_processDeletion doctypeName, =>
                    @_processAddition docs, callback
            else
                @_processAddition docs, callback

    _processAddition: (docs, callback) ->
        # Adding documents
        requests = []
        for doc in docs
            requests.push @_addDoc doc, callback

        @log "\t* Adding documents in the Data System..."
        async.parallel requests, (err, results) =>
            if err?
                msg = "\t\tx One or more documents have not been " + \
                      "added to the Data System -- #{err}"
                @log msg.red
            else
                @log "\t\t-> #{results.length} docs added!".green

            # starts next doctype importation
            callback null, null

    _processDeletion: (doctypeName, callback) ->
       # Removing documents
        @log "\t* Deleting documents from the Data System..."
        @removeAllDocsByDoctype doctypeName, (err) =>
            if err?
                msg = "\t\tx Couldn't delete documents from the Data " + \
                           "System --- #{err}"
                @log msg.red
            else
                msg = "\t\t-> Documents have been deleted from the " + \
                      "Data System."
                @log msg.green

            callback()

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

                callback err, data
        else
            errorMsg = "[WARN] Skipped #{filePath} because it is not a " + \
                        "JSON file."
            @log errorMsg.red
            callback null, null

    _getAllRequest: (doctypeName) ->
        return """
                function (doc) {
                    if (doc.docType === "#{doctypeName}") {
                        return emit(doc._id, doc);
                    }
                }
               """

    _createAllRequest: (doctypeName, callback) ->
        all = map: @_getAllRequest doctypeName
        @client.put "request/#{doctypeName}/all/", all, (err, res, body) ->
            @log  "Error occurred during  -- #{err}".red if err?
            callback err

    removeAllDocsByDoctype: (doctypeNames, callback) ->

        factory = (doctypeName) => (callback) =>
            @_createAllRequest doctypeName, (err) =>
                @_removeDocsForDoctype doctypeName, (err) ->
                    callback err
        requests = []
        if doctypeNames instanceof Array
            for doctypeName in doctypeNames
                requests.push factory doctypeName
        else
            requests.push factory doctypeNames

        async.parallel requests, (err) =>
            @log "\t[ERRROR] Couldn't remove all the docs -- #{err}".red if err?
            callback err

    _removeDocsForDoctype: (doctypeName, callback) ->
        url = "request/#{doctypeName}/all/destroy/"
        @client.put url, {}, (err, res, body) ->
            err = body.error if body? and body.error?
            callback err

    resetDatabase: (opts) ->

        @silent = opts.silent if opts?.silent?
        callback = opts.callback if opts?.callback?

        if opts?.removeAllRequests?
            removeAllRequests = opts.removeAllRequests
        else
            removeAllRequests = false

        @client.get 'doctypes', (err, res, body) =>
            msg = "[INFO] Removing all document from the database..."
            @log msg.yellow
            @removeAllDocsByDoctype body, =>
                @log "\tAll documents have been removed.".green if not err?
                if removeAllRequests
                    msg = "[INFO] Removing all the views 'all' from database..."
                    @log msg.yellow
                    @_removeAllRequestsByDoctype body, (err) =>
                        unless err?
                            @log "\tAll views 'all' have been removed".green
                        @_resetDefaults()
                        callback err if callback?
                else
                    @_resetDefaults()
                    callback err if callback?

    _removeAllRequestsByDoctype: (doctypeNames, callback) ->

        factory = (doctypeName) => (callback) =>
            @_removeAllRequestsForDoctype doctypeName, (err) ->
                callback err
        requests = []
        if doctypeNames instanceof Array
            for doctypeName in doctypeNames
                requests.push factory doctypeName
        else
            requests.push factory doctypeNames

        async.parallel requests, (err) =>
            msg = "\t[ERRROR] Couldn't remove the 'all' request -- #{err}"
            @log msg.red if err?
            callback err

    _removeAllRequestsForDoctype: (doctypeName, callback) ->
        url  = "request/#{doctypeName}/all"
        @client.del url, (err, res, body) ->
            err = body.error if body?.error?
            # we ignore the error if the view doesn't exist
            err  = null if res?.statusCode in [204, 404]
            callback err

    _addDoc: (doc, callback) -> (callback) =>
        @client.post 'data/', doc, (err, res, body) ->
            if err?
                if res?
                    statusCode = "#{statusCode} - "
                else
                    statusCode = ""
                callback("#{statusCode}#{err}", null)
            else
                callback(null, 'OK')

    log: (msg) -> console.log msg unless @silent


module.exports = new FixtureManager()