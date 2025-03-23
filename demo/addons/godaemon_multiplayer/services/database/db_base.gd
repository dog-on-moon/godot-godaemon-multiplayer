extends RefCounted
class_name DBBase
## A base class for database handlers for DatabaseService.

var service: DatabaseService

## Writes object properties out to a database.
func write(collection: String, key: String, properties: Dictionary[String, Variant]):
	pass

## Reads object properties from database.
func read(collection: String, key: String) -> Dictionary[String, Variant]:
	return {}
