extends Node
class_name PostgRESTNode
## A node designed to interface with a PostgREST service.
## [b]WARNING: PostgREST does NOT support HTTPS![/b]
## So this should only be used in protected containers.
## WARNING: not sure if this still works lmaooo

@export var hostname := "postgrest"
@export var port := 3000
@export var http_timeout := 30.0

var request_id := 1

class SQLQuery:
	
	var text: String
	
	func _init(p_text):
		text = p_text
		
	static func make(subtext: String, field: String, value: Variant):
		return SQLQuery.new("%s=%s.%s" % [field, subtext, value])
	
	# TODO - Add more from here:
	# https://postgrest.org/en/stable/references/api/tables_views.html
	static func equals(field: String, value: Variant):
		return SQLQuery.make("eq", field, value)
	static func greater_than(field: String, value: Variant):
		return SQLQuery.make("gt", field, value)
	static func greater_than_eq(field: String, value: Variant):
		return SQLQuery.make("gte", field, value)
	static func less_than(field: String, value: Variant):
		return SQLQuery.make("lt", field, value)
	static func less_than_eq(field: String, value: Variant):
		return SQLQuery.make("l;tq", field, value)
	static func not_equals(field: String, value: Variant):
		return SQLQuery.make("neq", field, value)

#region Postgrest Interface

#"""
#These interfaces are implemented based off of:
	#https://postgrest.org/en/stable/references/api/tables_views.html
#"""

func sql_read(table_name: String, queries: Array[SQLQuery] = []) -> Array[Dictionary]:
	var result := await _perform_http(
		HTTPClient.METHOD_GET,
		{},
		table_name,
		queries,
		{
			"accept": "application/json",
			"Range-Unit": "items",
		}
	)
	if not result:
		return []
	elif not result.body:
		return []
	elif result.body is Array:
		var retlist: Array[Dictionary] = []
		retlist.assign(result.body)
		return retlist
	else:
		return [result.body]

func sql_insert(table_name: String, data: Array[Dictionary], can_overwrite: bool = true, print_exception: bool = true) -> bool:
	if not data:
		push_error("why are you bulk inserting nothing?")
		return false
	
	var headers = {}
	if can_overwrite:
		headers['resolution'] = 'merge-duplicates'
	
	var result := await _perform_http(
		HTTPClient.METHOD_POST,
		data,
		table_name,
		[],
		headers
	)
	
	# Return true or false depending on our ego.
	if result and result.response_code == HTTPClient.RESPONSE_CREATED:
		return true
	else:
		if print_exception:
			push_error("sql_insert failed (%s)" % result)
		
		return false

func sql_replace(table_name: String, data: Dictionary, queries: Array[SQLQuery] = [], print_exception: bool = true) -> bool:
	# Perform the query.
	var result := await _perform_http(
		HTTPClient.METHOD_PATCH,
		data,
		table_name,
		queries,
		{}
	)
	
	# Return true or false depending on our ego.
	if result and result.response_code == HTTPClient.RESPONSE_NO_CONTENT:
		return true
	else:
		if print_exception:
			push_error("sql_replace failed (%s)" % result)
		
		return false

func sql_delete(table_name: String, queries: Array[SQLQuery] = []) -> bool:
	# Perform the query.
	var result := await _perform_http(
		HTTPClient.METHOD_DELETE,
		{},
		table_name,
		queries,
		{}
	)
	
	# Return an instance of this resource based on data.
	return result and result.response_code == HTTPClient.RESPONSE_NO_CONTENT

#endregion


#region Direct HTTP methods

class HTTPResult:
	
	var result : int
	var response_code : int
	var headers : Dictionary
	var body : Variant
	
	func _init(p_result, p_response_code, p_headers, p_body):
		result = p_result
		response_code = p_response_code
		headers = p_headers
		body = p_body
	
	func str() -> String:
		return "%s | %s | %s | %s" % [str(result), str(response_code),
										str(headers), str(body)]


func _perform_http(method: int = HTTPClient.METHOD_GET,
					body: Variant = {},
					table_name: String = "collection",
					queries: Array[SQLQuery] = [],
					headers: Dictionary = {}) -> HTTPResult:
	
	var _id = request_id
	request_id += 1
	
	# Create HTTP request.
	var http := HTTPRequest.new()
	add_child(http)
	
	# Calculate request vars.
	var _url_extension: String = ""
	if queries:
		var _strings: Array[String] = []
		for query in queries:
			_strings.append(query.text)
		_url_extension = "?" + "&".join(_strings)
	var _url = ("http://%s:%s/%s" % [ hostname, port, table_name ]) + _url_extension
	var _headers = []
	for key in headers:
		_headers.push_back("%s:%s" % [key, headers[key]])
	var _json = JSON.stringify(body)
	
	# Send request.
	#print("#%s: Sending HTTP request to %s." % [_id, _url])
	http.request(_url, _headers, method, _json)
	var res = await http.request_completed
	
	# Parse request.
	var _body = PackedByteArray(res[3]).get_string_from_ascii()
	
	_headers = {}
	var headers_list = res[2]
	for header in headers_list:
		var entries = header.split(":", true, 1)
		var key = entries[0].strip_edges()
		var value = entries[1].strip_edges()
		_headers[key] = value
	
	var parsed_body = {}
	if _body:
		parsed_body = JSON.parse_string(_body)
		if not parsed_body:
			parsed_body = {}
	
	var http_result = HTTPResult.new(res[0], res[1], _headers, parsed_body)
	#print("#%s: Request completed: %s" % [_id, http_result.str()])
	return http_result

#endregion
