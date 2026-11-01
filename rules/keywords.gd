class_name Keywords
extends RefCounted

## Named behaviors the duel engine actually implements.
## Silence clears the keyword list; nothing here is a hidden one-off.

const ALL := ["rush", "guard", "ward", "venom", "pierce", "siphon", "breach", "twinstrike"]

const TEXT := {
	"rush": "Can attack the turn it is played.",
	"guard": "Enemy units must attack a Guard before the warden, unless they have Breach.",
	"ward": "The first damage this would take is prevented, then Ward is lost.",
	"venom": "If this deals combat damage to a unit, destroy that unit.",
	"pierce": "Excess combat damage to a unit hits that player's warden.",
	"siphon": "Heal your warden for the combat damage this deals to units.",
	"breach": "May attack the enemy warden while they control a Guard.",
	"twinstrike": "May attack twice each turn.",
}
