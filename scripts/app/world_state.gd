class_name WorldState
extends Node

var current_ir: Variant = null
## -1 means that no World IR has been committed yet. The initial successful
## world commit therefore becomes revision 0.
var current_ir_revision: int = -1
var runtime_facts: Array = []
var spatial_payloads: Dictionary = {}

func runtime_context() -> Dictionary:
	return {"version": "1", "facts": runtime_facts.duplicate(true)}

func candidate_facts_after_ops(ops: Array) -> Array:
	var candidate: Array = runtime_facts.duplicate(true)
	for op in ops:
		if String(op.get("op", "")) != "clear":
			continue
		var fact_id := String(op.get("runtime_fact_id", ""))
		candidate = candidate.filter(func(fact): return String(fact.get("id", "")) != fact_id)
	return candidate

func next_ir_revision() -> int:
	return current_ir_revision + 1

func commit_revision(new_ir: Dictionary, new_facts: Array, revision: int) -> bool:
	if revision != next_ir_revision():
		return false
	current_ir = new_ir.duplicate(true)
	runtime_facts = new_facts.duplicate(true)
	current_ir_revision = revision
	var live_ids := {}
	for fact in runtime_facts:
		live_ids[String(fact.get("id", ""))] = true
	for fact_id in spatial_payloads.keys():
		if not live_ids.has(String(fact_id)):
			spatial_payloads.erase(fact_id)
	return true

func commit(new_ir: Dictionary, new_facts: Array) -> void:
	var committed := commit_revision(new_ir, new_facts, next_ir_revision())
	assert(committed)

func add_runtime_fact(fact: Dictionary, payload: Dictionary = {}) -> void:
	var fact_id := String(fact.get("id", ""))
	if not fact_id.is_empty():
		runtime_facts = runtime_facts.filter(func(existing): return String(existing.get("id", "")) != fact_id)
	runtime_facts.append(fact.duplicate(true))
	if not fact_id.is_empty() and not payload.is_empty():
		spatial_payloads[fact_id] = payload.duplicate(true)
