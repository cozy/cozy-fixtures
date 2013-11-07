path = require 'path'
should = require('chai').should()
sinon = require 'sinon'
Client = require('request-json').JsonClient

ds = new Client "http://localhost:9101/"
couch = new Client "http://localhost:5984/"
fixtures = require '../main'
fixtures.setDefaultValues
    dirPath: path.resolve __dirname, './fixtures/'
    silent: true
    removeBeforeLoad: false # useless because we clean the DB before tests


describe "Fixture Manager", ->

    describe "Reset Database", ->

        describe "When resetDatabase is called with no option", ->

            before (done) -> fixtures.load callback: done
            before (done) ->
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

    describe "Remove Every Views", ->

        describe "When removeEveryViews is called without parameters", ->

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
                    body.rows.length.should.equal 1
                    body.rows[0].id.should.equal "_design/doctypes"
                    done()

        describe "When removeEveryViews is called with a list of design to remove", ->

            before (done) ->
                fixtures._createAllRequest 'alarm', ->
                    fixtures._createAllRequest 'contact', done

            before (done) ->
                fixtures.removeEveryViews
                    designsToRemove: ['alarm']
                    callback: done


            it "There should be two design documents, doctypes and contact", (done) ->
                url = 'cozy/_all_docs?startkey="_design/"&endkey="_design0"' + \
                      '&include_docs=true'
                couch.get url, (err, res, body) ->
                    should.not.exist err
                    should.exist body
                    body.should.have.property 'rows'
                    body.rows.length.should.equal 2
                    body.rows[0].id.should.equal "_design/contact"
                    body.rows[1].id.should.equal "_design/doctypes"
                    done()
