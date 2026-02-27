

    // SATURN V OUTBOARD ENGINE GIMBAL CONTROLLER (24)
    // Fixed gimbal limiting for inward-pointing engines
    // Supports S-IC (stage 1) and S-II (stage 2) engines
     
    // Engine positions (viewed from below, looking up):
    //   Engine 4 (TL)       Engine 1 (TR)
    //        315°               45°
    //   
    //   Engine 3 (BL)       Engine 2 (BR)
    //       225°              135°
     
    // -------------------------------
    // USER SETTINGS
    // -------------------------------
     
    SET DEBUG_MODE TO TRUE.              // Set to TRUE for periodic debug output, FALSE to disable
    SET DEBUG_INTERVAL TO 10.            // Print debug info every N iterations (only if DEBUG_MODE is TRUE)
    SET INWARD_WEDGE_HALF_WIDTH TO 40.0. // Half-width of inward restriction wedge (degrees)
                                         // Full wedge = 80°, leaving 280° for normal operation
                                         // With 5° deadzone on each side: 45° - 5° = 40°
    SET CMD_MAGNITUDE_THRESHOLD TO 0.01. // Minimum command magnitude to consider as intentional input
    SET LOOP_WAIT_TIME TO 0.02.          // Main loop iteration wait time (seconds)
     
    // Engine angle offsets (in degrees, relative to vehicle frame)
    // These represent the INWARD direction for each engine (i.e., toward center)
    // Engine 1 at physical position  45° gimbals inward toward 225°
    // Engine 2 at physical position 135° gimbals inward toward 315°
    // Engine 3 at physical position 225° gimbals inward toward 45°
    // Engine 4 at physical position 315° gimbals inward toward 135°
     
    LOCAL ENGINE_INWARD_ANGLES IS LEXICON(
        "SIC_1", 225,
        "SIC_2", 315,
        "SIC_3", 45,
        "SIC_4", 135,
        "SII_1", 225,
        "SII_2", 315,
        "SII_3", 45,
        "SII_4", 135
    ).
     
    // Helper function to check if engine object is valid
    FUNCTION isEngineValid {
        PARAMETER obj.
        RETURN obj <> 0.
    }
     
    // Normalize an angle to -180 to +180 range
    FUNCTION normalizeAngle {
        PARAMETER angle.
        RETURN MOD(angle + 180, 360) - 180.
    }
     
    // Calculate angular distance between two angles (always returns 0-180)
    FUNCTION angularDistance {
        PARAMETER from, to.
        LOCAL diff IS ABS(from - to).
        RETURN CHOOSE (360 - diff) IF diff > 180 ELSE diff.
    }
     
    // Calculate how much inward deflection is requested (0.0 to 1.0)
    // Returns the magnitude of inward request, weighted by how deep into the inward wedge we are
    FUNCTION calcInwardComponent {
        PARAMETER pitch.     // -1 to +1 (positive = pitch up)
        PARAMETER yaw.      // -1 to +1 (positive = yaw right)
        PARAMETER inwardAngle. // engine's inward angle in degrees (the direction gimbal goes inward)
     
        LOCAL cmdMag IS SQRT(pitch * pitch + yaw * yaw).
     
        IF cmdMag < CMD_MAGNITUDE_THRESHOLD { RETURN 0.0. }  // No meaningful command
     
        // Get command direction in degrees (0=up, 90=right, 180=down, 270=left)
        // ARCTAN2(yaw, pitch) maps: pitch=+1,yaw=0 → 0°, pitch=0,yaw=+1 → 90°, etc.
        LOCAL cmdAngle IS ARCTAN2(yaw, pitch).
        SET cmdAngle TO MOD(cmdAngle + 360, 360).  // Convert to 0-360 range
     
        // Find angular distance from command to the inward direction
        LOCAL angDiff IS angularDistance(cmdAngle, inwardAngle).
     
        // angDiff = 0 means command is pointing inward (would cause inward gimbal)
        // angDiff = INWARD_WEDGE_HALF_WIDTH means at edge of restriction zone
        // angDiff > INWARD_WEDGE_HALF_WIDTH means outside restriction zone
     
        IF angDiff <= INWARD_WEDGE_HALF_WIDTH {
            // Inside inward wedge: return normalized distance into wedge (0 to 1)
            // At center (0°): return 1.0
            // At edge (INWARD_WEDGE_HALF_WIDTH): return 0.0
            RETURN (INWARD_WEDGE_HALF_WIDTH - angDiff) / INWARD_WEDGE_HALF_WIDTH.
        } ELSE {
            RETURN 0.0.  // Outside inward wedge
        }
    }
     
    // Determine if an engine would gimbal inward (binary check)
    FUNCTION wouldGimbalInward {
        PARAMETER pitch.
        PARAMETER yaw.
        PARAMETER engName.
     
        IF NOT ENGINE_INWARD_ANGLES:HASKEY(engName) {
            RETURN FALSE.  // Unknown engine, assume safe
        }
     
        LOCAL inwardAngle IS ENGINE_INWARD_ANGLES[engName].
        LOCAL inwardComp IS calcInwardComponent(pitch, yaw, inwardAngle).
     
        // Binary: any inward component means restrict
        RETURN inwardComp > 0.0.
    }
     
    // ENGINE DISCOVERY
    FUNCTION scanEngines {
        LIST ENGINES IN engs.
     
        LOCAL engDict IS LEXICON().
        LOCAL validTags IS LIST("SIC_1", "SIC_2", "SIC_3", "SIC_4", "SII_1", "SII_2", "SII_3", "SII_4").
     
        FOR e IN engs {
            LOCAL tag IS e:TAG.
            IF validTags:CONTAINS(tag) {
                SET engDict[tag] TO e.
            }
        }
     
        RETURN engDict.
    }
     
    PRINT "Scanning for Saturn V outboard gimbal engines...".
    LOCAL allEngines IS scanEngines().
     
    // Verify we found the expected engines (at least some of them)
    LOCAL engCount IS 0.
    FOR engName IN allEngines:KEYS {
        SET engCount TO engCount + 1.
    }
     
    PRINT "Found " + engCount + " gimbal engine(s):".
    FOR engName IN allEngines:KEYS {
        PRINT "  " + engName.
    }
     
    WAIT 0.5.
     
    // Main control loop
     
    LOCAL iterCount IS 0.
     
    UNTIL FALSE {
        LOCAL pilotPitch IS SHIP:CONTROL:PILOTPITCH.
        LOCAL pilotYaw IS SHIP:CONTROL:PILOTYAW.
        SET iterCount TO iterCount + 1.
     
        LOCAL cmdMag IS SQRT(pilotPitch * pilotPitch + pilotYaw * pilotYaw).
        LOCAL cmdAngle IS 0.
        IF cmdMag > CMD_MAGNITUDE_THRESHOLD {
            SET cmdAngle TO ARCTAN2(pilotYaw, pilotPitch).
            SET cmdAngle TO MOD(cmdAngle + 360, 360).
        }
     
        FOR engName IN allEngines:KEYS {
            LOCAL eng IS allEngines[engName].
     
            IF isEngineValid(eng) {
                // Check if this engine would gimbal inward
                LOCAL inwardRestricted IS wouldGimbalInward(pilotPitch, pilotYaw, engName).
                SET eng:GIMBAL:YAW TO NOT inwardRestricted.
                SET eng:GIMBAL:PITCH TO NOT inwardRestricted.
            }
        }
     
        // Debug output every N iterations (if enabled)
        IF DEBUG_MODE AND MOD(iterCount, DEBUG_INTERVAL) = 0 {
            CLEARSCREEN.
            PRINT "Saturn V gimbal control loop.".
            PRINT "=== Debug [Iteration " + iterCount + "] ===".
            PRINT "Commands - Pitch: " + ROUND(pilotPitch, 3) + " Yaw: " + ROUND(pilotYaw, 3).
            PRINT "Command angle: " + ROUND(cmdAngle, 1) + "° (0=up, 90=right, 180=down, 270=left)".
            PRINT " ".
     
            FOR engName IN allEngines:KEYS {
                LOCAL eng IS allEngines[engName].
                IF isEngineValid(eng) {
                    LOCAL inward IS calcInwardComponent(pilotPitch, pilotYaw, ENGINE_INWARD_ANGLES[engName]).
                    LOCAL restricted IS wouldGimbalInward(pilotPitch, pilotYaw, engName).
                    LOCAL limit IS eng:GIMBAL:LIMIT.
                    PRINT "  " + engName + "-Inward: " + ROUND(inward, 3) + 
                          "|Restricted: " + restricted + "|Limit: " + ROUND(limit, 1) + "°".
                }
            }
        }
     
        WAIT LOOP_WAIT_TIME.
    }

