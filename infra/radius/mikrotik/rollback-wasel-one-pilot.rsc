# WASEL One pilot rollback. Mirrors mikrotik/wasel-one-pilot.rsc.template:
#   1. disables only the RADIUS record tagged WASEL_ONE_PILOT;
#   2. sets use-radius=no on the exact Hotspot profile the template changed
#      (the template refuses to run on a profile that already had
#      use-radius=yes, so "no" IS the pre-change value). Leaving use-radius=yes
#      with no enabled RADIUS server would make every Hotspot login fail.
#
# radius-accounting and radius-interim-update are inert while use-radius=no and
# are left as they are. login-by and ssl-certificate are NOT reverted: the
# script cannot know their previous values and does not guess. Restore those
# two from the configuration export captured before the change.

:local waselRadius [/radius find where comment="WASEL_ONE_PILOT"]
:local waselState [/system script find where name="wasel-one-pilot-state"]
:if (([:len $waselRadius] = 0) && ([:len $waselState] = 0)) do={ :error "WASEL_ONE_PILOT RADIUS entry and rollback state not found; nothing to roll back" }

:if ([:len $waselRadius] != 0) do={
    /radius disable $waselRadius
    :put "WASEL One RADIUS entry disabled."
}

:if ([:len $waselState] = 0) do={
    :put "WARNING: wasel-one-pilot-state not found (applied with an older template)."
    :put "Set use-radius=no on the pilot Hotspot profile manually, then restore it from the saved export."
} else={
    :local waselHotspotProfile [/system script get $waselState comment]
    :local waselProfileId [/ip hotspot profile find where name=$waselHotspotProfile]
    :if ([:len $waselProfileId] = 0) do={
        :put ("WARNING: Hotspot profile not found: " . $waselHotspotProfile)
        :put "Rollback state kept. Set use-radius=no on the renamed profile manually."
    } else={
        /ip hotspot profile set $waselProfileId use-radius=no
        /system script remove $waselState
        :put ("WASEL One: use-radius=no restored on Hotspot profile " . $waselHotspotProfile)
    }
}

:put "Restore login-by and ssl-certificate from the saved export if they were changed by the pilot."
