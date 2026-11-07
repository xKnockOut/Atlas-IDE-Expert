unit Atlas.Common.Rules.Catalog.Data.De.Architecture;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  cCatalogLinesDeArchitecture: array[0..66] of string = (
    '{',
    '      "id": "forbidden-uses",',
    '      "name": "Verbotene uses-Beziehung",',
    '      "description": "Ein uses-Eintrag verletzt eine Schichtregel unter \"layers\" in atlas.json, z. B. darf *.Common.* nicht Vcl.* verwenden.",',
    '      "options": [',
    '        {',
    '          "name": "layers",',
    '          "description": "Schichtregeln: [{\"from\": Glob, \"deny\": [Globs], \"allow\": [Globs]}]."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "uses-cycle",',
    '      "name": "Zirkuläre Unit-Referenz über uses",',
    '      "description": "Ein uses-Eintrag führt über die uses-Listen anderer Units zurück zur eigenen Unit. Liegt jede Kante des Zyklus im interface-Abschnitt, lehnt der Compiler ihn ab (wie F2047; eine ' +
    'Unit, die sich selbst nennt, wie F2092), und der Befund ist ein Fehler; nur dann nennt die Meldung den Code (#1383); Zyklen mit mindestens einer implementation-Kante erlaubt Delphi, sie koppeln die Un' +
    'its aber eng (Initialisierungsreihenfolge, Neuübersetzen, Testen) und erscheinen mit dem Schweregrad der Regel (Option implementation). Die Meldung zeigt den vollständigen kürzesten Pfad (A → B → C → ' +
    'A), der Befund-Hover jede Kante mit ihrem Abschnitt. Grundlage ist der gemeinsame Uses-Graph über den Symbolindex (#268), inaktive Zweige der bedingten Kompilierung ausgeblendet; die geprüfte Unit zäh' +
    'lt mit ihrem Editor-Stand. Still ohne Projekte (Linter, Datei ohne Projekt), solange Projekte laden oder der Index unvollständig ist, und für Units, die der Uses-Graph nicht kennt.",',
    '      "options": [',
    '        {',
    '          "name": "implementation",',
    '          "description": "Auch Zyklen mit mindestens einer Kante im implementation-Abschnitt melden (vom Compiler erlaubt)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "architecture-role-import",',
    '      "name": "Import verletzt die Rollenmatrix",',
    '      "description": "Ein uses-Eintrag verletzt die Importmatrix des Rollenkonzepts (Ausgabeartefakt, Feature, Rolle: Contract, Internals, Providers, Adapters, Composition, Hosting). Standardmäßig aus' +
    '; in atlas.json mit der Option \"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Quelle -> Ziel\"-Globs. Testunits (mit DUnitX, DUnit oder TestInsight im uses) prüft die Rege' +
    'l nicht.",',
    '      "options": [',
    '        {',
    '          "name": "prefixes",',
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"; ohne Angabe meldet die Regel nichts."',
    '        },',
    '        {',
    '          "name": "hostRoles",',
    '          "description": "Erste Namenssegmente der Host-Units ohne Präfix."',
    '        },',
    '        {',
    '          "name": "allow",',
    '          "description": "Genehmigte Ausnahmen \"Quelle -> Ziel\" (beide Globs)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "architecture-contract-content",',
    '      "name": "Klasse in einer Contract-Unit",',
    '      "description": "Eine Contract-Unit deklariert im interface eine Klasse. Contracts enthalten nur Records, Interfaces, Aufzählungen und Ausnahmen. Standardmäßig aus; in atlas.json mit der Option \' +
    '"prefixes\" einschalten. Genehmigte Ausnahmen stehen unter \"allow\" als \"Unit.Typ\"-Globs. Testunits prüft die Regel nicht.",',
    '      "options": [',
    '        {',
    '          "name": "prefixes",',
    '          "description": "Präfixe der Ausgabeartefakte, z. B. \"Atlas.Common\"."',
    '        },',
    '        {',
    '          "name": "allow",',
    '          "description": "Genehmigte Ausnahmen \"Unit.Typ\" als Glob."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "forbidden-symbol",',
    '      "name": "Verbotenes Symbol verwendet",',
    '      "description": "Eine Liste unter \"symbols\" in atlas.json verbietet Routinen, Typen, Konstanten, Felder, Properties, Aufzählungswerte oder Bezeichner, jeweils mit Meldung und Ersatz. Verglichen' +
    ' wird über die Namensauflösung, nicht über Text: System.SysUtils.FileExists trifft auch FileExists, aber nicht eine eigene Methode gleichen Namens. Ein Eintrag darf den Namen ab einer Punktgrenze kürz' +
    'en (TThread.Queue) und * enthalten. Bezeichner aus System ohne Quelltext (Writeln, Halt) gelten als System.<Name>. Ist der linke Teil eines qualifizierten Namens gar nicht auflösbar (Unit nicht indexi' +
    'ert), wird der geschriebene Name mit dem Ende des Eintrags verglichen. Je Eintrag: kind (routine, type, constant, field, property, enumValue, identifier = nach Namen ohne Auflösung), message, replacem' +
    'ent, severity, units (Muster der Unit-Namen, \"!\" schließt aus), firstArgument (nur mit diesem ersten Argument, z. B. nil) und allowFirstArgument (erlaubt mit diesem ersten Argument, z. B. ErrOutput)' +
    '; beide vergleichen den Text des Arguments oder den Namen seines Typs (TextFile). Standard aus und ohne Liste stumm; im Profil strict an. Sicherheit hoch. Schnellkorrektur: durch den konfigurierten Er' +
    'satz ersetzen.",',
    '      "options": [',
    '        {',
    '          "name": "symbols",',
    '          "description": "Tabelle der verbotenen Symbole, ein Objekt je Eintrag: name (qualifiziert, * erlaubt), kind (routine, type, constant, field, property, enumValue oder identifier), message, re' +
    'placement, severity, units (Muster, ! schließt aus), firstArgument und allowFirstArgument (Texte oder Typnamen des Arguments)."',
    '        }',
    '      ]',
    '    }');

implementation

end.
