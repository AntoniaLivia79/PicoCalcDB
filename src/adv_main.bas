' =====================================================================
' adv_main.bas - entry point of the text adventure.
' Program = dblib + adv_model + adv_view + adv_ctrl + this file.
' The game state lives in collection "adv" in B:/db/; the world file
' is only read when a new game starts.
' =====================================================================
DbInit "B:/db"
GcRun "B:/adv/world.jsonl"
END
