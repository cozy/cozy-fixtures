# Cozy-fixtures
This tool will help you data fixtures for your Cozy development.

# Usage

## CLI
When you develop an application you might want to feed the Data System with data.

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
    dirPath: 'path/to/fixtures' # default is './tests/fixtures/'
    doctypeTarget: 'doctypeName' # default is null
    silent: true # default is false
    callback: youCallback # default is null
```