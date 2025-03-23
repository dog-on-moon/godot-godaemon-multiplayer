extends DBBase
class_name PostgresDB
## A basic DB implementation using binary text files in the user directory.
# FIXME - untested lol, probably will break on property serialization

var postgres: PostgRESTNode:
	get:
		if not postgres:
			if not service: return null
			postgres = PostgRESTNode.new()
			service.add_child(postgres)
		return postgres

func write(collection: String, key: String, properties: Dictionary[String, Variant]):
	properties['_key'] = key
	if not await postgres.sql_insert(collection, [properties]):
		push_warning("PostgresDB.write Failed")

func read(collection: String, key: String) -> Dictionary[String, Variant]:
	var result := await postgres.sql_read(collection, [PostgRESTNode.SQLQuery.equals('_key', key)])
	if result:
		var properties: Dictionary[String, Variant] = {}
		properties.assign(result[0])
		return properties
	else:
		return {}
