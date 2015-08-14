# Cozy-fixtures
Manage easily the data fixtures for your Cozy developments!

[![Build Status](https://travis-ci.org/mycozycloud/cozy-fixtures.png?branch=master)](https://travis-ci.org/mycozycloud/cozy-fixtures)

# Usage
Please note that the "load" process do the following:

* removing all the data for the concerned doctypes
* adding the fixtures for the concerned doctypes

The "concerned doctypes" are the ones found in the fixture files or the ones you gaves through parameters.

## CLI
When you develop an application you might want to feed the Data System with data.

```bash
npm install -g cozy-fixtures
cozy-fixtures load # will load all the fixtures inside ./tests/fixtures/
cozy-fixtures load ./fixtures/ # you can specify a folder
cozy-fixtures load ./fixtures/my-super-fixtures.json # or a file
cozy-fixtures load -d contact # only load the documents for a specified doctype
cozy-fixtures load -g -n 25 # uses fixtures/*.json files as model for Mockaroo to auto-generate 25 records
cozy-fixtures load -s # run the script quietly
cozy-fixtures -l load # doesn't remove documents before loading
```

## Automatic Tests
You can use cozy-fixtures programatically to ease automatic testing:

* First, add it to your dev dependencies:
```bash
npm install cozy-fixtures --save-dev
```
* Then use it where you need it

```coffeescript
fixtures = require 'cozy-fixtures'
fixtures.load
    dirPath: 'path/to/fixtures' # default is './test/fixtures/'
    doctypeTarget: 'doctypeName' # default is null
    silent: true # default is false
    removeBeforeLoad: false # default is true. Remove docs for concerned doctypes before loading the data
    callback: yourCallback # default is null
```

You can also do more precise action like:

* deleting all the documents for a specified doctype

```coffeescript
fixtures = require 'cozy-fixtures'
fixtures.removeDocs "doctypeName", (err) ->
    console.log err if err?
```

* deleting all the documents from the database

```coffeescript
fixtures = require 'cozy-fixtures'
    fixtures.resetDatabase
        callback: (err) -> console.log err if err?
        designsToRemove: true # default is false, removes all the design docs in the database (and related) views
```

If you want to have the same configuration for every call, use the setDefaultValues method:

```coffeescript
fixtures = require 'cozy-fixtures'
fixtures.setDefautValues
            target: './a/custom/target.json'
            silent: true
            removeBeforeLoad: false
fixtures.load callback: (err) -> console.log "fixtures loaded !"
```

You can still override the defautl values by passing the arguments to the load function.


# How to format the fixtures
* You must put the fixtures into files
* Fixtures must be described in valid JSON
* Don't forget the "docType" field in the fixtures

A simple example:
```json
[
    {
        "docType": "Alarm",
        "action": "DISPLAY",
        "trigg": "Tue Jul 02 2013 16:00:00",
        "description": "Réunion review scopyleft",
        "related": null
    },
    {
        "docType": "Contact",
        "fn": "John Doe",
        "datapoints": [
            {
                "name": "about",
                "type": "birthday",
                "value": "02/02/1980",
                "id": 1
            },
            {
                "name": "tel",
                "type": "main",
                "value": "+33 12 34 56 78",
                "id": 2
            }
        ],
        "note": "Données complémentaires sur le contact."
    },
    {
        "_id": "2",
        "docType": "File",
        "_attachments": "test/fixtures/files/fixtures.json",
        "class": "document",
        "lastModification": "Thu Oct 17 2013 08:29:21 GMT+0200 (CEST)",
        "name": "fixtures.json",
        "path": "",
        "size": 2413
    }
}
]
```
Note that you can add files as attachments. In order to achieve this, add a "_attachments" field to your fixture and put the path relatively to where you run the command.


# Use auto-generation through [Mockaroo](https://www.mockaroo.com) service

You can use the Mockaroo service to generate records and inject them as fixtures. You must define your model in your fixtures files, as follow:
```json
[
  {
    "name": "docType",
    "type": "Template",
    "value": "Alarm"
  },
  {
    "name": "action",
    "type": "Template",
    "value": "DISPLAY"
  },
  {
    "name": "trigg",
    "type": "Date",
    "min": "01/01/2000",
    "max": "12/31/2015",
    "format": "%a %b %d %Y %H:%M:%S"
  },
  {
    "name": "description",
    "type": "Sentences",
    "min": 1,
    "max": 1,
    "percentBlank": 20
  },
  {
    "name": "related",
    "type": "Blank"
  }
]
```

Your model declares all fields wanted in each record, and each field must have at least a _name_ and _type_ keys. They relies on the Mockaroo API (see [their documentation for more information](https://www.mockaroo.com/api/docs) about types and their parameters). Complex formats such as nested contents are allowed.

Note that an API key is needed to use the service. It can be obtained freely (limit to 200 request per day) on Mockaroo. Just sign up to the service and get your key in _my account_ section. This key must be provided in the `MOCKAROO_API_KEY`:

```sh
MOCKAROO_API_KEY="my_api_key" cozy-fixtures -g
```


## What is Cozy?

![Cozy Logo](https://raw.github.com/mycozycloud/cozy-setup/gh-pages/assets/images/happycloud.png)

[Cozy](http://cozy.io) is a platform that brings all your web services in the
same private space.  With it, your web apps and your devices can share data
easily, providing you with a new experience. You can install Cozy on your own
hardware where no one profiles you.

## Community

You can reach the Cozy Community by:

* Chatting with us on IRC #cozycloud on irc.freenode.net
* Posting on our [Forum](https://groups.google.com/forum/?fromgroups#!forum/cozy-cloud)
* Posting issues on the [Github repos](https://github.com/mycozycloud/)
* Mentioning us on [Twitter](http://twitter.com/mycozycloud)
