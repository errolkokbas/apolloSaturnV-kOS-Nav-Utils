

    // =====================================================
    // CSM RCS AXIS-SWAP CONTROLLER (AUTO LM DETECTION)
    // -----------------------------------------------------
    // - Swaps PITCH/YAW between quads depending on LM presence
    // - Only affects four CSM RCS quads (tags set in editor)
    // - Roll is untouched
    // =====================================================
     
    // ---------- CONFIG ----------
    // Part tags for your CSM RCS quads
    SET topTag       TO "CSM_TOP".
    SET bottomTag    TO "CSM_BOTTOM".
    SET portTag      TO "CSM_PORT".
    SET starboardTag TO "CSM_STARBOARD".
     
    // Part tag for the LM ascent module
    SET lmTag TO "LEM_MODULE".
     
    // ---------- HELPER FUNCTION: find quad by tag ----------
    FUNCTION findQuad {
        PARAMETER tag.
        // Find the part with matching tag and return the part itself
        FOR p IN SHIP:PARTS {
            IF p:TAG = tag {
                RETURN p.
            }
        }
        PRINT "ERROR: Missing part with tag " + tag.
        RETURN "NULL".
    }
     
    // ---------- GRAB THE QUADS ----------
    SET quadTop       TO findQuad(topTag).
    SET quadBottom    TO findQuad(bottomTag).
    SET quadPort      TO findQuad(portTag).
    SET quadStarboard TO findQuad(starboardTag).
     
    IF quadTop = "NULL" OR quadBottom = "NULL" OR quadPort = "NULL" OR quadStarboard = "NULL" {
        PRINT "One or more quads missing - aborting.".
        SHUTDOWN.
    }
     
    // ---------- MODE FUNCTIONS ----------
    FUNCTION setCSMSolo {
        // CSM ONLY: Top/Bottom = Pitch, Port/Starboard = Yaw
        SET quadTop:PITCHENABLED       TO TRUE.
        SET quadBottom:PITCHENABLED    TO TRUE.
        SET quadTop:YAWENABLED         TO FALSE.
        SET quadBottom:YAWENABLED      TO FALSE.
     
        SET quadPort:PITCHENABLED      TO FALSE.
        SET quadStarboard:PITCHENABLED TO FALSE.
        SET quadPort:YAWENABLED        TO TRUE.
        SET quadStarboard:YAWENABLED   TO TRUE.
    }
     
    FUNCTION setCSMLM {
        // CSM + LM: Top/Bottom = Yaw, Port/Starboard = Pitch
        SET quadTop:PITCHENABLED       TO FALSE.
        SET quadBottom:PITCHENABLED    TO FALSE.
        SET quadTop:YAWENABLED         TO TRUE.
        SET quadBottom:YAWENABLED      TO TRUE.
     
        SET quadPort:PITCHENABLED      TO TRUE.
        SET quadStarboard:PITCHENABLED TO TRUE.
        SET quadPort:YAWENABLED        TO FALSE.
        SET quadStarboard:YAWENABLED   TO FALSE.
    }
     
    // ---------- INITIAL STATE ----------
    SET lmAttached TO FALSE.
    setCSMSolo().
    PRINT "CSM RCS axis-swap controller active.".
    PRINT "Automatic LM detection mode.".
     
    // ---------- EDGE DETECTION LOOP ----------
    SET lastLMState TO FALSE.
     
    UNTIL FALSE {
        // Detect LM presence
        SET lmFound TO FALSE.
        FOR p IN SHIP:PARTS {
            IF p:TAG = lmTag {
                SET lmFound TO TRUE.
                WAIT 0.1.  // pause to prevent CPU overload, keep checking for dock/undock events
            }
        }
     
        // Rising/falling edge detection
        IF lmFound AND NOT lastLMState {
            // LM just appeared / docked
            setCSMLM().
            PRINT "LM detected - switching to CSM+LM mode.".
        } ELSE IF NOT lmFound AND lastLMState {
            // LM just removed / undocked
            setCSMSolo().
            PRINT "LM undocked - switching to CSM solo mode.".
        }
     
        // Save state for next iteration
        SET lastLMState TO lmFound.
        WAIT 0.1.  // Small sleep to reduce CPU usage
    }

