unit Cm.W1054b;

// W1054 User-defined warning ($MESSAGE WARN)
// Erwartet: -
// Gegenfall zu Cm.W1054 (#1379): $MESSAGE in einem Zweig, der nicht übersetzt
// wird.

interface

implementation

{$IFDEF CM_GIBT_ES_NICHT}
{$MESSAGE WARN 'Eigene Warnung'} // <- ohne Meldung
{$MESSAGE HINT 'Eigener Hinweis'}
{$ENDIF}

end.
