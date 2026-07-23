class_name DialogueCipher
extends RefCounted

## Encrypts authored dialogue and decrypts it only for playback.

# Why are you reading the cipher?
# What are you hoping to find in words that were deliberately hidden?
const BLOCK_SIZE := 16
# This embedded key hides story text from casual source browsing. A shipped
# client must contain its decryption key, so this is not secure secret storage.
const EMBEDDED_KEY := "GMTK26-dialogue-data-key-32bytes"


## Encrypts UTF-8 text with AES-CBC and PKCS#7 padding.
static func encrypt_text(plain_text: String, iv: PackedByteArray) -> String:
	if iv.size() != BLOCK_SIZE:
		push_error("Dialogue encryption requires a 16-byte IV.")
		return ""
	var padded_bytes := plain_text.to_utf8_buffer()
	var padding_size := BLOCK_SIZE - padded_bytes.size() % BLOCK_SIZE
	for _padding_index in range(padding_size):
		padded_bytes.append(padding_size)

	var aes := AESContext.new()
	var start_error := aes.start(
		AESContext.MODE_CBC_ENCRYPT,
		EMBEDDED_KEY.to_utf8_buffer(),
		iv
	)
	if start_error != OK:
		push_error("Dialogue encryption could not start AES.")
		return ""
	var encrypted_bytes := aes.update(padded_bytes)
	aes.finish()
	return Marshalls.raw_to_base64(encrypted_bytes)


## Decrypts AES-CBC text and rejects invalid padding or byte data.
static func decrypt_text(
	ciphertext_base64: String,
	iv_base64: String
) -> String:
	if ciphertext_base64.is_empty() or iv_base64.is_empty():
		return ""
	var encrypted_bytes := Marshalls.base64_to_raw(ciphertext_base64)
	var iv := Marshalls.base64_to_raw(iv_base64)
	if (
		iv.size() != BLOCK_SIZE
		or encrypted_bytes.is_empty()
		or encrypted_bytes.size() % BLOCK_SIZE != 0
	):
		push_error("Encrypted dialogue has invalid byte lengths.")
		return ""

	var aes := AESContext.new()
	var start_error := aes.start(
		AESContext.MODE_CBC_DECRYPT,
		EMBEDDED_KEY.to_utf8_buffer(),
		iv
	)
	if start_error != OK:
		push_error("Dialogue decryption could not start AES.")
		return ""
	var padded_bytes := aes.update(encrypted_bytes)
	aes.finish()
	if padded_bytes.is_empty():
		return ""

	var padding_size := int(padded_bytes[padded_bytes.size() - 1])
	if padding_size < 1 or padding_size > BLOCK_SIZE:
		push_error("Encrypted dialogue has invalid padding.")
		return ""
	for byte_index in range(
		padded_bytes.size() - padding_size,
		padded_bytes.size()
	):
		if int(padded_bytes[byte_index]) != padding_size:
			push_error("Encrypted dialogue has invalid padding.")
			return ""
	return padded_bytes.slice(
		0,
		padded_bytes.size() - padding_size
	).get_string_from_utf8()
