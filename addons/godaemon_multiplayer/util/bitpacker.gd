extends RefCounted
class_name Bitpacker
## Reads and parses bits from an integer.

## The current value within a Bitpacker.
var value := 0

## The current bit index we're writing to/reading from.
var idx := 0

## Writes the provided value in a certain amount of bits.
func write(bits: int, _value: int):
	assert(_value >= 0)
	assert(bits > 0)
	assert((idx + bits) <= 64)
	assert(_value < (2 ** bits))
	value |= (_value << idx)
	idx += bits

## Reads out a value from a certain amount of bits.
func read(bits: int) -> int:
	assert(bits > 0)
	assert((idx + bits) <= 64)
	var bitmask := ((2 ** bits) - 1) << idx
	var result := (value & bitmask) >> idx
	idx += bits
	return result

## Sets up a Bitpacker for writing a bitstring.
static func writer() -> Bitpacker:
	return Bitpacker.new()

## Sets up a Bitpacker for reading a bitstring.
static func reader(_value: int) -> Bitpacker:
	var bp := Bitpacker.new()
	bp.value = _value
	return bp

## Short test suite because I don't trust this class
static func _test():
	var bp := Bitpacker.writer()
	
	bp.write(1, 0)
	bp.write(2, 1)
	bp.write(3, 3)
	bp.write(4, 12)
	bp.write(5, 30)
	
	var reader := Bitpacker.reader(bp.value)
	
	assert(reader.read(1) == 0)
	assert(reader.read(2) == 1)
	assert(reader.read(3) == 3)
	assert(reader.read(4) == 12)
	assert(reader.read(5) == 30)
