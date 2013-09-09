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
    dirPath: './fixtures/'
    # If the script must be restrain to one doctype, which one
    doctypeTarget: null

    dataSystemUrl: "http://localhost:9101/"

    constructor: ->
        # Connection to the data system
        @client = new Client @dataSystemUrl

    load: (dirPath, doctypeTarget) ->

        @dirPath = dirPath if dirPath?
        @doctypeTarget = doctypeTarget if doctypeTarget?

        try
            if fs.lstatSync(@dirPath).isDirectory()
                # get the files and data
                fileList = fs.readdirSync(@dirPath)
                async.concat fileList, @_readJSONFile, @onRawFixturesLoad
            else if fs.lstatSync(@dirPath).isFile()
                @_readJSONFile @dirPath, @onRawFixturesLoad, true
        catch e
            console.log "[ERROR] Cannot load fixtures -- #{e}".red

    onRawFixturesLoad: (err, docs) =>

        # Track malformed documents
        skippedDoctypeMissing = []

        # Store the document per doctypes
        doctypeSet = {}
        for doc in docs
            doc.docType = doc.docType.toLowerCase()
            unless doc.docType?
                skippedDoctypeMissing.push doc
            else if (not @doctypeTarget? or @doctypeTarget is "") \
                    or @doctypeTarget is doc.docType
                currentDoctype = doc.docType.toLowerCase()
                unless doctypeSet[currentDoctype]?
                    doctypeSet[currentDoctype] = []
                doctypeSet[currentDoctype].push doc

        # TODO: improving feedback by telling in which documents
        #       the doctype is missing
        if skippedDoctypeMissing.length > 0
            msg = "[WARN] Missing doctype information in " + \
                        "#{skippedDoctypeMissing.length} documents."
            console.log msg.red
            for missingDoctypeDoc in skippedDoctypeMissing
                console.log util.inspect missingDoctypeDoc

        # prepare process
        requests = []
        for doctype, docs of doctypeSet
            requests.push @_processFactory doctype, docs

        # start process for each doctype
        async.series requests, (err, results) ->
            console.log "[INFO] End of fixtures importation.".blue

    # Process description:
    ## create the "all" request
    ## remove the document relative to the "all" request
    ## add the documents again
    _processFactory: (doctypeName, docs, callback) -> (callback) =>

        msg = "[INFO] DOCTYPE: #{doctypeName} - Starting importation " + \
              "of #{docs.length} documents..."
        console.log msg.yellow

        # Creating request
        console.log  "\t* Creating the \"all\" request..."
        @_createAllRequest doctypeName, (err) =>

            if err?
                msg = "\t\tx Couldn't create the \"all\" request -- #{err}"
                console.log msg.red
            else
                console.log "\t\t-> \"all\" request successfully created.".green

            # Removing documents
            console.log "\t* Deleting documents from the Data System..."
            @_removeDocs doctypeName, (err) =>
                if err?
                    msg = "\t\tx Couldn't delete documents from the Data " + \
                               "System --- #{err}"
                    console.log msg.red
                else
                    msg = "\t\t-> Documents have been deleted from the " + \
                          "Data System."
                    console.log msg.green

                # Adding documents
                requests = []
                for doc in docs
                    requests.push @_addDoc doc, callback

                console.log "\t* Adding documents in the Data System..."
                async.parallel requests, (err, results) ->
                    if err?
                        msg = "\t\tx One or more documents have not been " + \
                              "added to the Data System -- #{err}"
                        console.log msg.red
                    else
                        console.log "\t\t-> #{results.length} docs added!".green

                    # starts next doctype importation
                    callback null, null

    _readJSONFile: (filename, callback, absolutePath = false) =>

        if absolutePath
            filePath = filename
        else
            @dirPath = "#{@dirPath}/" if @dirPath[@dirPath.length - 1] isnt '/'
            filePath = @dirPath + filename

        # check it's a .json file
        if filePath.indexOf('.json') isnt -1
            fs.readFile filePath, (err, data) ->

                if err?
                    err = "[ERROR] While reading fixtures files, got #{err}"
                    console.log err.red
                else
                    msg = "[INFO] Reading fixtures from #{filePath}..."
                    console.log msg.blue

                try
                    data = JSON.parse data
                catch e
                    msg = "[WARN] Skipped #{filePath} because it contains " + \
                                "malformed JSON --- #{e}"
                    data = []
                    console.log msg.red

                callback err, data
        else
            errorMsg = "[WARN] Skipped #{filePath} because it is not a " + \
                        "JSON file."
            console.log errorMsg.red
            callback null, null

    _getAllRequest: (doctypeName) ->
        return """
                function (doc) {
                    if (doc.docType === "#{doctypeName}") {
                        return emit(doc.id, doc);
                    }
                }
               """

    _createAllRequest: (doctypeName, callback) ->
        all = map: @_getAllRequest doctypeName
        @client.put "request/#{doctypeName}/all/", all, (err, res, body) ->
            callback err

    _removeDocs: (doctypeName, callback) ->
        url = "request/#{doctypeName}/all/destroy/"
        @client.put url, {}, (err, res, body) ->
            err = body.error if body? and body.error?
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