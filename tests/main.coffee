path = require 'path'
fs = require 'fs'
should = require('chai').should()
sinon = require 'sinon'
nock = require 'nock'
Client = require('request-json').JsonClient

DB_NAME = process.env.DB_NAME or 'cozy'

ds = new Client "http://localhost:9101/"
authentifiedEnvs = ['test', 'production']
if process.env.NODE_ENV in authentifiedEnvs
    ds.setBasicAuth process.env.NAME, process.env.TOKEN

couch = new Client "http://localhost:5984/"
fixtures = require '../main'
fixtures.setDefaultValues
    dirPath: path.resolve __dirname, './fixtures/'
    silent: true
    removeBeforeLoad: false # useless because we clean the DB before tests

describe "Fixture Manager", ->

    describe "Reset Database", ->

        describe.only "When resetDatabase is called with no option", ->

            before (done) ->
                @timeout 5000
                fixtures.load callback: done
            before (done) ->
                @timeout 5000
                fixtures.resetDatabase callback: done

            it "It should remove every docs in the database", (done) ->
                ds.get 'doctypes', (err, res, body) ->
                    should.not.exist err
                    should.exist body
                    body.length.should.equal 0
                    done()

        describe "When resetDatabase is called with option removeView", ->

            before ->
                @sandbox = sinon.sandbox.create()
                @stub = @sandbox.stub fixtures, 'removeEveryViews'
                @stub.yieldsTo "callback", null

            before (done) ->
                fixtures.load callback: done
            before (done) ->
                fixtures.resetDatabase
                            removeAllViews: true
                            callback: done
            after ->
                @sandbox.restore()

            it "It should call removeEveryViews", ->
                @stub.called.should.be.true

        describe "When Data System fails at sending doctypes list", (done) ->
            before (done) -> fixtures.resetDatabase
                    removeAllViews: true
                    callback: done

            before ->
                @sandbox = sinon.sandbox.create()
                @stub = @sandbox.stub fixtures, "removeDocumentsOf"
                @stub.callsArg 1 # call the callback

                @scope = nock('http://localhost:9101')
                            .get('/doctypes')
                            .reply(404, error: 'not found')

            before (done) ->
                fixtures.resetDatabase callback: (err) =>
                    @err = err
                    @scope.isDone().should.be.true
                    done()

            after ->
                @sandbox.restore()
                nock.restore()

            it "There should be an error", ->
                should.exist @err

            it "The process should stop", ->
                @stub.callCount.should.equal 0

    describe "Remove Every Views", ->

        describe "When removeEveryViews is called without parameters", ->

            before (done) -> fixtures.resetDatabase
                                removeAllViews: true
                                callback: done

            before (done) ->
                fixtures._createAllRequest 'alarm', ->
                    fixtures._createAllRequest 'contact', done

            before (done) ->
                fixtures.removeEveryViews callback: done

            it "There should only be the doctypes design document", (done) ->
                url = 'cozy/_all_docs?startkey="_design/"&endkey="_design0"' + \
                      '&include_docs=true'
                couch.get url, (err, res, body) ->
                    should.not.exist err
                    should.exist body
                    body.should.have.property 'rows'
                    body.rows.length.should.equal 3
                    body.rows[0].id.should.equal "_design/device"
                    body.rows[1].id.should.equal "_design/doctypes"
                    body.rows[2].id.should.equal "_design/tags"
                    done()

        describe "When removeEveryViews is called with a list of design to remove", ->

            before (done) -> fixtures.resetDatabase
                                removeAllViews: true
                                callback: done

            before (done) ->
                fixtures._createAllRequest 'alarm', ->
                    fixtures._createAllRequest 'contact', done

            before (done) ->
                fixtures.removeEveryViews
                    designsToRemove: ['alarm']
                    callback: done

            it "There should be 4 documents, doctypes, device, tags and contact", (done) ->
                url = DB_NAME + '/_all_docs?startkey="_design/"&endkey="_design0"' + \
                      '&include_docs=true'
                couch.get url, (err, res, body) ->
                    should.not.exist err
                    should.exist body
                    body.should.have.property 'rows'
                    body.rows.length.should.equal 4
                    body.rows[0].id.should.equal "_design/contact"
                    body.rows[1].id.should.equal "_design/device"
                    body.rows[2].id.should.equal "_design/doctypes"
                    body.rows[3].id.should.equal "_design/tags"
                    done()

    describe "#removeDocumentsOf", ->

        describe "When removeDocumentsOf is called with an object as parameter", ->

            before (done) -> fixtures.resetDatabase
                                removeAllViews: true
                                callback: done

            before (done) -> fixtures.load doctypeTarget: 'Alarm', callback: done

            it "There should be an error", (done) ->
                fixtures.removeDocumentsOf {'error': 'blabla'}, (err) ->
                    should.exist err
                    done()

    describe "#_addDoc", ->

        describe "When  _addDoc is called with a document", ->
            before (done) -> fixtures.resetDatabase
                    removeAllViews: true
                    callback: done

            before (done) -> fixtures.resetDatabase callback: done

            before (done) ->
                @doc = require('./fixtures/fixtures.json')[0]
                addDoc = fixtures._addDoc @doc
                addDoc done

            # we must create the all request for the doc's doctype to check the creation
            before (done) ->
                @doctype = @doc.docType
                fixtures._createAllRequest @doctype, done

            it "The document should be added to the data system", (done) ->
                ds.post "request/#{@doctype}/all/", {}, (err, res, body) =>
                    should.not.exist err
                    should.exist body
                    body.length.should.equal 1
                    body[0].value.docType.should.equal @doctype
                    Object.keys(@doc).forEach (field) ->
                        should.exist body[0].value[field]
                    done()

        describe "When _addDoc is called with a document with a field _id", ->
            before (done) -> fixtures.resetDatabase
                                removeAllViews: true
                                callback: done

            before (done) ->
                @doc = require('./fixtures/fixtures-with-id.json')[0]
                @doc.should.have.property '_id'
                @id = @doc._id
                addDoc = fixtures._addDoc @doc
                addDoc done

            it "The document should be added in the database with the specified ID", (done) ->
                ds.get "data/#{@id}/", (err, res, body) =>
                    should.not.exist err
                    should.exist body

                    Object.keys(@doc).forEach (field) =>
                        # if the value is null, body[field] is null
                        # but assertion should be true
                        body[field]?.should.deep.equal @doc[field]
                    done()

        describe "When _addDoc is called with a document with a field _attachments", ->
            before (done) -> fixtures.resetDatabase
                                removeAllViews: true
                                callback: done
            before (done) ->
                @doc = require('./fixtures/fixtures-with-attachment.json')[0]
                @attachment = @doc._attachments
                @doc.should.have.property '_id'
                @doc.should.have.property '_attachments'
                @id = @doc._id
                addDoc = fixtures._addDoc @doc
                addDoc done

            it "The document should be added in the database", (done) ->
                ds.get "data/#{@id}/", (err, res, body) =>
                    should.not.exist err
                    should.exist body

                    Object.keys(@doc).forEach (field) =>
                        # if the value is null, body[field] is null
                        # but assertion should be true
                        body[field]?.should.deep.equal @doc[field]
                    body.should.have.property 'binary'
                    @binary = body.binary
                    done()
            it "And it should have a binary linked that contains the attachement", (done) ->

                    ds.get "data/#{@id}/binaries/file", (err, res, body) =>
                        should.not.exist err
                        should.exist body
                        body.should.not.have.property 'error'
                        done()


