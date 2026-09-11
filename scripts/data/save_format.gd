class_name SaveFormat
extends RefCounted

## The save contract (SPEC §7), shared by GameState, SaveManager and the
## backend. The server enforces the same byte cap — see backend/main.py.

const VERSION := 1
const MAX_BLOB_BYTES := 256 * 1024
const SLOT_COUNT := 3
