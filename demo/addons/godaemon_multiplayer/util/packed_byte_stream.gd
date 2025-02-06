extends RefCounted
class_name PackedByteStream
## A helper class for dynamically encoding/decoding PackedByteArrays.

## The internal data of the PackedByteStream.
var data: PackedByteArray

## The byte cursor position.
var c := 0

## A flag that's set to false if there was an error during read/write.
var valid := true

#region Write

## Sets up the stream writing. The max size must be declared here.
func setup_write(size: int):
	assert(size >= 0)
	c = 0
	data = PackedByteArray()
	data.resize(size)

## Allocate additional space for writing.
func allocate(size: int):
	data.resize(data.size() + size)

func write_double(value: float):
	if (c + 8) > data.size():
		valid = false
		return
	data.encode_double(c, value)
	c += 8

func write_float(value: float):
	if (c + 4) > data.size():
		valid = false
		return
	data.encode_float(c, value)
	c += 4

func write_half(value: float):
	if (c + 2) > data.size():
		valid = false
		return
	data.encode_half(c, value)
	c += 2

func write_s8(value: int):
	if (c + 1) > data.size():
		valid = false
		return
	data.encode_s8(c, value)
	c += 1

func write_s16(value: int):
	if (c + 2) > data.size():
		valid = false
		return
	data.encode_s16(c, value)
	c += 2

func write_s32(value: int):
	if (c + 4) > data.size():
		valid = false
		return
	data.encode_s32(c, value)
	c += 4

func write_s64(value: int):
	if (c + 8) > data.size():
		valid = false
		return
	data.encode_s64(c, value)
	c += 8

func write_u8(value: int):
	if (c + 1) > data.size():
		valid = false
		return
	data.encode_u8(c, value)
	c += 1

func write_u16(value: int):
	if (c + 2) > data.size():
		valid = false
		return
	data.encode_u16(c, value)
	c += 2

func write_u32(value: int):
	if (c + 4) > data.size():
		valid = false
		return
	data.encode_u32(c, value)
	c += 4

func write_u64(value: int):
	write_s64(value)  # Godot's int is a signed64

func write_signed(value: int, bytes: int):
	match bytes:
		1:
			write_s8(value)
		2:
			write_s16(value)
		4:
			write_s32(value)
		8:
			write_s64(value)
		_:
			valid = false

func write_unsigned(value: int, bytes: int):
	match bytes:
		1:
			write_u8(value)
		2:
			write_u16(value)
		4:
			write_u32(value)
		8:
			write_u64(value)
		_:
			valid = false

func write_bytes(bytes: PackedByteArray):
	if (c + bytes.size()) > data.size():
		valid = false
		return
	for i in bytes.size():
		data[c + i] = bytes[i]
	c += bytes.size()

func write_variant(value: Variant, allow_objects := false):
	var data := var_to_bytes(value) if not allow_objects else var_to_bytes_with_objects(value)
	write_bytes(data)

#endregion

#region Read

## Sets up the stream read.
func setup_read(_data: PackedByteArray):
	c = 0
	data = _data

func read_double() -> float:
	if (c + 8) > data.size():
		valid = false
		return 0.0
	c += 8
	return data.decode_double(c - 8)

func read_float() -> float:
	if (c + 4) > data.size():
		valid = false
		return 0.0
	c += 4
	return data.decode_float(c - 4)

func read_half() -> float:
	if (c + 2) > data.size():
		valid = false
		return 0.0
	c += 2
	return data.decode_half(c - 2)

func read_s8() -> int:
	if (c + 1) > data.size():
		valid = false
		return 0
	c += 1
	return data.decode_s8(c - 1)

func read_s16() -> int:
	if (c + 2) > data.size():
		valid = false
		return 0
	c += 2
	return data.decode_s16(c - 2)

func read_s32() -> int:
	if (c + 4) > data.size():
		valid = false
		return 0
	c += 4
	return data.decode_s32(c - 4)

func read_s64() -> int:
	if (c + 8) > data.size():
		valid = false
		return 0
	c += 8
	return data.decode_s64(c - 8)

func read_u8() -> int:
	if (c + 1) > data.size():
		valid = false
		return 0
	c += 1
	return data.decode_u8(c - 1)

func read_u16() -> int:
	if (c + 2) > data.size():
		valid = false
		return 0
	c += 2
	return data.decode_u16(c - 2)

func read_u32() -> int:
	if (c + 4) > data.size():
		valid = false
		return 0
	c += 4
	return data.decode_u32(c - 4)

func read_u64() -> int:
	return read_s64()  # Godot's int is a signed64

func read_signed(bytes: int) -> int:
	match bytes:
		1:
			return read_s8()
		2:
			return read_s16()
		4:
			return read_s32()
		8:
			return read_s64()
		_:
			valid = false
			return 0

func read_unsigned(bytes: int) -> int:
	match bytes:
		1:
			return read_u8()
		2:
			return read_u16()
		4:
			return read_u32()
		8:
			return read_u64()
		_:
			valid = false
			return 0

func read_bytes(size: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	if (c + size) > data.size():
		valid = false
		return bytes
	bytes.resize(size)
	for i in size:
		bytes[i] = data[c + i]
	c += size
	return bytes

func read_variant(allow_objects := false) -> Variant:
	var size := data.decode_var_size(c)
	if (c + size) > data.size():
		valid = false
		return null
	var variant := data.decode_var(c, allow_objects)
	c += size
	return variant

#endregion

## Returns the size of a variant.
func get_var_size(variant: Variant, allow_objects := false) -> int:
	return var_to_bytes(variant).size() if not allow_objects else var_to_bytes_with_objects(variant).size()
