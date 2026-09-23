# Disables only the RADIUS record tagged by the WASEL One pilot template.
# The operator must restore the Hotspot profile values from the pre-change export.

:local waselRadius [/radius find where comment="WASEL_ONE_PILOT"]
:if ([:len $waselRadius] = 0) do={ :error "WASEL_ONE_PILOT RADIUS entry not found" }
/radius disable $waselRadius
:put "WASEL One RADIUS entry disabled. Restore the Hotspot profile from the saved export."
