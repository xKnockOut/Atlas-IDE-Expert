unit Atlas.Core.Settings.SchemaData;

// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json;
// nicht von Hand ändern. JSON-Schema von atlas.json für den Einstellungsdialog (#227).

interface

/// <summary>Inhalt von atlas.schema.json.</summary>
function AtlasSchemaJson: string;

implementation

const
  cChunks: array[0..358] of string = (
    '{' + #10 + '  "$schema": "http://json-schema.org/draft-07/schema#",' + #10 + '  "title": "Atlas-Konfiguration",' +
      #10 + '  "description": "Einstellungen für Atlas. Jeder Schlüssel hat genau einen Ort (x-scope): ' +
      '\"project\" in atlas.json im Projektordner (Atlas › Projekt-Einstellungen), \"global\" in ' +
      '%APPDATA%\\Atlas\\settings.json für alle Projekte (Tools › Optionen › Atlas). \"both\" an ' +
      'beiden Orten: Die globale Datei gilt für alle Projekte, atlas.json übersteuert je Glied (r' +
      'ules: je Regel). Ein Schlüssel am falschen Ort wird ignoriert und gemeldet.",' + #10,
    '  "x-description-en": "Settings for Atlas. Each key has exactly one place (x-scope): \"pro' +
      'ject\" in atlas.json in the project folder (Atlas › Project settings), \"global\" in %APPD' +
      'ATA%\\Atlas\\settings.json for all projects (Tools › Options › Atlas). \"both\" in both pl' +
      'aces: the global file applies to all projects, atlas.json overrides per member (rules: per' +
      ' rule). A key in the wrong place is ignored and reported.",' + #10 + '  "type": "object",' + #10 +
      '  "properties": {' + #10 + '    "$schema": {' + #10 + '      "type": "string"' + #10 + '    },' + #10 +
      '    "delphiVersion": {' + #10 + '      "type": "string",' + #10 + '      "pattern": "^[0-9]+(\\.[0-9]+)?$",' +
      #10,
    '      "description": "Delphi-Version als Produktnummer (\"13\", \"12\", \"10.4\") oder wie' +
      ' in der Registry (\"37.0\" für Delphi 13, \"23.0\" für Delphi 12). Leer: passend zur Proje' +
      'ctVersion der .dproj, sonst die nächsthöhere, sonst die neueste installierte Version. Ist ' +
      'die eingestellte Version nicht installiert, warnt das Serverprotokoll mit der Stelle in se' +
      'ttings.json, und die automatische Wahl greift. Ohne jede Installation (Linux, CI) gilt die' +
      ' eingestellte bzw. zur ProjectVersion passende, sonst die neueste bekannte Version, nur fü' +
      'r CompilerVersion und VERxxx. In der IDE gilt immer die laufende IDE.",' + #10,
    '      "x-description-en": "Delphi version as product number (\"13\", \"12\", \"10.4\") or ' +
      'as in the registry (\"37.0\" for Delphi 13, \"23.0\" for Delphi 12). Empty: matching the P' +
      'rojectVersion of the .dproj, otherwise the next higher one, otherwise the newest installed' +
      ' version. If the configured version is not installed, the server log warns with the locati' +
      'on in settings.json and the automatic choice applies. Without any installation (Linux, CI)' +
      ' the configured version or the one matching the ProjectVersion applies, otherwise the newe' +
      'st known version, only for CompilerVersion and VERxxx. In the IDE the running IDE always a' + 'pplies.",' + #10 +
      '      "examples": [' + #10 + '        "37.0",' + #10 + '        "23.0"' + #10 + '      ],' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "general",' + #10 + '      "x-machine": true,' + #10 +
      '      "x-page": "Allgemein",' + #10,
    '      "x-control": "Auswahl aus den installierten Versionen",' + #10 + '      "x-issue": "#47, #258"' + #10 +
      '    },' + #10 + '    "minDelphiVersion": {' + #10 + '      "type": "string",' + #10 +
      '      "pattern": "^[0-9]+(\\.[0-9]+)?$",' + #10 +
      '      "description": "Älteste Delphi-Version, mit der das Projekt übersetzen muss, als Pro' +
      'duktnummer (\"12\", \"11\") oder wie in der Registry (\"23.0\"). Atlas meldet Sprachmerkma' +
      'le neuerer Versionen (Regel language-feature, z. B. \"is not\" oder If-Ausdruck bei \"12\"' +
      '), und Code-Aktionen, Schnellbefehle und Formatieren erzeugen sie nicht. Gilt die ältere a' +
      'us dieser und der gewählten Version (delphiVersion bzw. laufende IDE). Leer: nur die gewäh' + 'lte Version.",' +
      #10,
    '      "x-description-en": "Oldest Delphi version the project must compile with, as product' +
      ' number (\"12\", \"11\") or as in the registry (\"23.0\"). Atlas reports language features' +
      ' of newer versions (rule language-feature, e.g. \"is not\" or the if expression with \"12\' +
      '"), and code actions, slash commands and formatting do not produce them. The older of this' +
      ' and the selected version (delphiVersion or the running IDE) applies. Empty: only the sele' + 'cted version.",' +
      #10 + '      "examples": [' + #10 + '        "23.0",' + #10 + '        "22.0"' + #10 + '      ],' + #10 +
      '      "x-scope": "project",' + #10 + '      "x-page": "Projekt",' + #10 +
      '      "x-control": "Auswahl aller bekannten Delphi-Versionen",' + #10 + '      "x-issue": "#1126"' + #10 +
      '    },' + #10 + '    "language": {' + #10 + '      "type": "string",' + #10 + '      "enum": [' + #10 +
      '        "",' + #10 + '        "de",' + #10 + '        "en"' + #10 + '      ],' + #10,
    '      "default": "",' + #10 +
      '      "description": "Sprache der Befunde, Code-Aktionen, Hover, Vorschauen und Servermeld' +
      'ungen (#1458): \"de\" oder \"en\". Leer: wie die IDE (das Plugin schickt ihre Sprache in i' +
      'nitializationOptions.locale, andere Editoren in initialize.locale), sonst Englisch. AtlasS' +
      'erver --check nimmt --locale vor dieser Einstellung.",' + #10 +
      '      "x-description-en": "Language of findings, code actions, hovers, previews and server' +
      ' messages (#1458): \"de\" or \"en\". Empty: like the IDE (the plugin sends its language in' +
      ' initializationOptions.locale, other editors in initialize.locale), otherwise English. Atl' +
      'asServer --check takes --locale before this setting.",' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-page": "Allgemein",' + #10 + '      "x-control": "Auswahl",' +
      #10 + '      "x-issue": "#24, #1458"' + #10 + '    },' + #10 + '    "encoding": {' + #10,
    '      "type": "string",' + #10 + '      "default": "utf-8",' + #10 + '      "examples": [' + #10 +
      '        "utf-8",' + #10 + '        "windows-1252",' + #10 + '        "windows-1250"' + #10 + '      ],' + #10 +
      '      "description": "Vorgabe-Kodierung für Dateien ohne BOM, wenn die Erkennung nicht ent' +
      'scheidet (reines ASCII, ungültiges UTF-8): \"utf-8\" oder eine ANSI-Codepage wie \"windows' +
      '-1250\". Binäre Formulare werden nie geändert.",' + #10 +
      '      "x-description-en": "Default encoding for files without BOM when detection does not ' +
      'decide (pure ASCII, invalid UTF-8): \"utf-8\" or an ANSI code page like \"windows-1250\". ' +
      'Binary forms are never changed.",' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Allgemein",' +
      #10 + '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#121"' + #10 + '    },' + #10 +
      '    "project": {' + #10 + '      "type": "string",' + #10,
    '      "description": "Projektdatei (.dproj) relativ zu diesem Ordner. Leer: automatisch su' + 'chen.",' + #10 +
      '      "x-description-en": "Project file (.dproj) relative to this folder. Empty: search au' + 'tomatically.",' +
      #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Projekt",' + #10 +
      '      "x-control": "Vorgabe: aktives IDE-Projekt",' + #10 + '      "x-issue": "#14, #24"' + #10 + '    },' +
      #10 + '    "config": {' + #10 + '      "type": "string",' + #10 +
      '      "description": "Build-Konfiguration, z. B. Debug oder Release.",' + #10 +
      '      "x-description-en": "Build configuration, e.g. Debug or Release.",' + #10 + '      "examples": [' + #10 +
      '        "Debug",' + #10 + '        "Release"' + #10 + '      ],' + #10 + '      "x-scope": "project",' + #10 +
      '      "x-page": "Projekt",' + #10 + '      "x-control": "Auswahl aus der .dproj",' + #10 +
      '      "x-issue": "#14, #46"' + #10 + '    },' + #10 + '    "platform": {' + #10,
    '      "type": "string",' + #10 + '      "description": "Zielplattform.",' + #10 +
      '      "x-description-en": "Target platform.",' + #10 + '      "examples": [' + #10 + '        "Win32",' + #10 +
      '        "Win64"' + #10 + '      ],' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Projekt",' +
      #10 + '      "x-control": "Auswahl aus der .dproj",' + #10 + '      "x-issue": "#14, #46"' + #10 + '    },' +
      #10 + '    "rules": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Prüfregeln einzeln einstellen: Regel-ID → Schweregrad oder Objekt mi' +
      't \"severity\" und Optionen. Hauptschalter je Gruppe der Einstellungsseite (#909): \"group' +
      ':<gruppe>\": \"off\" schaltet alle Regeln der Gruppe ab (Gruppen siehe Regeln.md, z. B. \"' +
      'group:threads\"). Die Gruppe „Compiler vorab“ nimmt auch ein Objekt (#1024): \"group:compi' +
      'ler\": {\"severity\": \"off\", \"typeLevel\": \"off\"}; \"typeLevel\": \"off\" schaltet nu' +
      'r die Regeln der Stufe T ab, die Ausdruckstypen brauchen (Stufen siehe Regeln.md). Die Kon' +
      'fidenz eines Treffers begrenzt den Schweregrad auch hier: Bei mittlerer Konfidenz bleibt e' +
      'in Treffer höchstens eine Warnung, bei niedriger höchstens ein Hinweis, auch mit \"error\"' + '.",' + #10,
    '      "x-description-en": "Configure rules individually: rule id → severity or object with' +
      ' \"severity\" and options. Main switch per group of the settings page (#909): \"group:<gro' +
      'up>\": \"off\" turns off all rules of the group (groups see Regeln.md, e.g. \"group:thread' +
      's\"). The group “Compiler ahead” also takes an object (#1024): \"group:compiler\": {\"seve' +
      'rity\": \"off\", \"typeLevel\": \"off\"}; \"typeLevel\": \"off\" turns off only the rules ' +
      'of level T that need expression types (levels see Regeln.md). The confidence of a finding ' +
      'limits the severity here too: with medium confidence a finding stays at most a warning, wi' +
      'th low confidence at most a hint, even with \"error\".",' + #10 + '      "additionalProperties": {' + #10 +
      '        "oneOf": [' + #10 + '          {' + #10 + '            "type": "string",' + #10,
    '            "description": "Schweregrad der Regel. Treffer mittlerer Konfidenz bleiben höc' +
      'hstens Warnung, niedriger höchstens Hinweis (#144).",' + #10 +
      '            "x-description-en": "Severity of the rule. Findings with medium confidence sta' +
      'y at most a warning, low ones at most a hint (#144).",' + #10 + '            "enum": [' + #10 +
      '              "off",' + #10 + '              "hint",' + #10 + '              "info",' + #10 +
      '              "information",' + #10 + '              "warning",' + #10 + '              "error"' + #10 +
      '            ]' + #10 + '          },' + #10 + '          {' + #10 + '            "type": "object",' + #10 +
      '            "properties": {' + #10 + '              "severity": {' + #10 + '                "type": "string",' +
      #10 + '                "description": "Schweregrad der Regel. Treffer mittlerer Konfidenz bleiben' +
      ' höchstens Warnung, niedriger höchstens Hinweis (#144).",' + #10,
    '                "x-description-en": "Severity of the rule. Findings with medium confidence' +
      ' stay at most a warning, low ones at most a hint (#144).",' + #10 + '                "enum": [' + #10 +
      '                  "off",' + #10 + '                  "hint",' + #10 + '                  "info",' + #10 +
      '                  "information",' + #10 + '                  "warning",' + #10 + '                  "error"' +
      #10 + '                ]' + #10 + '              },' + #10 + '              "exclude": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "description": "Ausnahmen dieser Regel: Glob-Muster für Pfade (relativ zur' +
      ' Konfiguration) oder Unit-Namen.",' + #10 +
      '                "x-description-en": "Exceptions of this rule: glob patterns for paths (rel' +
      'ative to the configuration) or unit names."' + #10 + '              },' + #10,
    '              "max": {' + #10 + '                "type": "integer",' + #10 + '                "minimum": 1,' +
      #10 + '                "description": "Nur metric-* (#66): Grenzwert der Kennzahl; darüber meldet' +
      ' die Regel die Methode. Vorgaben: Länge 60, Tiefe 4, zyklomatisch 15, kognitiv 15, Paramet' +
      'er 6; metric-class-size 40 Member, metric-unit-length 2000 Zeilen, metric-uses-count 30 Un' +
      'its (#939); metric-boolean-operands 5 Operanden, metric-local-count 12 lokale Variablen, m' +
      'etric-exit-points 4 Ausstiege, metric-inheritance-depth 5 Vorfahren (#980). Bei line-lengt' +
      'h (#938) die Höchstlänge einer Zeile, Vorgabe 120.",' + #10,
    '                "x-description-en": "Only metric-* (#66): limit of the metric; above it th' +
      'e rule reports the method. Defaults: length 60, depth 4, cyclomatic 15, cognitive 15, para' +
      'meters 6; metric-class-size 40 members, metric-unit-length 2000 lines, metric-uses-count 3' +
      '0 units (#939); metric-boolean-operands 5 operands, metric-local-count 12 local variables,' +
      ' metric-exit-points 4 exits, metric-inheritance-depth 5 ancestors (#980). For line-length ' +
      '(#938) the maximum length of a line, default 120."' + #10 + '              },' + #10 +
      '              "minLines": {' + #10 + '                "type": "integer",' + #10 +
      '                "minimum": 1,' + #10 +
      '                "description": "Nur commented-out-code (#942): so viele aufeinanderfolgend' +
      'e Kommentarzeilen mit Code meldet die Regel; Vorgabe 3.",' + #10,
    '                "x-description-en": "Only commented-out-code (#942): the rule reports this' +
      ' many consecutive comment lines with code; default 3."' + #10 + '              },' + #10 +
      '              "maxLiteralLength": {' + #10 + '                "type": "integer",' + #10 +
      '                "minimum": 1,' + #10 +
      '                "description": "Nur pos-arguments-swapped (#1045): Höchstlänge des Literal' +
      's an der Stelle des Textes, bis zu der vertauschte Argumente vermutet werden; Vorgabe 3.",' + #10 +
      '                "x-description-en": "Only pos-arguments-swapped (#1045): maximum length of' +
      ' the literal in the place of the text up to which swapped arguments are assumed; default 3' + '."' + #10 +
      '              },' + #10 + '              "keywords": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 +
      '                  "pattern": "^[A-Za-z]+$"' + #10 + '                },' + #10,
    '                "default": ["TODO", "FIXME"],' + #10 +
      '                "description": "Nur todo-comment (#68): Marken offener TODO-Einträge (nur ' +
      'Buchstaben, Groß-/Kleinschreibung egal), z. B. [\"TODO\", \"FIXME\", \"HACK\"]. Erledigt i' +
      'st immer DONE. Gilt auch, wenn die Regel aus ist, für get_todos, atlas.server.todos und --' +
      'todos. Vorgabe: TODO und FIXME.",' + #10 +
      '                "x-description-en": "Only todo-comment (#68): tags of open TODO entries (l' +
      'etters only, case does not matter), e.g. [\"TODO\", \"FIXME\", \"HACK\"]. DONE is always d' +
      'one. Also applies when the rule is off, for get_todos, atlas.server.todos and --todos. Def' +
      'ault: TODO and FIXME."' + #10 + '              },' + #10 + '              "prefixes": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10,
    '                "description": "Nur architecture-role-import und architecture-contract-con' +
      'tent (Code-Review A-12): Präfixe der Ausgabeartefakte nach dem Rollenkonzept (Ausgabeartef' +
      'akt.Feature.Rolle.Sache), z. B. \"Atlas.Common\". Ohne Angabe melden die Regeln nichts.",' + #10 +
      '                "x-description-en": "Only architecture-role-import and architecture-contra' +
      'ct-content (code review A-12): prefixes of the output artifacts according to the role conc' +
      'ept (Artifact.Feature.Role.Thing), e.g. \"Atlas.Common\". Without them the rules report no' + 'thing."' + #10 +
      '              },' + #10 + '              "hostRoles": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10,
    '                "description": "Nur architecture-role-import: erste Namenssegmente der Hos' +
      't-Units ohne Präfix. Vorgabe: Foundation, Core, Shell, Adapters, Platform.",' + #10 +
      '                "x-description-en": "Only architecture-role-import: first name segments of' +
      ' host units without prefix. Default: Foundation, Core, Shell, Adapters, Platform."' + #10 + '              },' +
      #10 + '              "allow": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "description": "Nur architecture-role-import und architecture-contract-con' +
      'tent: genehmigte Ausnahmen, bei architecture-role-import \"Quelle -> Ziel\" (beide Globs),' +
      ' bei architecture-contract-content \"Unit.Typ\" als Glob.",' + #10,
    '                "x-description-en": "Only architecture-role-import and architecture-contra' +
      'ct-content: approved exceptions, for architecture-role-import \"source -> target\" (both g' +
      'lobs), for architecture-contract-content \"Unit.Type\" as glob."' + #10 + '              },' + #10 +
      '              "layers": {' + #10 + '                "type": "array",' + #10 +
      '                "description": "Nur forbidden-uses: Schichtregeln für uses-Beziehungen.",' + #10 +
      '                "x-description-en": "Only forbidden-uses: layer rules for uses relations."' + ',' + #10 +
      '                "items": {' + #10 + '                  "type": "object",' + #10 +
      '                  "required": [' + #10 + '                    "from",' + #10 + '                    "deny"' +
      #10 + '                  ],' + #10 + '                  "properties": {' + #10 + '                    "from": {' +
      #10 + '                      "type": "string",' + #10,
    '                      "description": "Glob auf den Unit-Namen (z. B. \"*.Common.*\") oder ' +
      'mit \"/\" auf den Pfad (z. B. \"Source/Common/**\").",' + #10 +
      '                      "x-description-en": "Glob on the unit name (e.g. \"*.Common.*\") or ' +
      'with \"/\" on the path (e.g. \"Source/Common/**\")."' + #10 + '                    },' + #10 +
      '                    "deny": {' + #10 + '                      "type": "array",' + #10 +
      '                      "items": {' + #10 + '                        "type": "string"' + #10 +
      '                      },' + #10 +
      '                      "description": "Verbotene Units als Globs, z. B. \"Vcl.*\".",' + #10 +
      '                      "x-description-en": "Forbidden units as globs, e.g. \"Vcl.*\"."' + #10 +
      '                    },' + #10 + '                    "allow": {' + #10 +
      '                      "type": "array",' + #10 + '                      "items": {' + #10 +
      '                        "type": "string"' + #10,
    '                      },' + #10 + '                      "description": "Ausnahmen von deny.",' + #10 +
      '                      "x-description-en": "Exceptions from deny."' + #10 + '                    }' + #10 +
      '                  }' + #10 + '                }' + #10 + '              },' + #10 +
      '              "symbols": {' + #10 + '                "type": "array",' + #10 +
      '                "description": "Nur forbidden-symbol (#1133): verbotene Symbole. Ohne List' +
      'e ist die Regel stumm.",' + #10 +
      '                "x-description-en": "Only forbidden-symbol (#1133): forbidden symbols. Wit' +
      'hout a list the rule is silent.",' + #10 + '                "default": [],' + #10 +
      '                "items": {' + #10 + '                  "type": "object",' + #10 +
      '                  "required": [' + #10 + '                    "name"' + #10 + '                  ],' + #10 +
      '                  "properties": {' + #10 + '                    "name": {' + #10,
    '                      "type": "string",' + #10 +
      '                      "description": "Voll qualifizierter Name (Unit.Typ.Mitglied) oder ab' +
      ' einer Punktgrenze gekürzt, * erlaubt, z. B. \"System.Write*\" oder \"TThread.Queue\".",' + #10 +
      '                      "x-description-en": "Fully qualified name (Unit.Type.Member) or shor' +
      'tened at a dot boundary, * allowed, e.g. \"System.Write*\" or \"TThread.Queue\"."' + #10 +
      '                    },' + #10 + '                    "kind": {' + #10 +
      '                      "type": "string",' + #10 +
      '                      "enum": ["routine", "type", "constant", "field", "property", "enumVa' +
      'lue", "identifier"],' + #10 +
      '                      "description": "Art des Symbols; ohne Angabe jede Art. identifier ve' +
      'rgleicht nur den geschriebenen Namen, ohne Namensauflösung.",' + #10,
    '                      "x-description-en": "Kind of symbol; without it any kind. identifier' +
      ' compares only the written name, without name resolution."' + #10 + '                    },' + #10 +
      '                    "message": {' + #10 + '                      "type": "string",' + #10 +
      '                      "description": "Begründung in der Meldung, z. B. \"Nur über ILogger\' + '".",' + #10 +
      '                      "x-description-en": "Reason in the message, e.g. \"Only through ILog' + 'ger\"."' + #10 +
      '                    },' + #10 + '                    "replacement": {' + #10 +
      '                      "type": "string",' + #10 +
      '                      "description": "Ersatz für die Schnellkorrektur.",' + #10 +
      '                      "x-description-en": "Replacement for the quick fix."' + #10 + '                    },' +
      #10 + '                    "severity": {' + #10 + '                      "type": "string",' + #10,
    '                      "enum": ["off", "hint", "info", "warning", "error"],' + #10 +
      '                      "description": "Schweregrad dieses Eintrags; ohne Angabe der der Reg' + 'el.",' + #10 +
      '                      "x-description-en": "Severity of this entry; without it the one of t' + 'he rule."' + #10 +
      '                    },' + #10 + '                    "units": {' + #10 +
      '                      "type": "array",' + #10 + '                      "items": {' + #10 +
      '                        "type": "string"' + #10 + '                      },' + #10 +
      '                      "description": "Units, in denen das Verbot gilt, als Muster; \"!\" d' +
      'avor schließt aus. Ohne Angabe überall.",' + #10 +
      '                      "x-description-en": "Units in which the ban applies, as patterns; \"' +
      '!\" in front excludes. Without it everywhere."' + #10 + '                    },' + #10 +
      '                    "firstArgument": {' + #10,
    '                      "type": "array",' + #10 + '                      "items": {' + #10 +
      '                        "type": "string"' + #10 + '                      },' + #10 +
      '                      "description": "Nur melden, wenn das erste Argument einer dieser Tex' +
      'te ist oder diesen Typ hat, z. B. [\"nil\"].",' + #10 +
      '                      "x-description-en": "Report only if the first argument is one of the' +
      'se texts or has this type, e.g. [\"nil\"]."' + #10 + '                    },' + #10 +
      '                    "allowFirstArgument": {' + #10 + '                      "type": "array",' + #10 +
      '                      "items": {' + #10 + '                        "type": "string"' + #10 +
      '                      },' + #10 +
      '                      "description": "Erlaubt, wenn das erste Argument einer dieser Texte ' +
      'ist oder diesen Typ hat, z. B. [\"ErrOutput\", \"TextFile\"].",' + #10,
    '                      "x-description-en": "Allowed if the first argument is one of these t' +
      'exts or has this type, e.g. [\"ErrOutput\", \"TextFile\"]."' + #10 + '                    }' + #10 +
      '                  }' + #10 + '                }' + #10 + '              },' + #10 + '              "ignore": {' +
      #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "description": "Nur unused-local, unused-parameter, unused-assignment, sha' +
      'dowed-name (#934) und naming-prefix (#1111): Namensmuster (* und ?), die nie gemeldet werd' +
      'en. Bei shadowed-name ohne Angabe Sender und Value.",' + #10 +
      '                "x-description-en": "Only unused-local, unused-parameter, unused-assignmen' +
      't, shadowed-name (#934) and naming-prefix (#1111): name patterns (* and ?) that are never ' +
      'reported. For shadowed-name without it Sender and Value."' + #10,
    '              },' + #10 + '              "local": {' + #10 + '                "type": "string",' + #10 +
      '                "default": "m",' + #10 +
      '                "description": "Nur naming-prefix (#1111): Präfix lokaler Variablen (auch ' +
      'Inline-var und for var); leer = nicht prüfen. Ohne Angabe gilt naming.local der Projektdat' +
      'ei .atlas, sonst m.",' + #10 +
      '                "x-description-en": "Only naming-prefix (#1111): prefix of local variables' +
      ' (also inline var and for var); empty = do not check. Without it naming.local of the proje' +
      'ct file .atlas applies, otherwise m."' + #10 + '              },' + #10 + '              "field": {' + #10 +
      '                "type": "string",' + #10 + '                "default": "F",' + #10 +
      '                "description": "Nur naming-prefix (#1111): Präfix von Feldern (auch class ' +
      'var); leer = nicht prüfen. Ohne Angabe gilt naming.field der Projektdatei .atlas, sonst F.' + '",' + #10,
    '                "x-description-en": "Only naming-prefix (#1111): prefix of fields (also cl' +
      'ass var); empty = do not check. Without it naming.field of the project file .atlas applies' + ', otherwise F."' +
      #10 + '              },' + #10 + '              "parameter": {' + #10 + '                "type": "string",' +
      #10 + '                "default": "A",' + #10 +
      '                "description": "Nur naming-prefix (#1111): Präfix von Parametern; leer = n' +
      'icht prüfen. Ohne Angabe gilt naming.parameter der Projektdatei .atlas, sonst A.",' + #10 +
      '                "x-description-en": "Only naming-prefix (#1111): prefix of parameters; emp' +
      'ty = do not check. Without it naming.parameter of the project file .atlas applies, otherwi' + 'se A."' + #10 +
      '              },' + #10 + '              "constant": {' + #10 + '                "type": "string",' + #10 +
      '                "default": "c",' + #10,
    '                "description": "Nur naming-prefix (#1111): Präfix von Konstanten (const, a' +
      'uch lokal, in Klassen und Inline-const; nicht resourcestring); leer = nicht prüfen. Ohne A' +
      'ngabe gilt naming.constant der Projektdatei .atlas, sonst c.",' + #10 +
      '                "x-description-en": "Only naming-prefix (#1111): prefix of constants (cons' +
      't, also local, in classes and inline const; not resourcestring); empty = do not check. Wit' +
      'hout it naming.constant of the project file .atlas applies, otherwise c."' + #10 + '              },' + #10 +
      '              "deferredApis": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "description": "Nur captured-loop-variable: weitere verzögert ausführende ' +
      'Aufrufe (neben TThread.Queue, TTask.Run und anderen), z. B. \"TMyPool.Post\".",' + #10,
    '                "x-description-en": "Only captured-loop-variable: further calls that run l' +
      'ater (besides TThread.Queue, TTask.Run and others), e.g. \"TMyPool.Post\"."' + #10 + '              },' + #10 +
      '              "lockPairs": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "array",' + #10 + '                  "items": {' + #10 +
      '                    "type": "string"' + #10 + '                  },' + #10 + '                  "minItems": 2,' +
      #10 + '                  "maxItems": 2' + #10 + '                },' + #10 +
      '                "description": "Nur lock-without-finally: weitere Paare aus Sperren und Fr' +
      'eigeben, z. B. [[\"Lock\", \"Unlock\"]].",' + #10 +
      '                "x-description-en": "Only lock-without-finally: further pairs of lock and ' +
      'unlock, e.g. [[\"Lock\", \"Unlock\"]]."' + #10 + '              },' + #10 + '              "template": {' + #10,
    '                "type": "string",' + #10 +
      '                "description": "Nur file-header: erwarteter Dateikopf mit Platzhaltern (si' +
      'ehe Regeln.md).",' + #10 +
      '                "x-description-en": "Only file-header: expected file header with placehold' +
      'ers (see Regeln.md)."' + #10 + '              },' + #10 + '              "allowCommented": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur empty-statement: leere Blöcke begin … end mit Kommenta' +
      'r darin nicht melden (#912).",' + #10 +
      '                "x-description-en": "Only empty-statement: do not report empty blocks begi' +
      'n … end with a comment inside (#912)."' + #10 + '              },' + #10 + '              "types": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string",' + #10,
    '                  "pattern": "^[A-Za-z_][A-Za-z0-9_.]*>[A-Za-z_][A-Za-z0-9_.]*$"' + #10 + '                },' +
      #10 + '                "default": ["Int64>Integer", "NativeInt>Integer"],' + #10 +
      '                "description": "Nur narrowing-assignment: gemeldete Paare Quelltyp>Zieltyp' +
      ', z. B. \"Double>Single\" oder \"Extended>Double\" (#1013).",' + #10 +
      '                "x-description-en": "Only narrowing-assignment: reported pairs source type' +
      '>target type, e.g. \"Double>Single\" or \"Extended>Double\" (#1013)."' + #10 + '              },' + #10 +
      '              "allowInProgram": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur global-formatsettings-modified: Zuweisungen an die glo' +
      'bale FormatSettings in der .dpr erlauben, etwa einmal beim Programmstart (#1089).",' + #10,
    '                "x-description-en": "Only global-formatsettings-modified: allow assignment' +
      's to the global FormatSettings in the .dpr, for example once at program start (#1089)."' + #10 +
      '              },' + #10 + '              "countNames": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Count", "Length"],' + #10 +
      '                "description": "Nur loop-off-by-one: Namen, die eine Anzahl liefern (Prope' +
      'rty wie Count oder Funktion wie Length) (#913).",' + #10 +
      '                "x-description-en": "Only loop-off-by-one: names that return a count (prop' +
      'erty like Count or function like Length) (#913)."' + #10 + '              },' + #10 +
      '              "mutatingMethods": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10,
    '                },' + #10 +
      '                "default": ["Add", "Delete", "Remove", "Extract", "Clear", "Insert"],' + #10 +
      '                "description": "Nur assert-side-effect und collection-modified-in-loop (#9' +
      '14): Methoden, die ihr Objekt bzw. die Liste verändern. Vorgabe: Add, Delete, Remove, Extr' +
      'act, Clear, Insert.",' + #10 +
      '                "x-description-en": "Only assert-side-effect and collection-modified-in-lo' +
      'op (#914): methods that change their object or the list. Default: Add, Delete, Remove, Ext' +
      'ract, Clear, Insert."' + #10 + '              },' + #10 + '              "ignoreMethods": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Destroy", "BeforeDestruction"],' + #10,
    '                "description": "Nur field-free-without-nil: Methoden, in denen Free ohne n' +
      'il erlaubt ist (#917). Destruktoren und Methoden mit [TearDown] gelten immer.",' + #10 +
      '                "x-description-en": "Only field-free-without-nil: methods in which Free wi' +
      'thout nil is allowed (#917). Destructors and methods with [TearDown] always count."' + #10 + '              },' +
      #10 + '              "ignoreCalls": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": [],' + #10 +
      '                "description": "Nur hardcoded-string: weitere Routinen, deren Text-Argumen' +
      'te niemand übersetzt (z. B. eine eigene Pick(Englisch, ''en'', ''de'')). Protokoll-, Prüf-, Ve' +
      'rgleichs- und Registry-Aufrufe gelten immer.",' + #10,
    '                "x-description-en": "Only hardcoded-string: further routines whose text ar' +
      'guments nobody translates (for example an own Pick(English, ''en'', ''de'')). Logging, check, ' +
      'comparison and registry calls always count."' + #10 + '              },' + #10 +
      '              "assertPatterns": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Assert.*", "WillRaise*", "Check*"],' + #10 +
      '                "description": "Nur dunitx-test-without-assert (#945): Aufrufe, die als Pr' +
      'üfung zählen, als Muster mit * und ?; ersetzt die Vorgabe. System.Assert und Klassen mit A' +
      'ssert im Namen zählen immer.",' + #10,
    '                "x-description-en": "Only dunitx-test-without-assert (#945): calls that co' +
      'unt as a check, as patterns with * and ?; replaces the default. System.Assert and classes ' +
      'with Assert in the name always count."' + #10 + '              },' + #10 + '              "selfRegistering": {' +
      #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 + '                "default": [],' + #10 +
      '                "description": "Nur create-without-assignment (#948): Klassen, die sich im' +
      ' Konstruktor selbst registrieren (Muster mit * und ?); TKlasse.Create; bleibt für sie stil' + 'l.",' + #10 +
      '                "x-description-en": "Only create-without-assignment (#948): classes that r' +
      'egister themselves in the constructor (patterns with * and ?); TClass.Create; stays silent' + ' for them."' +
      #10 + '              },' + #10,
    '              "componentClasses": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["TComponent"],' + #10 +
      '                "description": "Nur component-interface-dangling (#1090): Basisklassen ohn' +
      'e Referenzzählung; ihre Nachfahren als Interface zu speichern und dann freizugeben wird ge' +
      'meldet. Mit TComponent zählen auch die bekannten VCL- und FMX-Klassen (TForm, TFrame, TDat' + 'aModule …).",' +
      #10 + '                "x-description-en": "Only component-interface-dangling (#1090): base class' +
      'es without reference counting; storing their descendants as interface and then freeing the' +
      'm is reported. With TComponent the known VCL and FMX classes (TForm, TFrame, TDataModule …' + ') count too."' +
      #10 + '              },' + #10 + '              "swallow": {' + #10 + '                "type": "array",' + #10,
    '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["WM_ERASEBKGND"],' + #10 +
      '                "description": "Nur message-handler-without-inherited (#949): Nachrichten,' +
      ' die ohne inherited behandelt werden dürfen (WM_…, CM_…); ersetzt die Vorgabe.",' + #10 +
      '                "x-description-en": "Only message-handler-without-inherited (#949): messag' +
      'es that may be handled without inherited (WM_…, CM_…); replaces the default."' + #10 + '              },' + #10 +
      '              "ignoreTypes": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "string"' + #10 + '                },' + #10 + '                "default": [],' +
      #10 + '                "description": "Nur field-not-freed: Klassen, die anderswo freigegeben wer' +
      'den (#918). Generische Typen treffen ohne Typparameter, z. B. TObjectList.",' + #10,
    '                "x-description-en": "Only field-not-freed: classes that are freed elsewher' +
      'e (#918). Generic types match without type parameters, e.g. TObjectList."' + #10 + '              },' + #10 +
      '              "methods": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Create", "Destroy", "AfterConstruction", "BeforeDestruction"]' + ',' + #10 +
      '                "description": "Nur missing-inherited: geprüfte Methoden (#919). Create st' +
      'eht für alle Konstruktoren, deren Name mit Create beginnt.",' + #10 +
      '                "x-description-en": "Only missing-inherited: checked methods (#919). Creat' +
      'e stands for all constructors whose name starts with Create."' + #10 + '              },' + #10 +
      '              "registerPairs": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10,
    '                  "type": "object",' + #10 + '                  "required": ["open", "close"],' + #10 +
      '                  "additionalProperties": false,' + #10 + '                  "properties": {' + #10 +
      '                    "open": {' + #10 + '                      "type": "string",' + #10 +
      '                      "description": "Anmeldung, deren Ergebnis der Index ist, z. B. AddNo' + 'tifier.",' + #10 +
      '                      "x-description-en": "Registration whose result is the index, e.g. Ad' + 'dNotifier."' +
      #10 + '                    },' + #10 + '                    "close": {' + #10 +
      '                      "type": "string",' + #10 +
      '                      "description": "Abmeldung, die den Index erhält, z. B. RemoveNotifie' + 'r.",' + #10 +
      '                      "x-description-en": "Unregistration that receives the index, e.g. Re' + 'moveNotifier."' +
      #10 + '                    }' + #10 + '                  }' + #10 + '                },' + #10,
    '                "default": [{"open": "AddNotifier", "close": "RemoveNotifier"}, {"open": "' +
      'RegisterPackageWizard", "close": "RemoveWizard"}],' + #10 +
      '                "description": "Nur ota-notifier-not-removed (#944): Paare der Open Tools ' +
      'API aus Anmeldung und Abmeldung; ersetzt die Vorgabe.",' + #10 +
      '                "x-description-en": "Only ota-notifier-not-removed (#944): Open Tools API ' +
      'pairs of registration and unregistration; replaces the default."' + #10 + '              },' + #10 +
      '              "pairs": {' + #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "anyOf": [' + #10 + '                    {' + #10 + '                      "type": "object",' +
      #10 + '                      "required": ["open", "close"],' + #10 +
      '                      "additionalProperties": false,' + #10 + '                      "properties": {' + #10 +
      '                        "open": {' + #10,
    '                          "type": "string",' + #10 +
      '                          "description": "Öffnende Methode bzw. Routine, z. B. DisableCont' +
      'rols, oder eine Zuweisung wie \"Screen.Cursor :=\".",' + #10 +
      '                          "x-description-en": "Opening method or routine, e.g. DisableCont' +
      'rols, or an assignment like \"Screen.Cursor :=\"."' + #10 + '                        },' + #10 +
      '                        "close": {' + #10 + '                          "type": "string",' + #10 +
      '                          "description": "Schließende Methode bzw. Routine, z. B. EnableCo' + 'ntrols.",' + #10 +
      '                          "x-description-en": "Closing method or routine, e.g. EnableContr' + 'ols."' + #10 +
      '                        },' + #10 + '                        "openArg": {' + #10 +
      '                          "type": "integer",' + #10,
    '                          "description": "Argument (ab 0), das beide Aufrufe verbindet; oh' +
      'ne Angabe der Empfänger bzw. das erste Argument.",' + #10 +
      '                          "x-description-en": "Argument (from 0) that connects both calls;' +
      ' without it the receiver or the first argument."' + #10 + '                        },' + #10 +
      '                        "closeArg": {' + #10 + '                          "type": "integer",' + #10 +
      '                          "description": "Argument (ab 0) des schließenden Aufrufs; ohne A' +
      'ngabe der Empfänger bzw. das erste Argument.",' + #10 +
      '                          "x-description-en": "Argument (from 0) of the closing call; with' +
      'out it the receiver or the first argument."' + #10 + '                        }' + #10 +
      '                      }' + #10 + '                    },' + #10 + '                    {' + #10 +
      '                      "type": "string",' + #10,
    '                      "pattern": "^[^>]+>[^>]+$",' + #10 +
      '                      "description": "Nur handle-leak: Paar als Text Öffnen>Schließen, z. ' +
      'B. MeinOeffnen>MeinSchliessen.",' + #10 +
      '                      "x-description-en": "Only handle-leak: pair as text Open>Close, e.g.' +
      ' MyOpen>MyClose."' + #10 + '                    }' + #10 + '                  ]' + #10 + '                },' +
      #10 + '                "default": [],' + #10 +
      '                "description": "Nur pair-without-finally und handle-leak: weitere Paare ne' +
      'ben den eingebauten. pair-without-finally: Objekte mit open und close (DisableControls/Ena' +
      'bleControls, BeginUpdate/EndUpdate, FindFirst/FindClose, Reset/CloseFile, GetMem/FreeMem, ' +
      'Screen.Cursor; #930). handle-leak: Texte \"Öffnen>Schließen\" oder Objekte mit open und cl' +
      'ose; das Handle ist das Ergebnis des Öffnens und das erste Argument des Schließens (#1088)' + '.",' + #10,
    '                "x-description-en": "Only pair-without-finally and handle-leak: further pa' +
      'irs besides the built-in ones. pair-without-finally: objects with open and close (DisableC' +
      'ontrols/EnableControls, BeginUpdate/EndUpdate, FindFirst/FindClose, Reset/CloseFile, GetMe' +
      'm/FreeMem, Screen.Cursor; #930). handle-leak: texts \"Open>Close\" or objects with open an' +
      'd close; the handle is the result of opening and the first argument of closing (#1088)."' + #10 +
      '              },' + #10 + '              "onlyAfterRaisingCode": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur destructor-not-nil-safe: nur melden, wenn der Konstruk' +
      'tor vor dem Anlegen des Felds etwas aufruft, das eine Exception werfen kann; aus zählt jed' +
      'es im Konstruktor angelegte Feld (#1087).",' + #10,
    '                "x-description-en": "Only destructor-not-nil-safe: report only if the cons' +
      'tructor calls something that can raise an exception before creating the field; off counts ' +
      'every field created in the constructor (#1087)."' + #10 + '              },' + #10 +
      '              "requireElse": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur case-missing-enum-value: auch case-Anweisungen mit els' +
      'e melden, wenn Werte fehlen (#929).",' + #10 +
      '                "x-description-en": "Only case-missing-enum-value: also report case statem' +
      'ents with else when values are missing (#929)."' + #10 + '              },' + #10 +
      '              "wrapper": {' + #10 + '                "type": "string",' + #10 +
      '                "default": "TAtlasMainThread.Queue",' + #10,
    '                "description": "Nur queue-nil-in-package (#943): Ersatz für TThread.Queue(' +
      'nil, …) in der Schnellkorrektur; bei ForceQueue wird aus …Queue …ForceQueue. Mit Klammer s' +
      'teht der Text so vor den übrigen Argumenten, z. B. \"TAtlasMainThread.Queue(TAtlasFeature.' + 'Hover, \".",' +
      #10 + '                "x-description-en": "Only queue-nil-in-package (#943): replacement for TTh' +
      'read.Queue(nil, …) in the quick fix; with ForceQueue …Queue becomes …ForceQueue. With a pa' +
      'renthesis the text goes in front of the remaining arguments, e.g. \"TAtlasMainThread.Queue' +
      '(TAtlasFeature.Hover, \"."' + #10 + '              },' + #10 + '              "okMarker": {' + #10 +
      '                "type": "string",' + #10 + '                "default": "mainthread-ok",' + #10 +
      '                "description": "Nur queue-nil-in-package (#943): Kommentar, der eine Zeile' +
      ' ausnimmt, z. B. // mainthread-ok.",' + #10,
    '                "x-description-en": "Only queue-nil-in-package (#943): comment that exempt' +
      's a line, e.g. // mainthread-ok."' + #10 + '              },' + #10 + '              "replacement": {' + #10 +
      '                "type": "string",' + #10 + '                "default": "OutputDebugString",' + #10 +
      '                "description": "Nur writeln-in-gui-app: Ersatz für Write und Writeln in de' +
      'r Schnellkorrektur (#926), z. B. \"Log.Info\" oder mit Platzhalter \"Logger.Log(TLogLevel.' + 'Info, %s)\".",' +
      #10 + '                "x-description-en": "Only writeln-in-gui-app: replacement for Write and Wr' +
      'iteln in the quick fix (#926), e.g. \"Log.Info\" or with placeholder \"Logger.Log(TLogLeve' + 'l.Info, %s)\"."' +
      #10 + '              },' + #10 + '              "allowIn": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10,
    '                "default": [],' + #10 +
      '                "description": "Nur processmessages-in-loop: Methoden, in denen Applicatio' +
      'n.ProcessMessages erlaubt ist, als Name oder Klasse.Name (#931).",' + #10 +
      '                "x-description-en": "Only processmessages-in-loop: methods in which Applic' +
      'ation.ProcessMessages is allowed, as Name or Class.Name (#931)."' + #10 + '              },' + #10 +
      '              "functions": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["StrToInt", "StrToInt64", "StrToFloat", "StrToDate", "StrToDat' +
      'eTime", "StrToCurr"],' + #10 +
      '                "description": "Nur unchecked-conversion: geprüfte Umwandlungen (#932).",' + #10 +
      '                "x-description-en": "Only unchecked-conversion: checked conversions (#932)' + '."' + #10 +
      '              },' + #10,
    '              "sources": {' + #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Text", "Cells", "Lines"],' + #10 +
      '                "description": "Nur unchecked-conversion: Eigenschaften, die als Benutzere' +
      'ingabe gelten, z. B. Text in Edit.Text oder Cells in Grid.Cells[…] (#932).",' + #10 +
      '                "x-description-en": "Only unchecked-conversion: properties that count as u' +
      'ser input, e.g. Text in Edit.Text or Cells in Grid.Cells[…] (#932)."' + #10 + '              },' + #10 +
      '              "allowed": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": ["number", "string"]' + #10 + '                },' + #10 +
      '                "default": [0, 1, -1, 2, 10, 100],' + #10,
    '                "description": "magic-number: Zahlen, die nie gemeldet werden (#937). inhe' +
      'rited-wrong-method: erlaubte Paare \"Methode>geerbte Methode\" (Muster mit * und ?), z. B.' +
      ' \"Speichern>Pruefen\" (#1050); ohne Angabe keine.",' + #10 +
      '                "x-description-en": "magic-number: numbers that are never reported (#937).' +
      ' inherited-wrong-method: allowed pairs \"method>inherited method\" (patterns with * and ?)' +
      ', e.g. \"Save>Validate\" (#1050); none without it."' + #10 + '              },' + #10 +
      '              "ignoreStrings": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": true,' + #10 +
      '                "description": "Nur line-length: Zeilen, die nur wegen eines Strings zu la' +
      'ng sind, nicht melden (#938).",' + #10 +
      '                "x-description-en": "Only line-length: do not report lines that are too lo' +
      'ng only because of a string (#938)."' + #10 + '              },' + #10,
    '              "ignoreComments": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur line-length: Zeilen, die nur wegen eines Kommentars zu' +
      ' lang sind, nicht melden (#938).",' + #10 +
      '                "x-description-en": "Only line-length: do not report lines that are too lo' +
      'ng only because of a comment (#938)."' + #10 + '              },' + #10 + '              "includeRecords": {' +
      #10 + '                "type": "boolean",' + #10 + '                "default": false,' + #10 +
      '                "description": "Nur public-field: auch Felder von Records melden (#940).",' + #10 +
      '                "x-description-en": "Only public-field: also report fields of records (#94' + '0)."' + #10 +
      '              },' + #10 + '              "includeFormVariables": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": false,' + #10,
    '                "description": "Nur global-variable: auch die Formularvariablen des Design' +
      'ers melden (#941).",' + #10 +
      '                "x-description-en": "Only global-variable: also report the form variables ' +
      'of the designer (#941)."' + #10 + '              },' + #10 + '              "frameworkMembers": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": false,' + #10 +
      '                "description": "Nur shadowed-name: jeden lokalen Namen melden, der ein aus' +
      ' RTL, VCL oder einer Bibliothek geerbtes Mitglied verdeckt (Left, Text, Name …), nicht nur' +
      ', wo das Mitglied gemeint sein könnte.",' + #10 +
      '                "x-description-en": "Only shadowed-name: report every local name that hide' +
      's a member inherited from the RTL, VCL or a library (Left, Text, Name …), not only where t' +
      'he member could be meant."' + #10 + '              },' + #10 + '              "includeFields": {' + #10,
    '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur unused-private-member: auch nie verwendete private Fel' +
      'der melden; der Compiler meldet nur Methoden (#1020).",' + #10 +
      '                "x-description-en": "Only unused-private-member: also report private field' +
      's that are never used; the compiler reports only methods (#1020)."' + #10 + '              },' + #10 +
      '              "visibilities": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 +
      '                  "enum": ["public", "published", "protected"]' + #10 + '                },' + #10 +
      '                "default": ["public", "published"],' + #10 +
      '                "description": "Nur unused-public-member (#1102): geprüfte Sichtbarkeiten.' + '",' + #10,
    '                "x-description-en": "Only unused-public-member (#1102): checked visibiliti' + 'es."' + #10 +
      '              },' + #10 + '              "memberKinds": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 +
      '                  "enum": ["method", "constant", "property", "field", "classVar"]' + #10 + '                },' +
      #10 + '                "default": ["method", "constant", "property"],' + #10 +
      '                "description": "Nur unused-public-member (#1102): geprüfte Mitgliedsarten.' + '",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): checked member kin' + 'ds."' + #10 +
      '              },' + #10 + '              "projectKinds": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 +
      '                  "enum": ["application", "package", "library"]' + #10,
    '                },' + #10 + '                "default": ["application"],' + #10 +
      '                "description": "Nur unused-public-member (#1102): Projektarten, deren Unit' +
      's geprüft werden. Packages und Bibliotheken haben Nutzer außerhalb der Projektgruppe und s' +
      'ind deshalb standardmäßig aus.",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): project kinds whos' +
      'e units are checked. Packages and libraries have users outside the project group and are t' +
      'herefore off by default."' + #10 + '              },' + #10 + '              "unitLevel": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur unused-public-member (#1102): auch Routinen und Konsta' +
      'nten aus dem interface-Abschnitt einer Unit prüfen.",' + #10,
    '                "x-description-en": "Only unused-public-member (#1102): also check routine' +
      's and constants from the interface section of a unit."' + #10 + '              },' + #10 +
      '              "scope": {' + #10 + '                "type": "string",' + #10 +
      '                "enum": ["projectGroup", "project"],' + #10 + '                "default": "projectGroup",' +
      #10 + '                "description": "Nur unused-public-member (#1102): Suchbereich der Verwendu' +
      'ngen: alle Projekte der Gruppe oder nur die Projekte der Datei.",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): search scope of th' +
      'e usages: all projects of the group or only the projects of the file."' + #10 + '              },' + #10 +
      '              "testsCountAsUse": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": true,' + #10,
    '                "description": "Nur unused-public-member (#1102): Verwendungen in Testproj' +
      'ekten zählen; aus = ein Mitglied, das nur Tests verwenden, wird gemeldet.",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): usages in test pro' +
      'jects count; off = a member used only by tests is reported."' + #10 + '              },' + #10 +
      '              "stringLiteralsCountAsUse": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": true,' + #10 +
      '                "description": "Nur unused-public-member (#1102): der Name als String-Lite' +
      'ral (''Name'') zählt als Verwendung (RTTI, MethodAddress, Skripte).",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): the name as a stri' +
      'ng literal (''Name'') counts as a usage (RTTI, MethodAddress, scripts)."' + #10 + '              },' + #10 +
      '              "keepAttributes": {' + #10 + '                "type": "array",' + #10,
    '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": [],' + #10 +
      '                "description": "Nur unused-public-member (#1102): Attribute am Mitglied od' +
      'er seinem Typ, die es als verwendet markieren, z. B. Keep oder Api.",' + #10 +
      '                "x-description-en": "Only unused-public-member (#1102): attributes on the ' +
      'member or its type that mark it as used, e.g. Keep or Api."' + #10 + '              },' + #10 +
      '              "keepPatterns": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": [],' + #10 +
      '                "description": "Nur unused-public-member (#1102): Namensmuster (* und ?) f' +
      'ür Mitglieder, die immer als verwendet gelten, z. B. TPlugin.* oder *Callback.",' + #10,
    '                "x-description-en": "Only unused-public-member (#1102): name patterns (* a' +
      'nd ?) for members that always count as used, e.g. TPlugin.* or *Callback."' + #10 + '              },' + #10 +
      '              "keep": {' + #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 + '                "default": [],' + #10 +
      '                "description": "Nur unused-uses (#1135): Units, die nie als ungenutzt gelt' +
      'en, zusätzlich zu usesKeep. Gilt auch für das Abblenden im Editor und „uses aufräumen“.",' + #10 +
      '                "x-description-en": "Only unused-uses (#1135): units that never count as u' +
      'nused, in addition to usesKeep. Also applies to the dimming in the editor and to \"Clean u' + 'p uses\"."' +
      #10 + '              },' + #10 + '              "checkUses": {' + #10 + '                "type": "boolean",' +
      #10,
    '                "default": true,' + #10 +
      '                "description": "Nur duplicate-declaration: doppelte Einträge in uses-Klaus' +
      'eln melden (#988).",' + #10 +
      '                "x-description-en": "Only duplicate-declaration: report duplicate entries ' +
      'in uses clauses (#988)."' + #10 + '              },' + #10 + '              "allowComments": {' + #10 +
      '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur text-after-final-end: Kommentare und Direktiven nach e' +
      'nd. erlauben (#991).",' + #10 +
      '                "x-description-en": "Only text-after-final-end: allow comments and directi' +
      'ves after end. (#991)."' + #10 + '              },' + #10 + '              "minRecordSize": {' + #10 +
      '                "type": "integer",' + #10 + '                "minimum": 1,' + #10 +
      '                "default": 16,' + #10,
    '                "description": "Nur managed-param-without-const: Record-Parameter ab diese' +
      'r Größe in Byte melden (#975).",' + #10 +
      '                "x-description-en": "Only managed-param-without-const: report record param' +
      'eters from this size in bytes (#975)."' + #10 + '              },' + #10 + '              "ignoreOverrides": {' +
      #10 + '                "type": "boolean",' + #10 + '                "default": true,' + #10 +
      '                "description": "Nur managed-param-without-const: Overrides nicht melden, i' +
      'hre Signatur gibt der Vorfahr vor (#975).",' + #10 +
      '                "x-description-en": "Only managed-param-without-const: do not report overr' +
      'ides, their signature is given by the ancestor (#975)."' + #10 + '              },' + #10 +
      '              "allowAttributes": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10,
    '                "default": [],' + #10 +
      '                "description": "Nur write-only-property: Attribute, die eine Property ohne' +
      ' read erlauben, mit oder ohne Endung Attribute (#978).",' + #10 +
      '                "x-description-en": "Only write-only-property: attributes that allow a pro' +
      'perty without read, with or without the suffix Attribute (#978)."' + #10 + '              },' + #10 +
      '              "requirePublic": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur xmldoc-mismatch: öffentliche Methoden und Properties v' +
      'on Typen im interface ohne XMLDoc melden (#979).",' + #10 +
      '                "x-description-en": "Only xmldoc-mismatch: report public methods and prope' +
      'rties of types in the interface without XMLDoc (#979)."' + #10 + '              },' + #10 +
      '              "checkReturns": {' + #10 + '                "type": "boolean",' + #10,
    '                "default": true,' + #10 +
      '                "description": "Nur xmldoc-mismatch: <returns> an Routinen ohne Ergebnis u' +
      'nd fehlendes <returns> prüfen (#979).",' + #10 +
      '                "x-description-en": "Only xmldoc-mismatch: check <returns> on routines wit' +
      'hout result and missing <returns> (#979)."' + #10 + '              },' + #10 + '              "allowTypes": {' +
      #10 + '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 + '                "default": [],' + #10 +
      '                "description": "Nur unrelated-class-cast: Typen, die absichtlich hart umge' +
      'wandelt werden, als Typname (Quelle oder Ziel) oder Paar \"Quelle=Ziel\", z. B. [\"TEdit=T' +
      'Button\"] (#1129).",' + #10,
    '                "x-description-en": "Only unrelated-class-cast: types that are cast hard o' +
      'n purpose, as type name (source or target) or pair \"Source=Target\", e.g. [\"TEdit=TButto' + 'n\"] (#1129)."' +
      #10 + '              },' + #10 + '              "checkFree": {' + #10 + '                "type": "boolean",' +
      #10 + '                "default": true,' + #10 +
      '                "description": "Nur redundant-cast: auch eine Klassenumwandlung melden, di' +
      'e nur vor Free steht, z. B. TObject(FStrom).Free (#1139).",' + #10 +
      '                "x-description-en": "Only redundant-cast: also report a class cast that on' +
      'ly stands before Free, e.g. TObject(FStream).Free (#1139)."' + #10 + '              },' + #10 +
      '              "allowFirstElement": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10,
    '                "description": "Nur loop-runs-at-most-once: for-in aus einfachen Anweisung' +
      'en, das mit Exit bzw. Break endet (erstes Element holen), nicht melden (#1131).",' + #10 +
      '                "x-description-en": "Only loop-runs-at-most-once: do not report for-in mad' +
      'e of simple statements that ends with Exit or Break (fetching the first element) (#1131)."' + #10 +
      '              },' + #10 + '              "formatMethods": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": [],' + #10 +
      '                "description": "Nur format-args: weitere Routinen mit Formatstring und fol' +
      'gender Argumentliste [...], z. B. [\"TLogger.LogFmt\", \"Protokoll\"]; mit Punkt zählt ohn' +
      'e Namensauflösung der Methodenname hinter einem beliebigen Qualifizierer (#56).",' + #10,
    '                "x-description-en": "Only format-args: further routines with a format stri' +
      'ng and a following argument list [...], e.g. [\"TLogger.LogFmt\", \"Protocol\"]; with a do' +
      't the method name behind any qualifier counts, without name resolution (#56)."' + #10 + '              },' +
      #10 + '              "allowTables": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": [],' + #10 +
      '                "description": "Nur sql-write-without-where: Tabellen, die absichtlich gan' +
      'z geleert bzw. geändert werden, mit oder ohne Schema (#966).",' + #10 +
      '                "x-description-en": "Only sql-write-without-where: tables that are deliber' +
      'ately emptied or changed completely, with or without schema (#966)."' + #10 + '              },' + #10 +
      '              "allowProperties": {' + #10,
    '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Visible", "Enabled"],' + #10 +
      '                "description": "Nur duplicate-assignment: Properties, bei denen doppeltes ' +
      'Setzen gewollt sein kann (Setter mit Nebenwirkung), Muster mit * und ? (#1051).",' + #10 +
      '                "x-description-en": "Only duplicate-assignment: properties for which setti' +
      'ng them twice can be intended (setter with side effect), patterns with * and ? (#1051)."' + #10 +
      '              },' + #10 + '              "allowLazyInit": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": true,' + #10 +
      '                "description": "Nur getter-side-effect: Lazy-Initialisierung im Getter erl' +
      'auben (if FListe = nil then FListe := …, #1052).",' + #10,
    '                "x-description-en": "Only getter-side-effect: allow lazy initialization in' +
      ' the getter (if FList = nil then FList := …, #1052)."' + #10 + '              },' + #10 +
      '              "threadSafeTypes": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["TThreadList", "TThreadedQueue"],' + #10 +
      '                "description": "Nur parallel-for-shared-write: Typen, die als threadsicher' +
      ' gelten; ihre Sammlungsaufrufe in TParallel.For bleiben still (#1058).",' + #10 +
      '                "x-description-en": "Only parallel-for-shared-write: types that count as t' +
      'hread-safe; their collection calls in TParallel.For stay silent (#1058)."' + #10 + '              },' + #10 +
      '              "statements": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10,
    '                  "type": "string",' + #10 +
      '                  "enum": ["if", "else", "for", "while", "with", "case"]' + #10 + '                },' + #10 +
      '                "default": ["if", "else", "for", "while", "with"],' + #10 +
      '                "description": "Nur missing-begin-end: geprüfte Anweisungen; case prüft di' +
      'e Zweige von case-Anweisungen (#1025).",' + #10 +
      '                "x-description-en": "Only missing-begin-end: checked statements; case chec' +
      'ks the branches of case statements (#1025)."' + #10 + '              },' + #10 +
      '              "allowSingleLineExit": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur missing-begin-end: Exit, Continue, Break und raise in ' +
      'derselben Zeile wie die Bedingung erlauben (#1025).",' + #10,
    '                "x-description-en": "Only missing-begin-end: allow Exit, Continue, Break a' +
      'nd raise on the same line as the condition (#1025)."' + #10 + '              },' + #10 +
      '              "allowSameLine": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur missing-begin-end: eine einzelne Anweisung in derselbe' +
      'n Zeile wie Bedingung bzw. Schleifenkopf erlauben (#1025).",' + #10 +
      '                "x-description-en": "Only missing-begin-end: allow a single statement on t' +
      'he same line as the condition or loop header (#1025)."' + #10 + '              },' + #10 +
      '              "disabledChecks": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 +
      '                  "pattern": "^[EeHhWw][0-9]{4}$"' + #10 + '                },' + #10 +
      '                "default": [],' + #10,
    '                "description": "Nur type-restriction-violated: Compilercodes, die die Rege' +
      'l nicht prüft, z. B. [\"E2425\"] (#994).",' + #10 +
      '                "x-description-en": "Only type-restriction-violated: compiler codes the ru' +
      'le does not check, e.g. [\"E2425\"] (#994)."' + #10 + '              },' + #10 +
      '              "searchPaths": {' + #10 + '                "type": "string",' + #10 +
      '                "enum": ["project", "atlas", "both"],' + #10 + '                "default": "project",' + #10 +
      '                "description": "Nur uses-unit-not-found: wo nach Units gesucht wird (#1016' +
      '). project: wie der Compiler (Projekt, Suchpfade der .dproj, Bibliothekspfade der Installa' +
      'tion, .pas und .dcu); atlas: was Atlas kennt (Index, Quellpfade der Installation); both: b' + 'eides.",' + #10,
    '                "x-description-en": "Only uses-unit-not-found: where units are searched (#' +
      '1016). project: like the compiler (project, search paths of the .dproj, library paths of t' +
      'he installation, .pas and .dcu); atlas: what Atlas knows (index, source paths of the insta' +
      'llation); both: both."' + #10 + '              },' + #10 + '              "switchConstants": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 + '                "default": [],' + #10 +
      '                "description": "Nur constant-condition: Konstanten, die bewusst als Schalt' +
      'er dienen; Bedingungen darauf werden nicht gemeldet (#1041).",' + #10 +
      '                "x-description-en": "Only constant-condition: constants that deliberately ' +
      'serve as switches; conditions on them are not reported (#1041)."' + #10 + '              },' + #10,
    '              "defaultEncoding": {' + #10 + '                "type": "string",' + #10 +
      '                "enum": ["UTF8", "Unicode", "BigEndianUnicode", "ANSI", "ASCII", "UTF7", "' + 'Default"],' +
      #10 + '                "default": "UTF8",' + #10 +
      '                "description": "Nur load-without-encoding: Kodierung, die die Korrektur ei' +
      'nsetzt (TEncoding.<Wert>) (#1061).",' + #10 +
      '                "x-description-en": "Only load-without-encoding: encoding the fix inserts ' +
      '(TEncoding.<value>) (#1061)."' + #10 + '              },' + #10 + '              "namePatterns": {' + #10 +
      '                "type": "array",' + #10 + '                "items": {' + #10 +
      '                  "type": "string"' + #10 + '                },' + #10 +
      '                "default": ["Betrag", "Preis", "Summe", "Netto", "Brutto", "Steuer", "Amou' + 'nt", "Price"],' +
      #10,
    '                "description": "Nur money-as-float: Namensteile, die einen Geldbetrag beze' +
      'ichnen; maßgeblich ist der letzte Teil des Namens, Mehrzahl eingeschlossen (#1064).",' + #10 +
      '                "x-description-en": "Only money-as-float: name parts that denote an amount' +
      ' of money; the last part of the name counts, plurals included (#1064)."' + #10 + '              },' + #10 +
      '              "checkRound": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": false,' + #10 +
      '                "description": "Nur money-as-float: zusätzlich Round mit einem Geldbetrag ' +
      'im Argument melden (Banker''s Rounding) (#1064).",' + #10 +
      '                "x-description-en": "Only money-as-float: also report Round with an amount' +
      ' of money in the argument (banker''s rounding) (#1064)."' + #10 + '              },' + #10 +
      '              "min": {' + #10 + '                "type": "integer",' + #10 + '                "minimum": 2,' +
      #10,
    '                "default": 4,' + #10 +
      '                "description": "Nur string-if-chain: so viele Vergleiche desselben Strings' +
      ' in einer if-Kette meldet die Regel (#1066).",' + #10 +
      '                "x-description-en": "Only string-if-chain: the rule reports this many comp' +
      'arisons of the same string in an if chain (#1066)."' + #10 + '              },' + #10 +
      '              "ignoreStrictPrivate": {' + #10 + '                "type": "boolean",' + #10 +
      '                "default": true,' + #10 +
      '                "description": "Nur member-hides-ancestor: verdeckte strict private Member' +
      ' des Vorfahren nicht melden (#1003).",' + #10 +
      '                "x-description-en": "Only member-hides-ancestor: do not report hidden stri' +
      'ct private members of the ancestor (#1003)."' + #10 + '              }' + #10 + '            }' + #10 +
      '          }' + #10 + '        ]' + #10 + '      },' + #10 + '      "x-scope": "both",' + #10 +
      '      "x-area": "rules",' + #10,
    '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Tabelle aus dem Regelkatalog",' + #10 +
      '      "x-issue": "#41"' + #10 + '    },' + #10 + '    "profile": {' + #10 +
      '      "description": "Regelprofil: standard, fast (nur Bugs und Schwachstellen), strict (e' +
      'xperimentelle Regeln an, minConfidence low), security, style oder ein eigenes aus \"profil' +
      'es\". Als Objekt getrennt für Editor und Kommandozeile.",' + #10 +
      '      "x-description-en": "Rule profile: standard, fast (only bugs and vulnerabilities), s' +
      'trict (experimental rules on, minConfidence low), security, style or a custom one from \"p' +
      'rofiles\". As an object separately for editor and command line.",' + #10 + '      "default": "standard",' + #10 +
      '      "oneOf": [' + #10 + '        {' + #10 + '          "type": "string"' + #10 + '        },' + #10 +
      '        {' + #10 + '          "type": "object",' + #10 + '          "additionalProperties": false,' + #10 +
      '          "properties": {' + #10,
    '            "editor": {' + #10 + '              "type": "string",' + #10 +
      '              "description": "Profil im Editor.",' + #10 +
      '              "x-description-en": "Profile in the editor."' + #10 + '            },' + #10 +
      '            "cli": {' + #10 + '              "type": "string",' + #10 +
      '              "description": "Profil der Kommandozeile (--check), z. B. strict im CI.",' + #10 +
      '              "x-description-en": "Profile of the command line (--check), e.g. strict in C' + 'I."' + #10 +
      '            }' + #10 + '          }' + #10 + '        }' + #10 + '      ],' + #10 + '      "examples": [' + #10 +
      '        "fast",' + #10 + '        "strict"' + #10 + '      ],' + #10 + '      "x-scope": "project",' + #10 +
      '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#146"' + #10 +
      '    },' + #10 + '    "profiles": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Eigene Regelprofile: Name → { \"extends\": eingebautes oder eigenes ' +
      'Profil, \"categories\": nur diese Kategorien, \"rules\": Regel-ID → Schweregrad }.",' + #10 +
      '      "x-description-en": "Custom rule profiles: name → { \"extends\": built-in or custom ' +
      'profile, \"categories\": only these categories, \"rules\": rule id → severity }.",' + #10 +
      '      "additionalProperties": {' + #10 + '        "type": "object",' + #10 +
      '        "additionalProperties": false,' + #10 + '        "properties": {' + #10 + '          "extends": {' +
      #10 + '            "type": "string"' + #10 + '          },' + #10 + '          "categories": {' + #10 +
      '            "type": "array",' + #10 + '            "items": {' + #10 + '              "type": "string",' + #10 +
      '              "enum": [' + #10 + '                "bug",' + #10 + '                "vulnerability",' + #10 +
      '                "code-smell",' + #10 + '                "security-hotspot"' + #10,
    '              ]' + #10 + '            }' + #10 + '          },' + #10 + '          "rules": {' + #10 +
      '            "type": "object",' + #10 + '            "additionalProperties": {' + #10 +
      '              "type": "string",' + #10 + '              "enum": [' + #10 + '                "off",' + #10 +
      '                "hint",' + #10 + '                "info",' + #10 + '                "information",' + #10 +
      '                "warning",' + #10 + '                "error"' + #10 + '              ]' + #10 + '            }' +
      #10 + '          }' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "project",' + #10 +
      '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Profil-Editor",' + #10 + '      "x-issue": "#146"' +
      #10 + '    },' + #10 + '    "ruleChecks": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Prüfregeln in der LSP-Sitzung (#1454): Modul-Schalter „Prüfregeln“ d' +
      'es Plugins (Tools › Optionen › Atlas › Prüfregeln). Aus = der Server prüft in der Sitzung ' +
      'der IDE keine Regeln; es erscheinen nur Syntaxfehler und Compilermeldungen. AtlasServer --' +
      'check und das MCP-Werkzeug prüfen weiter nach atlas.json.",' + #10 +
      '      "x-description-en": "Rule checks in the LSP session (#1454): module switch \"Rule ch' +
      'ecks\" of the plugin (Tools › Options › Atlas › Rule checks). Off = the server checks no r' +
      'ules in the IDE session; only syntax errors and compiler messages appear. AtlasServer --ch' +
      'eck and the MCP tool keep checking according to atlas.json.",' + #10 + '      "additionalProperties": false,' +
      #10 + '      "properties": {' + #10 + '        "enabled": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Hauptschalter: false = keine Regelprüfung in der LSP-Sitzung (Mi' +
      'tteilung beim Start und bei jeder Änderung); --check und MCP unverändert.",' + #10 +
      '          "x-description-en": "Main switch: false = no rule checks in the LSP session (not' +
      'ice at start and on every change); --check and MCP unchanged."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "rules",' + #10 + '      "x-page": "Prüfregeln",' + #10 +
      '      "x-control": "Kontrollkästchen „Prüfregeln“ (Modul-Schalter)",' + #10 + '      "x-issue": "#1454"' + #10 +
      '    },' + #10 + '    "overrides": {' + #10 + '      "type": "array",' + #10 +
      '      "description": "Pfadregeln: Schweregrade für Dateien, die eines der Glob-Muster tref' +
      'fen, z. B. Tests oder generierten Code herabstufen. Regel-ID \"*\" steht für alle Regeln; ' +
      'spätere Einträge haben Vorrang.",' + #10,
    '      "x-description-en": "Path rules: severities for files that match one of the glob pat' +
      'terns, e.g. downgrade tests or generated code. Rule id \"*\" stands for all rules; later e' +
      'ntries take precedence.",' + #10 + '      "items": {' + #10 + '        "type": "object",' + #10 +
      '        "required": [' + #10 + '          "files"' + #10 + '        ],' + #10 +
      '        "additionalProperties": false,' + #10 + '        "properties": {' + #10 + '          "files": {' + #10 +
      '            "type": "array",' + #10 + '            "items": {' + #10 + '              "type": "string"' + #10 +
      '            }' + #10 + '          },' + #10 + '          "rules": {' + #10 + '            "type": "object",' +
      #10 + '            "additionalProperties": {' + #10 + '              "type": "string",' + #10 +
      '              "enum": [' + #10 + '                "off",' + #10 + '                "hint",' + #10 +
      '                "info",' + #10 + '                "information",' + #10,
    '                "warning",' + #10 + '                "error"' + #10 + '              ]' + #10 + '            }' +
      #10 + '          }' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "project",' + #10 +
      '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Liste mit Mustern",' + #10 +
      '      "x-issue": "#146"' + #10 + '    },' + #10 + '    "excludeTests": {' + #10 + '      "type": "boolean",' +
      #10 + '      "default": false,' + #10 +
      '      "description": "Test-Units und Testprojekte (uses DUnitX.TestFramework, TestFramewor' +
      'k oder TestInsight.*) nicht prüfen. Global für alle Projekte schaltbar; eine atlas.json, d' +
      'ie den Schlüssel nennt, geht vor.",' + #10 +
      '      "x-description-en": "Do not check test units and test projects (uses DUnitX.TestFram' +
      'ework, TestFramework or TestInsight.*). Switchable globally for all projects; an atlas.jso' +
      'n that names the key takes precedence.",' + #10 + '      "x-scope": "both",' + #10,
    '      "x-area": "rules",' + #10 + '      "x-page": "Prüfregeln",' + #10 +
      '      "x-control": "Kontrollkästchen",' + #10 + '      "x-issue": "#146"' + #10 + '    },' + #10 +
      '    "testProfile": {' + #10 + '      "type": "string",' + #10 +
      '      "description": "Regelprofil für Test-Units und Testprojekte; leer: wie \"profile\"."' + ',' + #10 +
      '      "x-description-en": "Rule profile for test units and test projects; empty: like \"pr' + 'ofile\".",' +
      #10 + '      "examples": [' + #10 + '        "fast"' + #10 + '      ],' + #10 + '      "x-scope": "project",' +
      #10 + '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#146"' +
      #10 + '    },' + #10 + '    "compiler": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Compiler-Anbindung: Kommandozeilen-Compiler (dcc32/dcc64) oder eine ' +
      'eigene IDE über cc.ps1.",' + #10,
    '      "x-description-en": "Compiler connection: command line compiler (dcc32/dcc64) or a s' +
      'eparate IDE through cc.ps1.",' + #10 + '      "additionalProperties": false,' + #10 + '      "properties": {' +
      #10 + '        "onSave": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Nach dem Speichern einer Quelldatei das Projekt im Hintergrund k' +
      'ompilieren und die Meldungen anzeigen. Nur mit dem Kommandozeilen-Compiler; über die IDE (' +
      'backend ide) kompiliert Atlas wegen ihrer Startzeit nur auf den Befehl „Projekt kompiliere' +
      'n“ (atlas.server.compile).",' + #10 +
      '          "x-description-en": "After saving a source file compile the project in the backg' +
      'round and show the messages. Only with the command line compiler; through the IDE (backend' +
      ' ide) Atlas compiles only on the command “Compile project” (atlas.server.compile) because ' +
      'of its start time."' + #10 + '        },' + #10,
    '        "backend": {' + #10 + '          "type": "string",' + #10 + '          "enum": [' + #10 +
      '            "auto",' + #10 + '            "dcc",' + #10 + '            "ide",' + #10 + '            "off"' +
      #10 + '          ],' + #10 + '          "default": "auto",' + #10 + '          "x-control": "Auswahl",' + #10,
    '          "description": "Weg zum Compiler. auto: Atlas erkennt vorher je Delphi-Installat' +
      'ion, ob dcc32/dcc64 vorhanden und nutzbar ist (die Starter und Community Edition melden ei' +
      'nen Lizenztext statt zu kompilieren), merkt sich das und nimmt dann dcc, sonst ide (wenn i' +
      'deCommand eingerichtet ist), sonst off. dcc: nur der Kommandozeilen-Compiler. ide: eine ei' +
      'gene IDE über cc.ps1 (ideCommand), immer mit eigener Instanz; die IDE des Benutzers wird n' +
      'ie angesprochen. off: Atlas kompiliert nie selbst. Ist kein Compiler nutzbar, meldet Atlas' +
      ' das einmal mit Grund und Ausweg, zeigt es im Status (atlas.server.status) und der Befehl ' +
      '„Projekt kompilieren“ antwortet mit dem Grund.",' + #10,
    '          "x-description-en": "Way to the compiler. auto: Atlas first detects per Delphi i' +
      'nstallation whether dcc32/dcc64 exists and is usable (the Starter and Community Edition pr' +
      'int a license text instead of compiling), remembers it and then takes dcc, otherwise ide (' +
      'if ideCommand is set up), otherwise off. dcc: only the command line compiler. ide: a separ' +
      'ate IDE through cc.ps1 (ideCommand), always with its own instance; the user''s IDE is never' +
      ' touched. off: Atlas never compiles itself. If no compiler is usable, Atlas reports it onc' +
      'e with reason and way out, shows it in the status (atlas.server.status), and the command “' +
      'Compile project” answers with the reason."' + #10 + '        },' + #10 + '        "ideCommand": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "x-control": "Datei wählen",' + #10,
    '          "description": "Pfad zu cc.ps1 (Claude-Compile) für den Weg über die IDE; leer =' +
      ' nicht eingerichtet. Atlas startet damit eine eigene Scratch-IDE (-Instance), nutzt sie fü' +
      'r weitere Läufe wieder und beendet sie mit dem Server.",' + #10 +
      '          "x-description-en": "Path to cc.ps1 (Claude-Compile) for the way through the IDE' +
      '; empty = not set up. Atlas starts its own scratch IDE with it (-Instance), reuses it for ' +
      'further runs and ends it with the server.",' + #10 + '          "examples": [' + #10 +
      '            "C:\\Projekte\\IDE-Plugins\\Claude-Compile\\cc.ps1"' + #10 + '          ]' + #10 + '        }' +
      #10 + '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "build",' + #10 +
      '      "x-page": "Compiler",' + #10 + '      "x-control": "Kontrollkästchen, Auswahl, Datei wählen",' + #10 +
      '      "x-issue": "#40, #261"' + #10 + '    },' + #10 + '    "vcs": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Versionsverwaltung (Git, SVN) für geänderte Dateien, Branch und Revi' + 'sion.",' + #10 +
      '      "x-description-en": "Version control (Git, SVN) for changed files, branch and revisi' + 'on.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "provider": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "auto",' + #10 +
      '            "git",' + #10 + '            "svn",' + #10 + '            "off"' + #10 + '          ],' + #10 +
      '          "default": "auto",' + #10 +
      '          "description": "auto: nach gefundener Arbeitskopie (.git oder .svn, die nächstli' +
      'egende gilt, bei Gleichstand Git). git bzw. svn: nur diese Art. off: ohne Versionsverwaltu' +
      'ng. Git und SVN über die Kommandozeile (git bzw. svn, TortoiseSVN mit Kommandozeilenwerkze' +
      'ugen genügt); fehlt das Programm, meldet Atlas das einmal und arbeitet ohne Versionsangabe' + 'n weiter.",' +
      #10,
    '          "x-description-en": "auto: by the working copy found (.git or .svn, the nearest ' +
      'one applies, on a tie Git). git or svn: only this kind. off: without version control. Git ' +
      'and SVN through the command line (git or svn, TortoiseSVN with command line tools is enoug' +
      'h); if the program is missing, Atlas reports it once and continues without version informa' + 'tion."' + #10 +
      '        },' + #10 + '        "git": {' + #10 + '          "type": "object",' + #10 +
      '          "description": "Programm git (#1285): path = Pfad zu git.exe, leer = automatisch' + ' suchen.",' +
      #10 + '          "x-description-en": "Program git (#1285): path = path to git.exe, empty = search' +
      ' automatically.",' + #10 + '          "additionalProperties": false,' + #10 + '          "properties": {' + #10 +
      '            "path": {' + #10 + '              "type": "string",' + #10 + '              "default": "",' + #10,
    '              "examples": ["C:\\Tools\\PortableGit\\cmd\\git.exe"],' + #10 +
      '              "description": "Pfad zu git.exe; leer = in PATH und den üblichen Installatio' +
      'nsordnern suchen. Ein gesetzter Pfad gilt allein: Fehlt die Datei, meldet Atlas das einmal' +
      ' je Sitzung und sucht nicht woanders.",' + #10 +
      '              "x-description-en": "Path to git.exe; empty = search in PATH and the usual i' +
      'nstallation folders. A set path applies alone: if the file is missing, Atlas reports it on' +
      'ce per session and does not search elsewhere."' + #10 + '            }' + #10 + '          }' + #10 +
      '        },' + #10 + '        "svn": {' + #10 + '          "type": "object",' + #10 +
      '          "description": "Programm svn (#1285): path = Pfad zu svn.exe, leer = automatisch' + ' suchen.",' +
      #10 + '          "x-description-en": "Program svn (#1285): path = path to svn.exe, empty = search' +
      ' automatically.",' + #10 + '          "additionalProperties": false,' + #10,
    '          "properties": {' + #10 + '            "path": {' + #10 + '              "type": "string",' + #10 +
      '              "default": "",' + #10 + '              "examples": ["C:\\Program Files\\SlikSvn\\bin\\svn.exe"],' +
      #10 + '              "description": "Pfad zu svn.exe (TortoiseSVN mit Kommandozeilenwerkzeugen, S' +
      'likSVN …); leer = in PATH und den üblichen Installationsordnern suchen. Ein gesetzter Pfad' +
      ' gilt allein: Fehlt die Datei, meldet Atlas das einmal je Sitzung und sucht nicht woanders' + '.",' + #10 +
      '              "x-description-en": "Path to svn.exe (TortoiseSVN with command line tools, S' +
      'likSVN …); empty = search in PATH and the usual installation folders. A set path applies a' +
      'lone: if the file is missing, Atlas reports it once per session and does not search elsewh' + 'ere."' + #10 +
      '            }' + #10 + '          }' + #10 + '        },' + #10 + '        "projects": {' + #10 +
      '          "type": "array",' + #10,
    '          "default": [],' + #10 +
      '          "description": "Persönliche Art und Hauptbranch je Delphi-Projekt (#1286). Es gi' +
      'lt der Abschnitt vcs der .atlas (je Feld), sonst die Zeile für genau diese .dproj, dann di' +
      'e der geöffneten .groupproj, dann der längste passende Ordner, sonst vcs.provider. Für ein' +
      'en Ordner (Änderungsmarken) gelten .dproj- und .groupproj-Zeilen für ihren Ordner, der län' +
      'gste passende gewinnt.",' + #10 +
      '          "x-description-en": "Personal kind and main branch per Delphi project (#1286). T' +
      'he section vcs of the .atlas applies (per field), otherwise the row for exactly this .dpro' +
      'j, then the one of the opened .groupproj, then the longest matching folder, otherwise vcs.' +
      'provider. For a folder (change markers) .dproj and .groupproj rows apply to their folder, ' +
      'the longest match wins.",' + #10 + '          "items": {' + #10 + '            "type": "object",' + #10,
    '            "additionalProperties": false,' + #10 + '            "required": ["match"],' + #10 +
      '            "properties": {' + #10 + '              "match": {' + #10 + '                "type": "string",' +
      #10 + '                "minLength": 1,' + #10 +
      '                "examples": ["C:\\Projekte\\Kasse\\Kasse.groupproj", "C:\\Projekte\\Kasse\' + '\Fremd\\Lib"],' +
      #10 + '                "description": "Gilt für: Pfad einer .dproj, einer .groupproj oder eines O' +
      'rdners (ohne Groß-/Kleinschreibung, auch UNC).",' + #10 +
      '                "x-description-en": "Applies to: path of a .dproj, a .groupproj or a folde' +
      'r (case-insensitive, also UNC)."' + #10 + '              },' + #10 + '              "provider": {' + #10 +
      '                "type": "string",' + #10 + '                "enum": ["auto", "git", "svn", "off"],' + #10 +
      '                "default": "auto",' + #10,
    '                "description": "Art: auto nach gefundener Arbeitskopie, git bzw. svn nur d' +
      'iese Art, off startet dort kein git bzw. svn.",' + #10 +
      '                "x-description-en": "Kind: auto by the working copy found, git or svn only' +
      ' this kind, off starts no git or svn there."' + #10 + '              },' + #10 +
      '              "mainBranch": {' + #10 + '                "type": "string",' + #10 +
      '                "default": "",' + #10 + '                "examples": ["develop", "trunk"],' + #10 +
      '                "description": "Hauptbranch (Basis für „Beginnen“, Vergleich für „Eingehen' +
      'd“); leer = raten (Git main, sonst master; SVN trunk). issues.branchBase hat Vorrang.",' + #10 +
      '                "x-description-en": "Main branch (base for “Start”, comparison for “Incomi' +
      'ng”); empty = guess (Git main, otherwise master; SVN trunk). issues.branchBase takes prece' + 'dence."' + #10 +
      '              }' + #10 + '            }' + #10,
    '          }' + #10 + '        },' + #10 + '        "timeoutSeconds": {' + #10 + '          "type": "integer",' +
      #10 + '          "minimum": 1,' + #10 + '          "maximum": 300,' + #10 + '          "default": 15,' + #10 +
      '          "description": "Zeitlimit je Aufruf von git bzw. svn in Sekunden (#1285); danach' +
      ' beendet Atlas den Prozess. Aufrufe mit eigenem, kürzerem Limit (Willkommensseite 1 s) beh' +
      'alten ihres; Branch anlegen und Pull nehmen das größere aus diesem Wert und 30 s.",' + #10 +
      '          "x-description-en": "Time limit per call of git or svn in seconds (#1285); after' +
      ' it Atlas ends the process. Calls with their own shorter limit (welcome page 1 s) keep the' +
      'irs; creating a branch and pull take the larger of this value and 30 s."' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "vcs",' + #10 +
      '      "x-page": "Versionsverwaltung",' + #10,
    '      "x-control": "Auswahl, Datei wählen mit „Prüfen“, Zahl, Tabelle Projekte",' + #10 +
      '      "x-issue": "#571, #1285, #1286"' + #10 + '    },' + #10 + '    "completion": {' + #10 +
      '      "type": "object",' + #10 + '      "description": "Code-Vervollständigung.",' + #10 +
      '      "x-description-en": "Code completion.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "matching": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": [' + #10 + '            "fuzzy",' + #10 + '            "prefix"' + #10 + '          ],' + #10 +
      '          "default": "fuzzy",' + #10 +
      '          "description": "Auswahl der Vorschläge: unscharf (Teilfolgen, Kürzel wie TSL für' +
      ' TStringList) oder nur nach Präfix, falls ein Editor nachträglich strikt filtert.",' + #10,
    '          "x-description-en": "Choice of suggestions: fuzzy (subsequences, abbreviations l' +
      'ike TSL for TStringList) or only by prefix, in case an editor filters strictly afterwards.' + '"' + #10 +
      '        },' + #10 + '        "interfaceSection": {' + #10 + '          "x-scope": "project",' + #10 +
      '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "private",' + #10 +
      '            "protected",' + #10 + '            "public"' + #10 + '          ],' + #10 +
      '          "default": "public",' + #10 +
      '          "description": "Abschnitt der Klasse, in den „Interface implementieren“ die Dekl' +
      'arationen fehlender Interface-Methoden schreibt.",' + #10 +
      '          "x-description-en": "Section of the class into which “Implement interface” write' +
      's the declarations of missing interface methods."' + #10 + '        },' + #10 + '        "senderCast": {' + #10 +
      '          "x-scope": "project",' + #10 + '          "type": "string",' + #10,
    '          "enum": [' + #10 + '            "as",' + #10 + '            "cast"' + #10 + '          ],' + #10 +
      '          "default": "as",' + #10 +
      '          "description": "Form der Typumwandlung, wenn nach Sender. ein Member der zugewie' +
      'senen Komponenten gewählt wird: \"as\" schreibt (Sender as TButton), \"cast\" schreibt TBu' + 'tton(Sender).",' +
      #10 + '          "x-description-en": "Form of the type cast when a member of the assigned compone' +
      'nts is chosen after Sender.: \"as\" writes (Sender as TButton), \"cast\" writes TButton(Se' + 'nder)."' + #10 +
      '        },' + #10 + '        "offerTryFinally": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Nach Übernahme eines Konstruktors in \"Liste := TStringList.Crea' +
      'te;\" anbieten, den folgenden Code in try…finally mit Freigabe einzuschließen.",' + #10,
    '          "x-description-en": "After accepting a constructor in \"List := TStringList.Crea' +
      'te;\" offer to wrap the following code in try…finally with freeing."' + #10 + '        },' + #10 +
      '        "freeStyle": {' + #10 + '          "x-scope": "project",' + #10 + '          "type": "string",' + #10 +
      '          "enum": [' + #10 + '            "free",' + #10 + '            "freeAndNil"' + #10 + '          ],' +
      #10 + '          "default": "free",' + #10 +
      '          "description": "Freigabe im finally von „Freigabe absichern“: \"free\" schreibt ' +
      'Liste.Free, \"freeAndNil\" schreibt FreeAndNil(Liste).",' + #10 +
      '          "x-description-en": "Freeing in the finally of “Secure freeing”: \"free\" writes' +
      ' List.Free, \"freeAndNil\" writes FreeAndNil(List)."' + #10 + '        },' + #10 + '        "keywords": {' +
      #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Schlüsselwörter passend zur Stelle vorschlagen (in Anweisungen b' +
      'egin, try …, im Klassenrumpf property, private …, nach \":\" string, array …), sobald ein ' +
      'Zeichen getippt ist.",' + #10 +
      '          "x-description-en": "Suggest keywords that fit the place (in statements begin, t' +
      'ry …, in the class body property, private …, after \":\" string, array …) as soon as a cha' +
      'racter is typed."' + #10 + '        },' + #10 + '        "postfixTemplates": {' + #10 +
      '          "x-area": "snippets",' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "Postfix-Vorlagen hinter einem Ausdruck anbieten: Liste.for wird ' +
      'zu for var Item in Liste do, FKunde.notnil zu if Assigned(FKunde) then, dazu tryf, ifa, fm' +
      't, nil, not, if, forin, free, try, var, exit und eigene Vorlagen mit \"postfix: true\".",' + #10,
    '          "x-description-en": "Offer postfix templates after an expression: List.for becom' +
      'es for var Item in List do, FCustomer.notnil becomes if Assigned(FCustomer) then, plus try' +
      'f, ifa, fmt, nil, not, if, forin, free, try, var, exit and your own templates with \"postf' + 'ix: true\"."' +
      #10 + '        },' + #10 + '        "genericConstraints": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Nach \"TObjectList<\" nur Typen vorschlagen, die die Constraints' +
      ' des Typparameters erfüllen (class, record, constructor, Interface oder Klasse), mit Übers' +
      'chrift „T: class · nur Klassen“ und den ausgeblendeten Arten in der Fußzeile.",' + #10,
    '          "x-description-en": "After \"TObjectList<\" only suggest types that satisfy the ' +
      'constraints of the type parameter (class, record, constructor, interface or class), with t' +
      'he heading \"T: class · classes only\" and the hidden kinds in the footer."' + #10 + '        },' + #10 +
      '        "createAccessors": {' + #10 + '          "x-scope": "project",' + #10 + '          "type": "boolean",' +
      #10 + '          "default": true,' + #10 +
      '          "description": "Nach read bzw. write einer Eigenschaftsdeklaration oben in der L' +
      'iste „Feld FName anlegen“, „GetName anlegen“ und „SetName anlegen“ anbieten: Feld im priva' +
      'te-Abschnitt (strict private, wenn die Klasse ihn nutzt), Methoden im Abschnitt nach acces' +
      'sorSection, Setter mit Änderungsprüfung.",' + #10,
    '          "x-description-en": "After read or write of a property declaration offer \"Creat' +
      'e field FName\", \"Create GetName\" and \"Create SetName\" at the top of the list: field i' +
      'n the private section (strict private if the class uses it), methods in the section given ' +
      'by accessorSection, setter with change check."' + #10 + '        },' + #10 + '        "accessorSection": {' +
      #10 + '          "x-scope": "project",' + #10 + '          "type": "string",' + #10 + '          "enum": [' +
      #10 + '            "private",' + #10 + '            "protected"' + #10 + '          ],' + #10 +
      '          "default": "private",' + #10 +
      '          "description": "Abschnitt der Klasse, in den „GetName anlegen“ und „SetName anle' +
      'gen“ die Zugriffsmethoden schreiben.",' + #10 +
      '          "x-description-en": "Section of the class into which \"Create GetName\" and \"Cr' +
      'eate SetName\" write the accessor methods."' + #10 + '        },' + #10,
    '        "resourceStrings": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Strg+Leertaste in einem String-Literal bietet „Als resourcestrin' +
      'g auslagern“ an: Name aus den ersten Wörtern (S + CamelCase, Umlaute ersetzt), Eintrag im ' +
      'resourcestring-Abschnitt; gibt es den Text schon, zusätzlich „Vorhandenen verwenden“. Nich' +
      't in Konstanten, Attributen, case-Marken und Parametervorgaben.",' + #10 +
      '          "x-description-en": "Ctrl+Space in a string literal offers \"Extract as resource' +
      'string\": name from the first words (S + CamelCase, umlauts replaced), entry in the resour' +
      'cestring section; if the text already exists, also \"Use existing\". Not in constants, att' +
      'ributes, case labels and parameter defaults."' + #10 + '        },' + #10 + '        "resourceStringUnit": {' +
      #10 + '          "x-scope": "project",' + #10 + '          "type": "string",' + #10,
    '          "default": "",' + #10 +
      '          "description": "Unit, in deren interface-Teil ausgelagerte resourcestrings komme' +
      'n (etwa App.Texte); sie wird bei Bedarf in uses eingetragen. Leer: implementation-Teil der' +
      ' eigenen Unit.",' + #10 +
      '          "x-description-en": "Unit whose interface part receives extracted resourcestring' +
      's (for example App.Texts); it is added to uses when needed. Empty: implementation part of ' + 'the own unit."' +
      #10 + '        },' + #10 + '        "typeConversion": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["off", "helper", "function"],' + #10 + '          "default": "off",' + #10,
    '          "description": "Passt ein Eintrag nicht zum erwarteten Typ (Zuweisung, Argument)' +
      ', schlägt Atlas die übliche Umwandlung als weiteren Eintrag direkt über dem Original vor, ' +
      'etwa Count.ToString für eine String-Zuweisung: Zahl, Boolean, Datum und Aufzählung nach st' +
      'ring, string nach Zahl. helper: Helper-Stil (X.ToString, X.ToInteger), wo es einen gibt, s' +
      'onst Funktion; function: Funktionsstil (IntToStr(X), StrToInt(X)); off: aus. Benötigte Uni' +
      'ts kommen ins uses. Für Gleitkomma nach Ganzzahl nur ein Hinweis auf Round und Trunc im De' + 'tailpanel.",' +
      #10,
    '          "x-description-en": "If an entry does not fit the expected type (assignment, arg' +
      'ument), Atlas suggests the usual conversion as an extra entry directly above the original,' +
      ' for example Count.ToString for a string assignment: number, Boolean, date and enumeration' +
      ' to string, string to number. helper: helper style (X.ToString, X.ToInteger) where one exi' +
      'sts, otherwise function; function: function style (IntToStr(X), StrToInt(X)); off: off. Re' +
      'quired units are added to uses. For floating point to integer only a hint on Round and Tru' +
      'nc in the detail panel.",' + #10 + '          "x-experimental": true,' + #10 + '          "x-offValue": "off",' +
      #10 + '          "x-issue": "#490"' + #10 + '        },' + #10 + '        "assignAllFields": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10,
    '          "description": "Hinter einem Record- oder Klassenausdruck mit Punkt am Anfang ei' +
      'ner Anweisung (Opts.) steht „Alle Felder zuweisen (n)“ ganz oben: je öffentlich beschreibb' +
      'arem Feld und jeder Property eine Zeile Opts.Feld := Platzhalter; in Deklarationsreihenfol' +
      'ge, mit 0, '''', False, nil oder dem ersten Aufzählungswert als Vorgabe im Platzhalter-Modus' +
      '. Felder, die die folgenden Zeilen schon zuweisen, fallen weg. Bei mehr als 15 Feldern zue' +
      'rst eine Liste mit Kontrollkästchen.",' + #10,
    '          "x-description-en": "After a record or class expression with a dot at the start ' +
      'of a statement (Opts.) \"Assign all fields (n)\" is at the very top: one line Opts.Field :' +
      '= placeholder per public writable field and property, in declaration order, with 0, '''', Fa' +
      'lse, nil or the first enumeration value as default in placeholder mode. Fields that the fo' +
      'llowing lines already assign are left out. With more than 15 fields a list with check boxe' +
      's comes first.",' + #10 + '          "x-experimental": true,' + #10 + '          "x-issue": "#491"' + #10 +
      '        },' + #10 + '        "usesDetails": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Im uses-Abschnitt: schon eingebundene Units ausblenden (die Fußz' +
      'eile nennt sie), Units nach Projekt, RTL/VCL und Drittanbietern gruppieren, Kurzformen auf' +
      ' den Namespace ergänzen (Classes → System.Classes), Units aus dem anderen Abschnitt mit „b' +
      'ereits im interface-Teil“ bzw. „… implementation-Teil“ und im interface-Teil Units mit Zir' +
      'kelbezug markieren; im Detailpanel Pfad und die ersten exportierten Typen. Aus: alle Units' +
      ' des Index als schlichte Liste.",' + #10,
    '          "x-description-en": "In the uses section: hide units already used (the footer na' +
      'mes them), group units by project, RTL/VCL and third party, complete short forms to the na' +
      'mespace (Classes → System.Classes), mark units from the other section with \"already in in' +
      'terface part\" or \"… implementation part\" and units with circular reference in the inter' +
      'face part; path and the first exported types in the detail panel. Off: all units of the in' +
      'dex as a plain list.",' + #10 + '          "x-issue": "#469"' + #10 + '        },' + #10 +
      '        "inheritedCall": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Nach „inherited “ zuerst den vollständigen Aufruf der gleichnami' +
      'gen Vorfahrmethode mit den Parametern der eigenen Methode anbieten (Marke „gleiche Paramet' +
      'er“), dann ihre übrigen Überladungen, in Konstruktoren und Destruktoren auch die übrigen K' +
      'onstruktoren bzw. Destruktoren der Vorfahren. Abstrakte Vorfahrmethoden fehlen, die Fußzei' +
      'le nennt sie. In Funktionen ergänzt die Übernahme „Result := “, wenn vor inherited nichts ' +
      'in der Zeile steht. Aus: nur die Namen der Vorfahrmethoden.",' + #10,
    '          "x-description-en": "After \"inherited \" first offer the complete call of the a' +
      'ncestor method of the same name with the parameters of the own method (label \"same parame' +
      'ters\"), then its other overloads, in constructors and destructors also the other construc' +
      'tors or destructors of the ancestors. Abstract ancestor methods are missing, the footer na' +
      'mes them. In functions accepting adds \"Result := \" if nothing precedes inherited on the ' +
      'line. Off: only the names of the ancestor methods.",' + #10 + '          "x-issue": "#482"' + #10 +
      '        },' + #10 + '        "attributes": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Nach „[“ vor einer Typ-, Methoden-, Feld-, Property- oder Parame' +
      'terdeklaration nur Attributklassen (Nachfahren von TCustomAttribute) ohne die Endung Attri' +
      'bute anbieten; bekannte zuerst (DUnitX Test, TestCase, TestFixture, Setup, TearDown, JSONN' +
      'ame, JSONMarshalled, die Compiler-Attribute weak, unsafe, volatile, Ref), rechts die Param' +
      'eter des Konstruktors bzw. die Unit, aus nicht eingebundenen Units mit uses-Eintrag. Nach ' +
      '„(“ zeigt der Parameter-Hint den Konstruktor. Aus: die gewöhnliche Liste.",' + #10,
    '          "x-description-en": "After \"[\" before a type, method, field, property or param' +
      'eter declaration only offer attribute classes (descendants of TCustomAttribute) without th' +
      'e suffix Attribute; known ones first (DUnitX Test, TestCase, TestFixture, Setup, TearDown,' +
      ' JSONName, JSONMarshalled, the compiler attributes weak, unsafe, volatile, Ref), on the ri' +
      'ght the parameters of the constructor or the unit, from units not yet used with a uses ent' +
      'ry. After \"(\" the parameter hint shows the constructor. Off: the ordinary list.",' + #10 +
      '          "x-issue": "#465"' + #10 + '        },' + #10 + '        "anonymousMethods": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Erwartet ein Argument oder eine Zuweisung einen Methodenreferenz' +
      'typ (reference to procedure/function, z. B. TProc, TFunc<T>, TPredicate<T> oder ein eigene' +
      'r), oben in der Liste ein Gerüst mit passender Signatur anbieten: procedure(const Value: T' +
      'Kunde) bzw. function(const Value: TKunde): Boolean mit begin/end und Cursor im Rumpf. Die ' +
      'Parameter Arg1, Arg2 der generischen RTL-Typen heißen Value bzw. nach ihrem Typ, mit dem P' +
      'arameterpräfix des Projekts. Nach „(“ erscheint das Gerüst von selbst. Aus: kein Gerüst.",' + #10,
    '          "x-description-en": "If an argument or an assignment expects a method reference ' +
      'type (reference to procedure/function, e.g. TProc, TFunc<T>, TPredicate<T> or your own), o' +
      'ffer a skeleton with matching signature at the top of the list: procedure(const Value: TCu' +
      'stomer) or function(const Value: TCustomer): Boolean with begin/end and the cursor in the ' +
      'body. The parameters Arg1, Arg2 of the generic RTL types are named Value or after their ty' +
      'pe, with the parameter prefix of the project. After \"(\" the skeleton appears by itself. ' +
      'Off: no skeleton.",' + #10 + '          "x-issue": "#468"' + #10 + '        },' + #10 +
      '        "withOrigin": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "In with-Blöcken Mitglieder des with-Objekts kennzeichnen: Marke ' +
      '„aus qryOrders“ (bei verschachtelten with das innerste passende Objekt, wie der Compiler),' +
      ' und wenn das Mitglied einen gleichnamigen lokalen Namen oder ein Mitglied von Self verdec' +
      'kt, die Warnmarke „verdeckt Self.Name“ mit Warnfläche. Das Detailpanel nennt beide Bedeutu' +
      'ngen. Aus: Mitglieder ohne Herkunft.",' + #10 +
      '          "x-description-en": "Mark members of the with object in with blocks: label \"fro' +
      'm qryOrders\" (for nested with the innermost matching object, like the compiler), and if t' +
      'he member hides a local name or a member of Self of the same name, the warning label \"hid' +
      'es Self.Name\" with warning background. The detail panel names both meanings. Off: members' +
      ' without origin.",' + #10 + '          "x-issue": "#481"' + #10 + '        },' + #10 +
      '        "exceptionClasses": {' + #10 + '          "type": "boolean",' + #10,
    '          "default": true,' + #10 +
      '          "description": "Nach „raise “ und „on E: “ nur Exception-Klassen anbieten. Nach ' +
      'raise Projektklassen vor denen der Bibliotheken, Übernahme als EFoo.Create('''') mit dem Cur' +
      'sor zwischen den Anführungszeichen, dazu je Klasse ein Eintrag EFoo.CreateFmt. Nach „on E:' +
      ' “ zuerst die Gruppe „Aus dem try-Block“ mit den Klassen aus <exception cref> der dort auf' +
      'gerufenen Routinen (und bekannten Fällen der RTL wie StrToInt → EConvertError), darunter „' +
      'Allgemein“; im selben except schon behandelte Klassen fehlen, Klassen, die ein früherer Zw' +
      'eig schon fängt, tragen die Warnung „nie erreicht“. Aus: die gewöhnliche Liste.",' + #10,
    '          "x-description-en": "After \"raise \" and \"on E: \" only offer exception classe' +
      's. After raise project classes before library classes, accepted as EFoo.Create('''') with th' +
      'e cursor between the quotes, plus one entry EFoo.CreateFmt per class. After \"on E: \" fir' +
      'st the group \"From the try block\" with the classes from <exception cref> of the routines' +
      ' called there (and known RTL cases such as StrToInt → EConvertError), below \"General\"; c' +
      'lasses already handled in the same except are missing, classes an earlier branch already c' +
      'atches carry the warning \"never reached\". Off: the ordinary list.",' + #10 + '          "x-issue": "#483"' +
      #10 + '        },' + #10 + '        "syntaxNotice": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Hinweis bei unvollständigem Code: Steht vor dem Cursor in der ak' +
      'tuellen Routine bzw. Klassendeklaration ein Syntaxfehler, zeigt die Liste oben die Warnlei' +
      'ste „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“; Klick auf die Zei' +
      'lenangabe springt dorthin. Ohne Vorschläge zeigt der leere Zustand den Fehler. Fehler in a' +
      'nderen Routinen und die Stelle, an der gerade getippt wird, zählen nicht. Aus: kein Hinwei' + 's.",' + #10 +
      '          "x-description-en": "Notice for incomplete code: if there is a syntax error befo' +
      're the cursor in the current routine or class declaration, the list shows the warning bar ' +
      '\"Results may be incomplete · syntax error in line n\" at the top; clicking the line numbe' +
      'r jumps there. Without suggestions the empty state shows the error. Errors in other routin' +
      'es and the place being typed do not count. Off: no notice.",' + #10 + '          "x-issue": "#457"' + #10,
    '        },' + #10 + '        "sameNameVariants": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Kommt ein Name in mehreren Units vor, jede Variante mit ihrer Un' +
      'it zeigen; die Variante, die der Compiler nach den uses wählt (letzte Unit gewinnt), steht' +
      ' zuerst mit „aktiv“, das Detailpanel nennt alle Units, die den Namen deklarieren. Aus: nur' +
      ' die aktive Variante.",' + #10 +
      '          "x-description-en": "If a name occurs in several units, show each variant with i' +
      'ts unit; the variant the compiler picks according to uses (last unit wins) comes first wit' +
      'h \"active\", the detail panel names all units declaring the name. Off: only the active va' + 'riant.",' + #10 +
      '          "x-issue": "#475"' + #10 + '        },' + #10 + '        "sameNameInsert": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["prefix", "uses"],' + #10 +
      '          "default": "prefix",' + #10,
    '          "description": "Übernahme einer nicht aktiven Variante: prefix fügt den Unit-Prä' +
      'fix ein (Vcl.Graphics.TBitmap), uses verschiebt die Unit in ihrer uses-Liste nach hinten b' +
      'zw. ergänzt sie; das Detailpanel warnt dann, dass andere Stellen ihre Bedeutung ändern kön' + 'nen.",' + #10 +
      '          "x-description-en": "Accepting a variant that is not active: prefix inserts the ' +
      'unit prefix (Vcl.Graphics.TBitmap), uses moves the unit to the back of its uses list or ad' +
      'ds it; the detail panel then warns that other places may change their meaning.",' + #10 +
      '          "x-issue": "#475"' + #10 + '        },' + #10 + '        "showFmxUnits": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Varianten aus FireMonkey-Units (FMX.*) zeigen. Aus: Die Fußzeile' +
      ' nennt sie als ausgeblendet.",' + #10,
    '          "x-description-en": "Show variants from FireMonkey units (FMX.*). Off: the foote' +
      'r names them as hidden.",' + #10 + '          "x-issue": "#475"' + #10 + '        },' + #10 +
      '        "nameSuggestions": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "An der Namensposition einer Deklaration mit bekanntem Typ (var-A' +
      'bschnitt, Inline-var, Feld, Parameter) Namen aus dem Typ vorschlagen: TCustomerList ergibt' +
      ' Customers, CustomerList und List, mit F, A bzw. L, wenn mindestens 60 % der Deklarationen' +
      ' dieser Art im Projekt das Präfix tragen oder die Projektdatei .atlas es unter naming vorg' + 'ibt.",' + #10,
    '          "x-description-en": "At the name position of a declaration with known type (var ' +
      'section, inline var, field, parameter) suggest names from the type: TCustomerList gives Cu' +
      'stomers, CustomerList and List, with F, A or L if at least 60 % of the declarations of tha' +
      't kind in the project carry the prefix or the project file .atlas sets it under naming."' + #10 + '        }' +
      #10 + '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "completion",' + #10 +
      '      "x-page": "Vervollständigung",' + #10 + '      "x-control": "Auswahl",' + #10 +
      '      "x-issue": "#31, #188, #229, #450, #452, #466, #467, #469, #473, #475, #480, #482, #' + '489, #490"' +
      #10 + '    },' + #10 + '    "refactoring": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Code, den Atlas erzeugt.",' + #10 +
      '      "x-description-en": "Code that Atlas generates.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10,
    '        "inlineVar": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Inline-Variablen (for var Item in …, var Name := …) erzeugen, we' +
      'nn die Delphi-Version sie kennt (ab 10.3). Aus: Atlas trägt die Variable in den var-Abschn' +
      'itt der Routine ein.",' + #10 +
      '          "x-description-en": "Generate inline variables (for var Item in …, var Name := …' +
      ') if the Delphi version supports them (10.3 and later). Off: Atlas adds the variable to th' +
      'e var section of the routine."' + #10 + '        },' + #10 + '        "changeSignature": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktion „Signatur ändern …“: Parameter hinzufügen, entfernen' +
      ', umsortieren und umbenennen samt Aufrufern, Überschreibungen, Interfaces und gebundenen E' + 'reignissen.",' +
      #10,
    '          "x-description-en": "Code action \"Change signature …\": add, remove, reorder an' +
      'd rename parameters including callers, overrides, interfaces and bound events.",' + #10 +
      '          "x-issue": "#100"' + #10 + '        },' + #10 + '        "newParameter": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["overload", "updateCallers"],' + #10 +
      '          "default": "overload",' + #10 +
      '          "description": "Neue Parameter: overload behält die alte Signatur als Überladung' +
      ', die mit dem angegebenen Wert weiterreicht (Aufrufer bleiben); updateCallers ändert alle ' +
      'Aufrufer. Interface-Methoden und gebundene Handler gehen nur mit updateCallers. Standardwe' +
      'rte erzeugt Atlas nie.",' + #10,
    '          "x-description-en": "New parameters: overload keeps the old signature as an over' +
      'load that passes on the given value (callers stay); updateCallers changes all callers. Int' +
      'erface methods and bound handlers only work with updateCallers. Atlas never generates defa' + 'ult values.",' +
      #10 + '          "x-issue": "#100"' + #10 + '        },' + #10 + '        "virtualOverload": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Die Überladung mit der alten Signatur bei virtuellen Methoden eb' +
      'enfalls virtual machen.",' + #10 +
      '          "x-description-en": "Also make the overload with the old signature virtual for v' +
      'irtual methods.",' + #10 + '          "x-issue": "#100"' + #10 + '        },' + #10 +
      '        "syncSignatures": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Weichen Deklaration und Implementierung voneinander ab, die Akti' +
      'onen „Implementierung an Deklaration angleichen“ und umgekehrt anbieten.",' + #10 +
      '          "x-description-en": "If declaration and implementation differ, offer the actions' +
      ' \"Align implementation with declaration\" and vice versa.",' + #10 + '          "x-issue": "#100"' + #10 +
      '        },' + #10 + '        "forwardDeclaration": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Typen, die im type-Abschnitt vor ihrer Deklaration benutzt werde' +
      'n, melden und „Forward-Deklaration ergänzen“, „type-Blöcke zusammenlegen“ bzw. „Deklaratio' +
      'n nach oben verschieben“ anbieten; überflüssige Forward-Deklarationen melden.",' + #10,
    '          "x-description-en": "Report types used in the type section before their declarat' +
      'ion and offer \"Add forward declaration\", \"Merge type blocks\" or \"Move declaration up\' +
      '"; report superfluous forward declarations.",' + #10 + '          "x-issue": "#685"' + #10 + '        },' + #10 +
      '        "propertyFromAccessors": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "Code-Aktionen „Property X anlegen“ auf einer Zugriffsmethode und' +
      ' „Fehlende Properties anlegen (n)“ auf der Kopfzeile einer Klasse: Zu Methoden wie GetX/Se' +
      'tX (auch indiziert, IsX/HasX für Boolean) ohne Property X legt Atlas die Property an, mit ' +
      'read FX, wenn der Getter nur das Feld liefert. Vorschau vor dem Übernehmen.",' + #10,
    '          "x-description-en": "Code actions \"Create property X\" on an accessor method an' +
      'd \"Create missing properties (n)\" on the header line of a class: for methods such as Get' +
      'X/SetX (also indexed, IsX/HasX for Boolean) without property X Atlas creates the property,' +
      ' with read FX if the getter only returns the field. Preview before applying.",' + #10 +
      '          "x-issue": "#682"' + #10 + '        },' + #10 + '        "propertyFromAccessorsPrefixes": {' + #10 +
      '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": ["Get", "Set", "Is", "Has"],' + #10 +
      '          "description": "Präfixe der Zugriffsmethoden. Is und Has gelten nur für Getter m' +
      'it Ergebnis Boolean, Get nur für Getter, Set nur für Setter, eigene Präfixe für beide.",' + #10,
    '          "x-description-en": "Prefixes of the accessor methods. Is and Has only apply to ' +
      'getters returning Boolean, Get only to getters, Set only to setters, your own prefixes to ' + 'both.",' + #10 +
      '          "x-control": "Liste",' + #10 + '          "x-issue": "#682"' + #10 + '        },' + #10 +
      '        "propertyFromAccessorsReplaceCalls": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["ask", "always", "never"],' + #10 + '          "default": "ask",' + #10 +
      '          "description": "Aufrufe im ganzen Projekt auf die Property umstellen (X.GetCapti' +
      'on → X.Caption, X.SetCaption(V) → X.Caption := V); Übergaben als Methodenzeiger bleiben. a' +
      'sk: beide Aktionen anbieten, mit und ohne Umstellen; always: immer umstellen; never: nie."' + ',' + #10,
    '          "x-description-en": "Switch calls in the whole project to the property (X.GetCap' +
      'tion → X.Caption, X.SetCaption(V) → X.Caption := V); passing as method pointer stays. ask:' +
      ' offer both actions, with and without switching; always: always switch; never: never.",' + #10 +
      '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#682"' + #10 + '        },' + #10 +
      '        "propertyFromAccessorsSection": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["accessor", "public", "published"],' + #10 + '          "default": "accessor",' + #10 +
      '          "description": "Abschnitt der neuen Property: accessor wie die sichtbarste Zugri' +
      'ffsmethode, public bzw. published mindestens dort.",' + #10 +
      '          "x-description-en": "Section of the new property: accessor like the most visible' +
      ' accessor method, public or published at least there.",' + #10 + '          "x-control": "Auswahl",' + #10,
    '          "x-issue": "#682"' + #10 + '        },' + #10 + '        "propertyFromAccessorsHideAccessors": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["off", "private", "protected"],' + #10 +
      '          "default": "off",' + #10 +
      '          "description": "Zugriffsmethoden nach dem Anlegen nach private bzw. protected ve' +
      'rschieben, wenn sie danach außerhalb ihrer Klasse nicht mehr benutzt werden (virtuelle und' +
      ' überschriebene bleiben). off: nie.",' + #10 +
      '          "x-description-en": "After creating, move accessor methods to private or protect' +
      'ed if they are no longer used outside their class (virtual and overridden ones stay). off:' + ' never.",' + #10 +
      '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#682"' + #10 + '        },' + #10 +
      '        "freeFields": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Im Konstruktor (oder einer von ihm aufgerufenen privaten Methode' +
      ') mit TKlasse.Create erzeugte Objektfelder, die die Klasse nirgends freigibt, melden (fiel' +
      'd-not-freed, bis #918 owned-field-not-freed) und die Code-Aktionen „Im Destruktor freigebe' +
      'n“ am Feld und „Alle eigenen Objekte freigeben (n)“ an der Klasse anbieten. Fehlt der Dest' +
      'ruktor, legt Atlas ihn mit override und inherited an. Ausgenommen sind Komponenten mit Own' +
      'er sowie Interface- und Record-Felder; zurückgegebene oder weitergereichte Felder meldet A' +
      'tlas als unklar (owned-field-free-unclear).",' + #10,
    '          "x-description-en": "Report object fields created in the constructor (or a priva' +
      'te method it calls) with TClass.Create that the class never frees (field-not-freed, until ' +
      '#918 owned-field-not-freed) and offer the code actions \"Free in destructor\" on the field' +
      ' and \"Free all owned objects (n)\" on the class. If the destructor is missing, Atlas crea' +
      'tes it with override and inherited. Components with owner as well as interface and record ' +
      'fields are excluded; fields that are returned or passed on are reported as unclear (owned-' +
      'field-free-unclear).",' + #10 + '          "x-issue": "#666"' + #10 + '        },' + #10 +
      '        "freeFieldsStyle": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["free", "freeAndNil"],' + #10 + '          "default": "free",' + #10 +
      '          "description": "Form der Freigabe im Destruktor: free schreibt FFeld.Free, freeA' +
      'ndNil schreibt FreeAndNil(FFeld).",' + #10,
    '          "x-description-en": "Form of freeing in the destructor: free writes FField.Free,' +
      ' freeAndNil writes FreeAndNil(FField).",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#666"' + #10 + '        },' + #10 + '        "suggestConst": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Glühbirne „Als Konstante deklarieren“ auf einer Variablen, die g' +
      'enau einmal zugewiesen und nie geändert wird: var X := … wird const X = …, eine Variable a' +
      'us dem var-Abschnitt mit einer einzigen Zuweisung im Rumpf wird an dieser Stelle eine Inli' +
      'ne-Konstante mit ihrem Typ (const X: T = …) und verschwindet aus dem var-Abschnitt. Nur, w' +
      'enn die Sprachversion Inline-Konstanten kennt (Delphi 10.3 und neuer). Gegenstück zur Unte' +
      'rstreichung neu zugewiesener Variablen im Plugin (highlight.reassigned).",' + #10,
    '          "x-description-en": "Light bulb \"Declare as constant\" on a variable that is as' +
      'signed exactly once and never changed: var X := … becomes const X = …, a variable from the' +
      ' var section with a single assignment in the body becomes an inline constant with its type' +
      ' at that place (const X: T = …) and disappears from the var section. Only if the language ' +
      'version supports inline constants (Delphi 10.3 and later). Counterpart of the underline of' +
      ' reassigned variables in the plugin (highlight.reassigned).",' + #10 + '          "x-issue": "#712"' + #10 +
      '        },' + #10 + '        "invertBoolean": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Code-Aktion „Bedeutung umkehren (X → Y)“ auf einer Boolean-Varia' +
      'blen, einem Feld, einer Konstanten, einer Property, einem Parameter oder einer Boolean-Fun' +
      'ktion des Projekts: neuer Name mit der Gegenbedeutung, jede Stelle so verneint, dass das P' +
      'rogramm gleich bleibt (X := True → Y := False, if not X → if Y, X = False → Y). Funktionen' +
      ' liefern im Rumpf das Gegenteil, Properties nehmen Feld, Getter, Setter und default mit, Ü' +
      'berschreibungen und Interfaces folgen. Vorschau mit Warnungen (var/out-Übergaben, @X, Zeic' +
      'henketten für RTTI), je Datei ein Rückgängig-Schritt.",' + #10,
    '          "x-description-en": "Code action \"Invert meaning (X → Y)\" on a Boolean variabl' +
      'e, field, constant, property, parameter or Boolean function of the project: new name with ' +
      'the opposite meaning, every place negated so that the program stays the same (X := True → ' +
      'Y := False, if not X → if Y, X = False → Y). Functions return the opposite in the body, pr' +
      'operties take field, getter, setter and default along, overrides and interfaces follow. Pr' +
      'eview with warnings (var/out arguments, @X, strings for RTTI), one undo step per file.",' + #10 +
      '          "x-issue": "#715"' + #10 + '        },' + #10 + '        "invertBooleanAntonyms": {' + #10 +
      '          "type": "object",' + #10 + '          "additionalProperties": {' + #10 +
      '            "type": "string"' + #10 + '          },' + #10 + '          "default": {},' + #10,
    '          "description": "Eigene Gegensatzpaare für den Namensvorschlag, z. B. {\"Verbose\' +
      '": \"Silent\"}; gelten in beiden Richtungen und vor den eingebauten (Hidden ↔ Visible, Ena' +
      'bled ↔ Disabled, IsEmpty ↔ HasItems, Valid ↔ Invalid, Locked ↔ Unlocked …).",' + #10 +
      '          "x-description-en": "Your own pairs of opposites for the name suggestion, e.g. {' +
      '\"Verbose\": \"Silent\"}; they apply in both directions and before the built-in ones (Hidd' +
      'en ↔ Visible, Enabled ↔ Disabled, IsEmpty ↔ HasItems, Valid ↔ Invalid, Locked ↔ Unlocked …' + ').",' + #10 +
      '          "x-control": "Tabelle (Name, Gegenteil)",' + #10 + '          "x-issue": "#715"' + #10 + '        },' +
      #10 + '        "invertBooleanFallbackPrefix": {' + #10 + '          "type": "string",' + #10 +
      '          "default": "Not",' + #10,
    '          "description": "Präfix, wenn kein Gegensatzpaar passt: FReady → FNotReady, IsRea' +
      'dy → IsNotReady; ein vorhandenes Präfix fällt weg (IsNotReady → IsReady).",' + #10 +
      '          "x-description-en": "Prefix if no pair of opposites fits: FReady → FNotReady, Is' +
      'Ready → IsNotReady; an existing prefix is dropped (IsNotReady → IsReady).",' + #10 +
      '          "x-control": "Textfeld",' + #10 + '          "x-issue": "#715"' + #10 + '        },' + #10 +
      '        "invertBooleanIncludeDfm": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Published Properties auch in den Formularen (.dfm, .fmx) der Kla' +
      'sse und ihrer Nachfahren umkehren: Name und Wert (Hidden = True → Visible = False); der de' +
      'fault der Property wird mit umgedreht. Aus: Formulare bleiben, die Vorschau warnt.",' + #10,
    '          "x-description-en": "Also invert published properties in the forms (.dfm, .fmx) ' +
      'of the class and its descendants: name and value (Hidden = True → Visible = False); the de' +
      'fault of the property is inverted too. Off: forms stay, the preview warns.",' + #10 +
      '          "x-issue": "#715"' + #10 + '        },' + #10 + '        "ifCase": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktionen „In case umwandeln“ auf einer if-Kette, die densel' +
      'ben ordinalen Ausdruck ohne Seiteneffekte mit Konstanten vergleicht (X = a, X in [a, b..c]' +
      ', (X >= a) and (X <= b), mit or verknüpft), und „In if-Kette umwandeln“ auf einem case. Ko' +
      'mmentare in den Zweigen bleiben, begin … end nur bei mehreren Anweisungen. Der Hinweis auf' +
      ' lange umwandelbare if-Ketten ist die Regel prefer-case.",' + #10,
    '          "x-description-en": "Code actions \"Convert to case\" on an if chain that compar' +
      'es the same ordinal expression without side effects with constants (X = a, X in [a, b..c],' +
      ' (X >= a) and (X <= b), joined with or), and \"Convert to if chain\" on a case. Comments i' +
      'n the branches stay, begin … end only for several statements. The notice on long convertib' +
      'le if chains is the rule prefer-case.",' + #10 + '          "x-issue": "#646"' + #10 + '        },' + #10 +
      '        "conditions": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen zum Umformen von Bedingungen: „Bedingung umkehren“' +
      ' (then und else tauschen, Bedingung lesbar verneint: Vergleiche drehen, De Morgan in gleic' +
      'her Reihenfolge), „Frühen Ausstieg einführen“ (if ohne else am Ende einer Routine bzw. Sch' +
      'leife wird if … then Exit bzw. Continue), „Verschachtelte if zusammenfassen“ (if A then if' +
      ' B → if A and B) und „Doppelte Verneinung entfernen“. Klammern nur, wo der Vorrang sie ver' +
      'langt; Kommentare in den Zweigen bleiben.",' + #10,
    '          "x-description-en": "Code actions to reshape conditions: \"Invert condition\" (s' +
      'wap then and else, condition negated readably: flip comparisons, De Morgan in the same ord' +
      'er), \"Introduce early exit\" (if without else at the end of a routine or loop becomes if ' +
      '… then Exit or Continue), \"Merge nested if\" (if A then if B → if A and B) and \"Remove d' +
      'ouble negation\". Parentheses only where precedence requires them; comments in the branche' + 's stay.",' + #10 +
      '          "x-issue": "#656"' + #10 + '        },' + #10 + '        "conditionalExpression": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen zwischen if-Anweisung und Bedingungsausdruck (Delp' +
      'hi 13: X := if C then A else B): „In bedingten Ausdruck umwandeln“ auf einem if mit else, ' +
      'dessen Zweige an dasselbe Ziel zuweisen, Exit aufrufen oder denselben Aufruf mit genau ein' +
      'em anderen Argument ohne Seiteneffekte machen (bis zu zwei Bedingungen, verträgliche Typen' +
      '), „In if-Anweisung umwandeln“ als Rückweg und „IfThen durch bedingten Ausdruck ersetzen“ ' +
      '(IfThen wertet beide Zweige aus). Muss das Projekt mit Delphi 12 oder älter übersetzen, gi' +
      'bt es nur den Rückweg; vorhandene Bedingungsausdrücke meldet dann die Regel conditional-ex' +
      'pression-version.",' + #10,
    '          "x-description-en": "Code actions between if statement and conditional expressio' +
      'n (Delphi 13: X := if C then A else B): \"Convert to conditional expression\" on an if wit' +
      'h else whose branches assign to the same target, call Exit or make the same call with exac' +
      'tly one different argument without side effects (up to two conditions, compatible types), ' +
      '\"Convert to if statement\" as the way back and \"Replace IfThen with conditional expressi' +
      'on\" (IfThen evaluates both branches). If the project must compile with Delphi 12 or older' +
      ', only the way back is offered; existing conditional expressions are then reported by the ' +
      'rule conditional-expression-version.",' + #10 + '          "x-issue": "#684"' + #10 + '        },' + #10 +
      '        "nestedRoutine": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen zwischen lokaler Routine und Methode: „In private ' +
      'Methode umwandeln“ bzw. „Aus Routine herauslösen“ auf dem Kopf einer lokalen Routine (genu' +
      'tzte Variablen und Parameter der äußeren Routine werden Parameter, var beim Schreiben, con' +
      'st bei Strings, Records und Interfaces; Konstanten wandern mit), „Als lokale Routine einbe' +
      'tten“ bzw. „In lokale Routine umwandeln“ auf einer privaten, nicht virtuellen Methode bzw.' +
      ' einer freien Routine der Implementierung mit genau einem Aufruf, wahlweise ohne durchgere' +
      'ichte Parameter. Jede Aktion zeigt vorher die neue Signatur und die Zahl der geänderten Au' +
      'frufe. Liegt die lokale Routine in einer anderen, gibt es statt der Aktion einen Hinweis."' + ',' + #10,
    '          "x-description-en": "Code actions between local routine and method: \"Convert to' +
      ' private method\" or \"Extract from routine\" on the header of a local routine (used varia' +
      'bles and parameters of the outer routine become parameters, var when written, const for st' +
      'rings, records and interfaces; constants move along), \"Embed as local routine\" or \"Conv' +
      'ert to local routine\" on a private, non-virtual method or a free routine of the implement' +
      'ation with exactly one call, optionally without passed-through parameters. Each action fir' +
      'st shows the new signature and the number of changed calls. If the local routine lies in a' +
      'nother one, there is a notice instead of the action.",' + #10 + '          "x-issue": "#663"' + #10 +
      '        },' + #10 + '        "promoteVariable": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Code-Aktionen zwischen lokaler Variable und Feld: „In Feld umwan' +
      'deln“ auf einer lokalen Variablen oder Inline-Variablen einer Methode (Vorschlag F + Name ' +
      'ohne L-Präfix, änderbar; das Feld steht hinter dem letzten Feld des private-Abschnitts, ei' +
      'ne Initialisierung bleibt als Zuweisung, der Typ einer Inline-Variablen ohne Angabe wird a' +
      'bgeleitet; Warnung, wenn das Objekt in der Methode erzeugt und freigegeben wird) und „In l' +
      'okale Variable umwandeln“ auf einem privaten Feld, das nur eine Methode benutzt und dort a' +
      'uf jedem Weg zuerst schreibt (nicht bei Property, published, Formularfeld). Vorher eine Vo' +
      'rschau, ein Rückgängig-Schritt.",' + #10,
    '          "x-description-en": "Code actions between local variable and field: \"Convert to' +
      ' field\" on a local or inline variable of a method (suggestion F + name without L prefix, ' +
      'editable; the field goes after the last field of the private section, an initialization st' +
      'ays as assignment, the type of an inline variable without type is inferred; warning if the' +
      ' object is created and freed in the method) and \"Convert to local variable\" on a private' +
      ' field used by only one method that writes it first on every path (not for property, publi' +
      'shed, form field). A preview first, one undo step.",' + #10 + '          "x-issue": "#668"' + #10 +
      '        },' + #10 + '        "anonymousMethod": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Code-Aktionen zwischen anonymer Methode und Methode: „In Methode' +
      ' umwandeln“ auf dem Kopf einer anonymen Methode (private Methode der Klasse, in freien Rou' +
      'tinen eine Routine der Unit; Name aus dem Zusammenhang wie HandleClick oder CompareByName,' +
      ' änderbar). Ohne erfasste Variablen steht an der Stelle der Methodenname; erfasste Variabl' +
      'en werden Parameter (var, wenn geschrieben), und eine kurze anonyme Weiterleitung ruft die' +
      ' Methode mit ihnen auf. „Als anonyme Methode einbetten“ auf einer privaten Methode, die ge' +
      'nau einmal als Wert an ein reference to übergeben und nie aufgerufen wird (nicht für Ereig' +
      'nisse der Formulardatei). Vorher eine Vorschau, ein Rückgängig-Schritt.",' + #10,
    '          "x-description-en": "Code actions between anonymous method and method: \"Convert' +
      ' to method\" on the header of an anonymous method (private method of the class, in free ro' +
      'utines a routine of the unit; name from the context such as HandleClick or CompareByName, ' +
      'editable). Without captured variables the method name goes in its place; captured variable' +
      's become parameters (var if written), and a short anonymous forwarder calls the method wit' +
      'h them. \"Embed as anonymous method\" on a private method that is passed exactly once as a' +
      ' value to a reference to and never called (not for events of the form file). A preview fir' +
      'st, one undo step.",' + #10 + '          "x-issue": "#680"' + #10 + '        },' + #10 +
      '        "anonymousMethodDeferredCapture": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["forward", "fields"],' + #10 + '          "default": "forward",' + #10,
    '          "description": "Wenn eine anonyme Methode mit erfassten Variablen später läuft (' +
      'TThread.Queue, TTask.Run, Ereignis): forward lässt eine kurze anonyme Weiterleitung stehen' +
      ', die die Variablen weiter festhält (Verhalten bleibt gleich); fields kopiert die Werte vo' +
      'r der Anweisung in Felder und setzt den Methodennamen ein (spätere Änderungen sieht die Me' +
      'thode nicht; nur in Methoden ohne geschriebene Variablen).",' + #10 +
      '          "x-description-en": "If an anonymous method with captured variables runs later (' +
      'TThread.Queue, TTask.Run, event): forward leaves a short anonymous forwarder that keeps ho' +
      'lding the variables (behavior stays the same); fields copies the values into fields before' +
      ' the statement and inserts the method name (the method does not see later changes; only in' +
      ' methods without written variables).",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#680"' + #10 + '        },' + #10,
    '        "methodKind": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Methoden ohne Self erkennen (kein Feld, keine Property, keine In' +
      'stanzmethode, kein Self, auch nicht implizit; nicht virtual/override, nicht als Ereignis i' +
      'n der Formulardatei, nicht als Methodenzeiger, nicht Teil eines Interfaces) und umwandeln:' +
      ' „In class-Methode umwandeln“ (wahlweise auch die Aufrufe über Instanzen auf TKlasse.X), „' +
      'In freie Routine umwandeln“ (Aufrufe verlieren den Objektbezug, uses in anderen Units) und' +
      ' „In Record-Helper verschieben“ (erster Parameter eines einfachen Typs wird Self, Aufrufe ' +
      'S.X; Warnung, wenn schon ein Helper für den Typ sichtbar ist). Vorher eine Vorschau mit al' +
      'len geänderten Aufrufen, ein Rückgängig-Schritt je Datei. Die Hinweis-Diagnose dazu ist di' +
      'e Regel method-without-self.",' + #10,
    '          "x-description-en": "Detect methods without Self (no field, no property, no inst' +
      'ance method, no Self, not even implicitly; not virtual/override, not an event in the form ' +
      'file, not a method pointer, not part of an interface) and convert them: \"Convert to class' +
      ' method\" (optionally also calls via instances to TClass.X), \"Convert to free routine\" (' +
      'calls lose the object reference, uses in other units) and \"Move to record helper\" (first' +
      ' parameter of a simple type becomes Self, calls S.X; warning if a helper for the type is a' +
      'lready visible). A preview with all changed calls first, one undo step per file. The hint ' +
      'diagnostic for this is the rule method-without-self.",' + #10 + '          "x-issue": "#686"' + #10 +
      '        },' + #10 + '        "methodKindMarker": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Marke „braucht kein Self“ am Kopf solcher Methoden; aus = die Ak' +
      'tionen nur über Strg+.",' + #10 +
      '          "x-description-en": "Label \"Self unused\" at the header of such methods; off = ' +
      'the actions only via Ctrl+.",' + #10 + '          "x-issue": "#686"' + #10 + '        },' + #10 +
      '        "methodKindStatic": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "„In class-Methode umwandeln“ setzt static (ohne verstecktes Self' +
      ' der Klasse); bei Records immer.",' + #10 +
      '          "x-description-en": "\"Convert to class method\" sets static (without the hidden' +
      ' Self of the class); always for records.",' + #10 + '          "x-issue": "#686"' + #10 + '        },' + #10 +
      '        "typeAlias": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen „Typ-Alias einführen“ auf einem Typausdruck (gener' +
      'ischer Typ mit Argumenten, Array, Menge, Methodenreferenz, prozeduraler Typ): schreibt X =' +
      ' Ausdruck in den type-Abschnitt vor der ersten Verwendung (bei Bedarf mit Vorwärtsdeklarat' +
      'ion der eigenen Klasse, im Projekt in den interface-Teil) und ersetzt die Stelle, alle gle' +
      'ichen Ausdrücke der Unit oder des Projekts; gleich heißt gleiche aufgelöste Typen. Offene ' +
      'generische Parameter (TList<T> in TBox<T>) ergeben keinen Alias, die Aktion nennt den Grun' +
      'd. Dazu „Alias auflösen“ auf dem Namen eines Alias X = Y: ersetzt die Verwendungen durch Y' +
      ' (Arrays, Mengen und prozedurale Typen nur dort, wo Delphi einen Typausdruck annimmt) und ' +
      'entfernt den Alias, wenn keine Verwendung bleibt; X = type Y bleibt. Vorher eine Vorschau ' +
      'mit allen Stellen, ein Rückgängig-Schritt je Datei.",' + #10,
    '          "x-description-en": "Code actions \"Introduce type alias\" on a type expression ' +
      '(generic type with arguments, array, set, method reference, procedural type): writes X = e' +
      'xpression into the type section before the first use (with a forward declaration of the ow' +
      'n class if needed, in the project into the interface part) and replaces the place, all equ' +
      'al expressions of the unit or the project; equal means equal resolved types. Open generic ' +
      'parameters (TList<T> in TBox<T>) give no alias, the action names the reason. Plus \"Resolv' +
      'e alias\" on the name of an alias X = Y: replaces the uses with Y (arrays, sets and proced' +
      'ural types only where Delphi accepts a type expression) and removes the alias if no use re' +
      'mains; X = type Y stays. A preview with all places first, one undo step per file.",' + #10 +
      '          "x-issue": "#681"' + #10 + '        },' + #10 + '        "typeAliasScope": {' + #10 +
      '          "type": "string",' + #10,
    '          "enum": ["here", "unit", "project"],' + #10 + '          "default": "unit",' + #10 +
      '          "description": "Reichweite der ersten Aktion „Typ-Alias einführen“: here ersetzt' +
      ' nur die Stelle, unit alle gleichen Ausdrücke der Unit, project auch die Units, die die Un' +
      'it einbinden. Die anderen beiden Reichweiten stehen als eigene Aktionen daneben.",' + #10 +
      '          "x-description-en": "Scope of the first action \"Introduce type alias\": here on' +
      'ly replaces the place, unit all equal expressions of the unit, project also the units usin' +
      'g the unit. The other two scopes are offered as separate actions next to it.",' + #10 +
      '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#681"' + #10 + '        },' + #10 +
      '        "enumTables": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen für Tabellen über Aufzählungen (array[TTyp] of …):' +
      ' „Namenstabelle anlegen“ auf einem Aufzählungstyp ohne feste Werte schreibt hinter den Typ' +
      ' (oder in den implementation-Teil) const CTypNames: array[TTyp] of string mit Texten aus d' +
      'en Elementnamen (gemeinsames Kleinbuchstaben-Präfix weg, CamelCase getrennt: osPaymentDue ' +
      '→ ''Payment due''); der Name ist änderbar. An einer Tabelle, deren Einträge nicht mehr zum T' +
      'yp passen, „Fehlenden Eintrag ergänzen“ bzw. „Überzähligen Eintrag entfernen“ an der richt' +
      'igen Stelle (erkannt an Texten, Bezeichnern und Kommentaren wie {osPaid}; sonst geschätzt ' +
      'und so benannt). „Tabellen von TTyp nachziehen“ ändert alle Tabellen über den Typ im Proje' +
      'kt und ergänzt fehlende Zweige in case-Anweisungen ohne else, mit Vorschau.",' + #10,
    '          "x-description-en": "Code actions for tables over enumerations (array[TType] of ' +
      '…): \"Create name table\" on an enumeration type without fixed values writes const CTypeNa' +
      'mes: array[TType] of string after the type (or into the implementation part) with texts fr' +
      'om the element names (common lowercase prefix removed, CamelCase split: osPaymentDue → ''Pa' +
      'yment due''); the name is editable. On a table whose entries no longer match the type, \"Ad' +
      'd missing entry\" or \"Remove surplus entry\" at the right place (detected by texts, ident' +
      'ifiers and comments such as {osPaid}; otherwise estimated and labelled so). \"Update table' +
      's of TType\" changes all tables over the type in the project and adds missing branches to ' +
      'case statements without else, with preview.",' + #10 + '          "x-issue": "#667"' + #10 + '        },' + #10 +
      '        "enumTablesResourceStrings": {' + #10 + '          "type": "boolean",' + #10,
    '          "default": false,' + #10 +
      '          "description": "„Namenstabelle anlegen“ schreibt je Element einen resourcestring' +
      ' (übersetzbar) und eine Tabelle array[TTyp] of PResStringRec mit @-Verweisen; lesen mit Lo' +
      'adResString(CTypNames[X]).",' + #10 +
      '          "x-description-en": "\"Create name table\" writes one resourcestring per element' +
      ' (translatable) and a table array[TType] of PResStringRec with @ references; read with Loa' +
      'dResString(CTypeNames[X]).",' + #10 + '          "x-issue": "#667"' + #10 + '        },' + #10 +
      '        "overloads": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen auf dem Kopf einer Routine (Strg+.): „Überladung a' +
      'nlegen (Kopie)“ kopiert Deklaration und Rumpf direkt hinter das Original, beide mit overlo' +
      'ad; danach führt der Platzhalter-Modus erst durch die Parameterliste der Kopie (in Deklara' +
      'tion und Implementierung gleich), dann durch den Rumpf. „Überladung anlegen (als Weiterlei' +
      'tung)“ legt eine Überladung ohne den letzten Parameter an, die die bestehende aufruft und ' +
      'für ihn den Standardwert seines Typs mitgibt (0, '''', False, nil, erstes Element einer Aufz' +
      'ählung, sonst Default(Typ)), als Platzhalter. virtual, override, dynamic und message gehen' +
      ' nicht auf die neue Überladung über; ist das Original ein override, weist Atlas darauf hin' +
      '. Der ///-Kommentar wird mitkopiert. Überladungen über Standardparameter zusammenführen gi' +
      'bt es bewusst nicht.",' + #10,
    '          "x-description-en": "Code actions on the header of a routine (Ctrl+.): \"Create ' +
      'overload (copy)\" copies declaration and body directly after the original, both with overl' +
      'oad; then placeholder mode first leads through the parameter list of the copy (same in dec' +
      'laration and implementation), then through the body. \"Create overload (as forwarder)\" cr' +
      'eates an overload without the last parameter that calls the existing one and passes the de' +
      'fault value of its type for it (0, '''', False, nil, first element of an enumeration, otherw' +
      'ise Default(Type)), as placeholder. virtual, override, dynamic and message are not carried' +
      ' over to the new overload; if the original is an override, Atlas points this out. The /// ' +
      'comment is copied too. Merging overloads into default parameters is deliberately not offer' + 'ed.",' + #10 +
      '          "x-issue": "#674"' + #10 + '        },' + #10 + '        "varBlock": {' + #10,
    '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktionen rund um lokale Variablen (Strg+.): „In Inline-Vari' +
      'able umwandeln“ auf einer Variablen des var-Abschnitts (an die erste Zuweisung als var X :' +
      '= …, sonst als var X: T; vor die erste Verwendung, nur ab Delphi 10.3 und nur, wenn alle V' +
      'erwendungen im selben oder einem inneren Block liegen, nicht in anonymen Methoden), „In va' +
      'r-Block verschieben“ auf einer Inline-Variablen (Typ bei var X := … aus dem Ausdruck) und ' +
      '„var-Block aufräumen“ im var-Abschnitt (ungenutzte Variablen entfernen, sortieren, gleiche' +
      ' Typen zusammenfassen). Kommentare an Variablen wandern mit.",' + #10,
    '          "x-description-en": "Code actions around local variables (Ctrl+.): \"Convert to ' +
      'inline variable\" on a variable of the var section (at the first assignment as var X := …,' +
      ' otherwise as var X: T; before the first use, only from Delphi 10.3 and only if all uses l' +
      'ie in the same or an inner block, not in anonymous methods), \"Move to var block\" on an i' +
      'nline variable (type for var X := … from the expression) and \"Clean up var block\" in the' +
      ' var section (remove unused variables, sort, merge equal types). Comments on variables mov' + 'e along.",' +
      #10 + '          "x-issue": "#644"' + #10 + '        },' + #10 + '        "varBlockMerge": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "„var-Block aufräumen“ fasst aufeinanderfolgende Variablen gleich' +
      'en Typs zusammen (I, J: Integer). Aus: jede Variable in eine eigene Zeile. Einträge mit Ko' +
      'mmentar und Typen ohne Namen (array of …) bleiben, wie sie sind.",' + #10 +
      '          "x-description-en": "\"Clean up var block\" merges consecutive variables of the ' +
      'same type (I, J: Integer). Off: each variable on its own line. Entries with comments and t' +
      'ypes without names (array of …) stay as they are.",' + #10 + '          "x-issue": "#644"' + #10 + '        },' +
      #10 + '        "varBlockSort": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["usage", "alpha", "none"],' + #10 + '          "default": "usage",' + #10 +
      '          "description": "Reihenfolge nach „var-Block aufräumen“: usage nach der ersten Ve' +
      'rwendung in der Routine, alpha alphabetisch, none wie bisher.",' + #10,
    '          "x-description-en": "Order after \"Clean up var block\": usage by first use in t' +
      'he routine, alpha alphabetical, none as before.",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#644"' + #10 + '        },' + #10 + '        "extractInterface": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktion „Interface aus TFoo herauslösen …“ auf der Kopfzeile' +
      ' einer Klasse: Ein Dialog zeigt die public- und published-Methoden und -Properties zum Ank' +
      'reuzen (vorab alle public-Methoden), den Namen (I + Klassenname ohne T) und das Ziel (dies' +
      'elbe Unit, eine Unit des Projekts oder eine neue). Das Interface bekommt eine neue GUID, d' +
      'ie Signaturen samt Doku-Kommentaren und die Properties; liest eine Property ein Feld, legt' +
      ' Atlas Get- und Set-Methoden an. Die Klasse erhält das Interface in ihrer Vorfahrenliste (' +
      'statt TObject TInterfacedObject). Vorschau vor dem Übernehmen.",' + #10,
    '          "x-description-en": "Code action \"Extract interface from TFoo …\" on the header' +
      ' line of a class: a dialog shows the public and published methods and properties to tick (' +
      'all public methods preselected), the name (I + class name without T) and the target (same ' +
      'unit, a unit of the project or a new one). The interface gets a new GUID, the signatures w' +
      'ith doc comments and the properties; if a property reads a field, Atlas creates Get and Se' +
      't methods. The class gets the interface in its ancestor list (TInterfacedObject instead of' +
      ' TObject). Preview before applying.",' + #10 + '          "x-issue": "#664"' + #10 + '        },' + #10 +
      '        "extractSuperclass": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10,
    '          "description": "Code-Aktion „Basisklasse herauslösen …“ auf der Kopfzeile einer ' +
      'Klasse: Ein Dialog zeigt Felder, Methoden und Properties zum Ankreuzen, je Methode verschi' +
      'eben oder abstrakt deklarieren, den Namen und das Ziel (dieselbe Unit oberhalb der Klasse ' +
      'oder eine neue Unit). Die neue Klasse erbt vom bisherigen Vorfahren, die Klasse von ihr; A' +
      'nweisungen im Konstruktor bzw. Destruktor für verschobene Felder wandern mit, private Mitg' +
      'lieder, die die Klasse weiter benutzt, werden gehoben. Vorschau vor dem Übernehmen.",' + #10,
    '          "x-description-en": "Code action \"Extract base class …\" on the header line of ' +
      'a class: a dialog shows fields, methods and properties to tick, for each method move or de' +
      'clare abstract, the name and the target (same unit above the class or a new unit). The new' +
      ' class inherits from the previous ancestor, the class from it; statements in constructor o' +
      'r destructor for moved fields move along, private members the class still uses are raised.' +
      ' Preview before applying.",' + #10 + '          "x-issue": "#713"' + #10 + '        },' + #10 +
      '        "extractSuperclassTarget": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["sameUnit", "newUnit"],' + #10 + '          "default": "sameUnit",' + #10 +
      '          "description": "Vorgabe für das Ziel im Dialog: sameUnit (oberhalb der Klasse) o' +
      'der newUnit (neue Unit mit dem Klassennamen ohne T).",' + #10,
    '          "x-description-en": "Default for the target in the dialog: sameUnit (above the c' +
      'lass) or newUnit (new unit with the class name without T).",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#713"' + #10 + '        },' + #10 + '        "extractSuperclassNameSuffix": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "Base",' + #10 +
      '          "description": "Endung für den vorgeschlagenen Namen (TPdfExport → TExportBase);' +
      ' Custom wird zum Präfix (TCustomExport).",' + #10 +
      '          "x-description-en": "Suffix for the suggested name (TPdfExport → TExportBase); C' +
      'ustom becomes a prefix (TCustomExport).",' + #10 + '          "x-issue": "#713"' + #10 + '        },' + #10 +
      '        "extractSuperclassMethodMode": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["move", "abstract"],' + #10 + '          "default": "move",' + #10,
    '          "description": "Vorgabe je Methode: move (Rumpf wandert mit) oder abstract (oben' +
      ' virtual; abstract;, unten override).",' + #10 +
      '          "x-description-en": "Default per method: move (body moves along) or abstract (vi' +
      'rtual; abstract; above, override below).",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#713"' + #10 + '        },' + #10 + '        "extractSuperclassRaiseVisibility": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["protected", "strictProtected"],' + #10 +
      '          "default": "protected",' + #10 +
      '          "description": "Sichtbarkeit für private Mitglieder, die in die Basisklasse wand' +
      'ern und unten weiter benutzt werden.",' + #10 +
      '          "x-description-en": "Visibility for private members that move to the base class ' +
      'and are still used below.",' + #10 + '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#713"' +
      #10 + '        },' + #10,
    '        "moveMember": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktionen „„Run“ in Vorfahr verschieben …“ und „„Run“ in Nac' +
      'hfahren verschieben …“ auf einem Feld, einer Methode oder einer Property: Ein Dialog zeigt' +
      ' die Mitglieder zum Ankreuzen (benutzte zum Mitnehmen), das Ziel (Vorfahren bzw. direkte N' +
      'achfahren im Projekt), nach oben je Methode verschieben oder abstrakt deklarieren und ob g' +
      'leichnamige Methoden anderer Nachfahren override werden, nach unten ob die Methoden im Vor' +
      'fahren abstrakt bleiben. Benutzt fremder Code das Mitglied über den Vorfahr-Typ, verbietet' +
      ' Atlas das Verschieben nach unten. Private Mitglieder werden bei Bedarf protected, fehlend' +
      'e uses ergänzt. Vorschau vor dem Übernehmen.",' + #10,
    '          "x-description-en": "Code actions \"Move \"Run\" to ancestor …\" and \"Move \"Ru' +
      'n\" to descendants …\" on a field, method or property: a dialog shows the members to tick ' +
      '(used ones to take along), the target (ancestors or direct descendants in the project), up' +
      'wards per method move or declare abstract and whether methods of the same name in other de' +
      'scendants become override, downwards whether the methods stay abstract in the ancestor. If' +
      ' foreign code uses the member via the ancestor type, Atlas forbids moving down. Private me' +
      'mbers become protected if needed, missing uses are added. Preview before applying.",' + #10 +
      '          "x-issue": "#675"' + #10 + '        },' + #10 + '        "inlineAccessor": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktion „Zugriffsmethode GetName durch Feld FName ersetzen“ ' +
      'an einer Property und an einer trivialen Zugriffsmethode: Liefert ein Getter nur ein Feld ' +
      '(Result := FName;) oder setzt ein Setter nur ein Feld (FName := Value;), zeigt die Propert' +
      'y danach direkt auf das Feld, Deklaration und Rumpf fallen weg. Nur für Methoden, die nich' +
      't virtuell sind, kein Interface implementieren, keinen index haben und nirgends direkt auf' +
      'gerufen werden (Referenzsuche). Vorschau vor dem Übernehmen.",' + #10,
    '          "x-description-en": "Code action \"Replace accessor GetName with field FName\" o' +
      'n a property and on a trivial accessor method: if a getter only returns a field (Result :=' +
      ' FName;) or a setter only sets a field (FName := Value;), the property then points directl' +
      'y to the field, declaration and body are removed. Only for methods that are not virtual, i' +
      'mplement no interface, have no index and are never called directly (reference search). Pre' +
      'view before applying.",' + #10 + '          "x-issue": "#717"' + #10 + '        },' + #10 +
      '        "inlineAccessorEqualityCheck": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Setter mit Gleichheitsprüfung (if FName <> Value then FName := V' +
      'alue;) gelten als trivial. Setter mit Benachrichtigung (Changed, Invalidate) nie.",' + #10,
    '          "x-description-en": "Setters with equality check (if FName <> Value then FName :' +
      '= Value;) count as trivial. Setters with notification (Changed, Invalidate) never.",' + #10 +
      '          "x-issue": "#717"' + #10 + '        },' + #10 + '        "inlineAccessorBulk": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Zusätzlich die Sammelaktionen „Alle trivialen Zugriffsmethoden d' +
      'er Unit ersetzen (n)“ und „… des Projekts ersetzen“ mit Vorschau; Methoden mit Aufrufen bl' +
      'eiben, die Vorschau nennt sie.",' + #10 +
      '          "x-description-en": "Also the bulk actions \"Replace all trivial accessors of th' +
      'e unit (n)\" and \"… of the project\" with preview; methods with calls stay, the preview n' + 'ames them.",' +
      #10 + '          "x-issue": "#717"' + #10 + '        },' + #10 + '        "inlineAccessorDiagnostic": {' + #10 +
      '          "type": "boolean",' + #10,
    '          "default": false,' + #10 +
      '          "description": "Hinweis-Diagnose trivial-accessor an trivialen Zugriffsmethoden ' +
      '(Schweregrad über die Regel einstellbar); die Glühbirne an der Meldung ersetzt sie.",' + #10 +
      '          "x-description-en": "Hint diagnostic trivial-accessor on trivial accessor method' +
      's (severity adjustable via the rule); the light bulb on the message replaces them.",' + #10 +
      '          "x-issue": "#717"' + #10 + '        },' + #10 + '        "safeDelete": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "„Sicher löschen“ (Alt+Entf im Editor, Code-Aktion „Methode „Run“' +
      ' sicher löschen …“) für Methoden (Überladungen einzeln), Felder, Properties, Typen, Konsta' +
      'nten, globale Variablen, Routinen, lokale Routinen und auf der Zeile „unit X;“ für die gan' +
      'ze Unit. Atlas sucht vorher Verwendungen im Projekt, in Formularen (Ereignisse, Komponente' +
      'n), in uses-Listen, Überschreibungen und Interface-Implementierungen. Ohne Verwendungen wi' +
      'rd sofort gelöscht, sonst zeigt eine Liste die Stellen (Abbrechen, Anzeigen, Trotzdem lösc' +
      'hen). Doku-Kommentar und Attribute gehen mit, leere Abschnitte fallen weg.",' + #10,
    '          "x-description-en": "\"Safe delete\" (Alt+Del in the editor, code action \"Safel' +
      'y delete method \"Run\" …\") for methods (overloads individually), fields, properties, typ' +
      'es, constants, global variables, routines, local routines and, on the line \"unit X;\", fo' +
      'r the whole unit. Atlas first searches for uses in the project, in forms (events, componen' +
      'ts), in uses lists, overrides and interface implementations. Without uses it deletes at on' +
      'ce, otherwise a list shows the places (Cancel, Show, Delete anyway). Doc comment and attri' +
      'butes go along, empty sections are removed.",' + #10 + '          "x-issue": "#716"' + #10 + '        },' + #10 +
      '        "safeDeletePreviewWhenUnused": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10 +
      '          "description": "Auch ohne Verwendungen erst die Vorschau zeigen, statt sofort zu' + ' löschen.",' +
      #10,
    '          "x-description-en": "Show the preview first even without uses instead of deletin' + 'g at once.",' +
      #10 + '          "x-issue": "#716"' + #10 + '        },' + #10 + '        "safeDeleteCascade": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["ask", "always", "never"],' + #10 +
      '          "default": "ask",' + #10 +
      '          "description": "Was durch das Löschen unbenutzt wird (private Felder und Methode' +
      'n, Getter und Setter einer Property, uses-Einträge): ask (nachfragen), always (mitlöschen)' +
      ' oder never (stehen lassen).",' + #10 +
      '          "x-description-en": "What becomes unused by deleting (private fields and methods' +
      ', getter and setter of a property, uses entries): ask, always (delete too) or never (leave' + ' in place).",' +
      #10 + '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#716"' + #10 + '        },' + #10 +
      '        "safeDeleteIncludeOverrides": {' + #10 + '          "type": "string",' + #10,
    '          "enum": ["ask", "always", "never"],' + #10 + '          "default": "ask",' + #10 +
      '          "description": "Überschreibungen einer virtuellen Methode in Nachfahren: ask (na' +
      'chfragen), always (mitlöschen) oder never (zählen als Verwendung).",' + #10 +
      '          "x-description-en": "Overrides of a virtual method in descendants: ask, always (' +
      'delete too) or never (count as use).",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#716"' + #10 + '        },' + #10 + '        "tryFinally": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktion „try/finally ergänzen“ nach X := TFoo.Create(…) für ' +
      'lokale Variablen (bei Result: try/except, das nur im Fehlerfall freigibt). Der try-Block s' +
      'chließt die folgenden Anweisungen bis zum Blockende bzw. bis zum Ende der Auswahl ein.",' + #10,
    '          "x-description-en": "Code action \"Add try/finally\" after X := TFoo.Create(…) f' +
      'or local variables (for Result: try/except that only frees on failure). The try block encl' +
      'oses the following statements up to the end of the block or the end of the selection.",' + #10 +
      '          "x-issue": "#42"' + #10 + '        },' + #10 + '        "classActions": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktionen in einer Klassendeklaration: „Getter, Setter und F' +
      'eld erzeugen“ auf einer Property ohne read/write, „Methoden von IFoo implementieren“ und „' +
      'Name überschreiben“ für virtuelle Methoden der Vorfahren.",' + #10 +
      '          "x-description-en": "Code actions in a class declaration: \"Generate getter, set' +
      'ter and field\" on a property without read/write, \"Implement methods of IFoo\" and \"Over' +
      'ride Name\" for virtual methods of the ancestors.",' + #10,
    '          "x-issue": "#42"' + #10 + '        },' + #10 + '        "explicitType": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktion „Typ ausschreiben“ auf dem Namen von var X := …, con' +
      'st X = … und for var X in … ohne Typangabe: fügt den abgeleiteten Typ ein (var Count: Inte' +
      'ger := Lines.Count) und trägt seine Unit bei Bedarf ins uses ein.",' + #10 +
      '          "x-description-en": "Code action \"Write out type\" on the name of var X := …, c' +
      'onst X = … and for var X in … without type: inserts the inferred type (var Count: Integer ' +
      ':= Lines.Count) and adds its unit to uses if needed.",' + #10 + '          "x-issue": "#453"' + #10 +
      '        },' + #10 + '        "compilerFixes": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Schnellkorrekturen an Meldungen des letzten Compilerlaufs: H2443' +
      ' trägt die Unit aus der Meldung ins uses ein, E2003 bietet die Units an, die den Bezeichne' +
      'r deklarieren (RTL und VCL zuerst), H2077 entfernt eine wirkungslose Zuweisung (bei einem ' +
      'Aufruf bleibt nur der Aufruf), W1035 fügt Result := Default(<Typ>); am Anfang der Funktion' +
      ' ein, W1057/W1058 setzen eine explizite Umwandlung (string(…), AnsiString(…)). Gibt es die' +
      'selbe Meldung mehrmals in der Datei, dazu „Alle … in der Datei beheben“. Jede Korrektur is' +
      't ein Rückgängig-Schritt.",' + #10,
    '          "x-description-en": "Quick fixes on messages of the last compiler run: H2443 add' +
      's the unit from the message to uses, E2003 offers the units declaring the identifier (RTL ' +
      'and VCL first), H2077 removes an ineffective assignment (for a call only the call stays), ' +
      'W1035 inserts Result := Default(<Type>); at the start of the function, W1057/W1058 add an ' +
      'explicit cast (string(…), AnsiString(…)). If the same message occurs several times in the ' +
      'file, also \"Fix all … in the file\". Each fix is one undo step.",' + #10 + '          "x-issue": "#549"' + #10 +
      '        },' + #10 + '        "missingUnit": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Code-Aktionen auf „Unit nicht gefunden“ (F2613, F1026) des letzt' +
      'en Compilerlaufs: Atlas sucht die Unit im Projektordner und seinen Unterordnern, in den an' +
      'deren Projekten der Gruppe, in den Suchpfaden der anderen Konfigurationen und Plattformen,' +
      ' in den Bibliothekspfaden anderer Plattformen und im Index. Für einen Fund: „Ordner in den' +
      ' Suchpfad dieser Konfiguration aufnehmen“, „… aller Konfigurationen“ (relativ zur .dproj, ' +
      'über die Projektoptionen der IDE) und für eine Quelle „Unit ins Projekt aufnehmen“. Gibt e' +
      's die Unit nur für andere Plattformen, sagt die Aktion das („Winapi.Windows gibt es für Li' +
      'nux64 nicht“); ohne Fund nennt sie die durchsuchten Orte.",' + #10,
    '          "x-description-en": "Code actions on \"Unit not found\" (F2613, F1026) of the la' +
      'st compiler run: Atlas searches the unit in the project folder and its subfolders, in the ' +
      'other projects of the group, in the search paths of the other configurations and platforms' +
      ', in the library paths of other platforms and in the index. For a hit: \"Add folder to the' +
      ' search path of this configuration\", \"… of all configurations\" (relative to the .dproj,' +
      ' via the project options of the IDE) and, for a source, \"Add unit to project\". If the un' +
      'it only exists for other platforms, the action says so (\"Winapi.Windows does not exist fo' +
      'r Linux64\"); without a hit it names the searched places.",' + #10 + '          "x-issue": "#550"' + #10 +
      '        },' + #10 + '        "disableWarning": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Code-Aktionen auf einer Warnung oder einem Hinweis des letzten C' +
      'ompilerlaufs: „W1000 hier abschalten“ setzt {$WARN SYMBOL_DEPRECATED OFF} vor und {$WARN S' +
      'YMBOL_DEPRECATED ON} hinter die Zeile, dazu Varianten um die Routine, für die ganze Unit u' +
      'nd (nach Rückfrage) für das ganze Projekt in den Projektoptionen. Hinweise bekommen {$HINT' +
      'S OFF}/{$HINTS ON}, Warnungen ohne eigenen Bezeichner {$WARNINGS OFF}/{$WARNINGS ON} (betr' +
      'ifft alle Warnungen). Ablaufmeldungen wie H2164 oder W1035 gibt es nur um die ganze Routin' +
      'e. Ein Rückgängig-Schritt.",' + #10,
    '          "x-description-en": "Code actions on a warning or hint of the last compiler run:' +
      ' \"Disable W1000 here\" puts {$WARN SYMBOL_DEPRECATED OFF} before and {$WARN SYMBOL_DEPREC' +
      'ATED ON} after the line, plus variants around the routine, for the whole unit and (after a' +
      'sking) for the whole project in the project options. Hints get {$HINTS OFF}/{$HINTS ON}, w' +
      'arnings without their own identifier {$WARNINGS OFF}/{$WARNINGS ON} (affects all warnings)' +
      '. Flow messages such as H2164 or W1035 only around the whole routine. One undo step.",' + #10 +
      '          "x-issue": "#531"' + #10 + '        },' + #10 + '        "disableWarningReason": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Beim Abschalten einer Warnung nach einer Begründung fragen; sie ' +
      'kommt als Kommentar hinter den Schalter ({$WARN SYMBOL_DEPRECATED OFF} // Altlast bis zur ' +
      'Umstellung). Leer erlaubt. Aus: ohne Rückfrage, ohne Kommentar.",' + #10 +
      '          "x-description-en": "Ask for a reason when disabling a warning; it goes as a com' +
      'ment after the switch ({$WARN SYMBOL_DEPRECATED OFF} // legacy until migration). Empty all' +
      'owed. Off: no question, no comment.",' + #10 + '          "x-issue": "#531"' + #10 + '        },' + #10 +
      '        "extract": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktionen „Methode extrahieren“ (markierte Anweisungen werde' +
      'n eine neue Methode bzw. Routine; Parameter nach Datenfluss: nur gelesen const, geschriebe' +
      'n und danach gelesen var bzw. out, nur innen lokale Variable), „Variable einführen“ (auch ' +
      'für alle textgleichen Vorkommen im Block) und „Konstante extrahieren“ (in der Routine oder' +
      ' in der Unit). Inline-Variable oder var-Abschnitt nach inlineVar.",' + #10 +
      '          "x-description-en": "Code actions \"Extract method\" (selected statements become' +
      ' a new method or routine; parameters by data flow: only read const, written and then read ' +
      'var or out, only inside local variable), \"Introduce variable\" (also for all textually eq' +
      'ual occurrences in the block) and \"Extract constant\" (in the routine or in the unit). In' +
      'line variable or var section according to inlineVar.",' + #10 + '          "x-issue": "#50"' + #10 +
      '        },' + #10,
    '        "completeCase": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Code-Aktion „case vervollständigen“: ergänzt bei case über einem' +
      ' Aufzählungstyp genau die fehlenden Werte als leere Zweige in Deklarationsreihenfolge. Mit' +
      ' else heißt sie „Fehlende Werte vor else ergänzen“ und ist nicht die bevorzugte Aktion.",' + #10 +
      '          "x-description-en": "Code action \"Complete case\": for case over an enumeration' +
      ' type adds exactly the missing values as empty branches in declaration order. With else it' +
      ' is called \"Add missing values before else\" and is not the preferred action.",' + #10 +
      '          "x-issue": "#50"' + #10 + '        },' + #10 + '        "resolveWith": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Code-Aktion „with auflösen“: Bezeichner im with-Rumpf, die zu ei' +
      'nem Mitglied eines with-Ausdrucks gehören, bekommen diesen Ausdruck vorangestellt (innerst' +
      'es Element zuerst); aufwendige Ausdrücke vom Klassentyp kommen vorher in eine lokale Varia' +
      'ble. Ist ein Bezeichner nicht eindeutig auflösbar, gibt es die Aktion nicht.",' + #10 +
      '          "x-description-en": "Code action \"Resolve with\": identifiers in the with body ' +
      'that belong to a member of a with expression get that expression prepended (innermost elem' +
      'ent first); costly expressions of class type first go into a local variable. If an identif' +
      'ier cannot be resolved unambiguously, the action is not offered.",' + #10 + '          "x-issue": "#50"' + #10 +
      '        },' + #10 + '        "inline": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10,
    '          "description": "Code-Aktionen „Variable einbetten“ und „Methode einbetten“ auf e' +
      'iner lokalen Variablen bzw. einem Aufruf: Die Variable verschwindet, ihre Stellen bekommen' +
      ' den Ausdruck; der Aufruf wird durch den Rumpf ersetzt (lokale Namen eindeutig umbenannt, ' +
      'Argumente eingesetzt oder in Hilfsvariablen, Mitglieder mit dem Empfänger, das Ergebnis di' +
      'rekt oder in einer Variablen wie AddResult). Angeboten nur, wenn Datenfluss und Namensaufl' +
      'ösung zeigen, dass sich die Bedeutung nicht ändert. Hilfsvariablen als Inline-Variable ode' +
      'r im var-Abschnitt nach refactoring.inlineVar.",' + #10,
    '          "x-description-en": "Code actions \"Inline variable\" and \"Inline method\" on a' +
      ' local variable or a call: the variable disappears, its places get the expression; the cal' +
      'l is replaced by the body (local names renamed uniquely, arguments substituted or put into' +
      ' helper variables, members with the receiver, the result directly or in a variable such as' +
      ' AddResult). Only offered if data flow and name resolution show that the meaning does not ' +
      'change. Helper variables as inline variable or in the var section according to refactoring' + '.inlineVar.",' +
      #10 + '          "x-experimental": true,' + #10 + '          "x-issue": "#103"' + #10 + '        },' + #10 +
      '        "moveClass": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' + #10,
    '          "description": "Code-Aktion „Klasse in eigene Unit verschieben …“ auf der ersten' +
      ' Zeile einer Klassen- oder Record-Deklaration: Die Deklaration samt Attributen, Kommentar ' +
      'und Methodenrümpfen kommt in eine neue Unit neben der alten (Name aus dem Klassennamen ohn' +
      'e T, im Dialog änderbar). Die neue Unit steht danach in .dpr bzw. .dpk und .dproj; ihre us' +
      'es entstehen aus den benötigten Namen, und alle Units, die die Klasse verwenden, binden si' +
      'e ein. Nicht angeboten bei Zugriff auf Namen aus dem implementation-Teil der alten Unit, K' +
      'reisverweis, Formularklassen und bedingter Übersetzung.",' + #10,
    '          "x-description-en": "Code action \"Move class to its own unit …\" on the first l' +
      'ine of a class or record declaration: the declaration with attributes, comment and method ' +
      'bodies goes into a new unit next to the old one (name from the class name without T, edita' +
      'ble in the dialog). The new unit is then listed in .dpr or .dpk and .dproj; its uses are b' +
      'uilt from the names needed, and all units using the class include it. Not offered for acce' +
      'ss to names from the implementation part of the old unit, circular reference, form classes' +
      ' and conditional compilation.",' + #10 + '          "x-experimental": true,' + #10 +
      '          "x-issue": "#103"' + #10 + '        },' + #10 + '        "unitRenameFollowUp": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["ask", "off"],' + #10 + '          "default": "off",' +
      #10,
    '          "description": "Nach dem Umbenennen einer Unit in der Projektverwaltung (die IDE' +
      ' passt nur .dpr und .dproj an) meldet Atlas in der Benachrichtigungszentrale, wie viele Un' +
      'its den alten Namen noch verwenden, und bietet an, uses-Einträge und qualifizierte Bezeich' +
      'ner (Alt.TKlasse) im Projekt oder in der Projektgruppe nachzuziehen, mit Vorschau und rück' +
      'gängig machbar. ask: anbieten; off: aus.",' + #10 +
      '          "x-description-en": "After renaming a unit in the project manager (the IDE only ' +
      'updates .dpr and .dproj) Atlas reports in the notification center how many units still use' +
      ' the old name and offers to update uses entries and qualified identifiers (Old.TClass) in ' +
      'the project or in the project group, with preview and undoable. ask: offer; off: off.",' + #10 +
      '          "x-experimental": true,' + #10 + '          "x-offValue": "off",' + #10 +
      '          "x-issue": "#512"' + #10 + '        },' + #10,
    '        "createMethod": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Methode aus Aufruf anlegen: Nach \"(\" hinter einem unbekannten ' +
      'Namen und mit Strg+Leer auf einem solchen Aufruf bietet Atlas an, die Methode (in einer Me' +
      'thode der Klasse) bzw. freie Routine anzulegen; bei Obj.Name(…) in der Klasse von Obj, sof' +
      'ern sie zum Projekt gehört (auch als Code-Aktion). Parametertypen aus den Argumenten, Rück' +
      'gabetyp aus der Zuweisung bzw. dem erwarteten Typ; ohne Zuweisung eine Prozedur.",' + #10,
    '          "x-description-en": "Create method from call: after \"(\" behind an unknown name' +
      ' and with Ctrl+Space on such a call Atlas offers to create the method (inside a method of ' +
      'the class) or free routine; for Obj.Name(…) in the class of Obj, if it belongs to the proj' +
      'ect (also as a code action). Parameter types from the arguments, return type from the assi' +
      'gnment or the expected type; without assignment a procedure.",' + #10 + '          "x-issue": "#472"' + #10 +
      '        },' + #10 + '        "createMethodSection": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["private", "protected", "public"],' + #10 + '          "default": "private",' + #10 +
      '          "description": "Abschnitt der neuen Methode, wenn die Klasse in derselben Unit s' +
      'teht. In einer anderen Unit kommt sie immer nach public, damit der Aufruf übersetzt.",' + #10,
    '          "x-description-en": "Section of the new method if the class is in the same unit.' +
      ' In another unit it always goes to public so that the call compiles.",' + #10 + '          "x-issue": "#472"' +
      #10 + '        },' + #10 + '        "createMethodCaret": {' + #10 + '          "type": "string",' + #10 +
      '          "enum": ["call", "body"],' + #10 + '          "default": "call",' + #10 +
      '          "description": "Wo der Cursor nach „Methode anlegen“ in der Vervollständigung st' +
      'eht: an der Aufrufstelle (call) oder in der leeren Zeile des neuen Rumpfs (body).",' + #10 +
      '          "x-description-en": "Where the cursor is after \"Create method\" in completion: ' +
      'at the call site (call) or on the empty line of the new body (body).",' + #10 + '          "x-issue": "#472"' +
      #10 + '        },' + #10 + '        "constParameters": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Erzeugte Parameter für Strings, Records und Interfaces mit const' +
      ' (Methode aus Aufruf anlegen).",' + #10 +
      '          "x-description-en": "Generated parameters for strings, records and interfaces wi' +
      'th const (create method from call).",' + #10 + '          "x-issue": "#472"' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Vervollständigung",' + #10 +
      '      "x-control": "Kontrollkästchen",' + #10 +
      '      "x-issue": "#42, #50, #100, #188, #453, #472, #646, #656, #666, #682, #684, #685, #7' + '15"' + #10 +
      '    },' + #10 + '    "usesCommand": {' + #10 + '      "type": "boolean",' + #10 + '      "default": true,' +
      #10 + '      "description": "Eine Zeile \"/uses Unit1, Unit2\" wird nach Enter gelöscht und die U' +
      'nits kommen ins passende uses.",' + #10,
    '      "x-description-en": "A line \"/uses Unit1, Unit2\" is deleted after Enter and the un' +
      'its go into the matching uses.",' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "codeActions",' +
      #10 + '      "x-page": "Eingabehilfen",' + #10 + '      "x-control": "Kontrollkästchen",' + #10 +
      '      "x-issue": "#254"' + #10 + '    },' + #10 + '    "completeBlocks": {' + #10 + '      "type": "object",' +
      #10 + '      "description": "Eingabehilfen, die beim Tippen Code ergänzen.",' + #10 +
      '      "x-description-en": "Typing aids that add code while typing.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "docComment": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Gerüst des Dokumentationskommentars nach dem dritten / über eine' +
      'r Deklaration erzeugen (summary, typeparam, param, returns), dazu die Code-Aktionen „Dokum' +
      'entationskommentar erzeugen“ und „Dokumentation an die Signatur anpassen“. Überzählige par' +
      'am werden dabei als <!-- entfernt: Name --> markiert, nicht gelöscht. false: /// bleibt, w' + 'ie getippt.",' +
      #10 + '          "x-description-en": "Generate the skeleton of the documentation comment after th' +
      'e third / above a declaration (summary, typeparam, param, returns), plus the code actions ' +
      '\"Generate documentation comment\" and \"Align documentation with signature\". Surplus par' +
      'am entries are marked as <!-- removed: Name -->, not deleted. false: /// stays as typed.",' + #10 +
      '          "x-issue": "#88"' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "codeActions",' + #10,
    '      "x-page": "Eingabehilfen",' + #10 + '      "x-control": "Kontrollkästchen",' + #10 +
      '      "x-issue": "#88"' + #10 + '    },' + #10 + '    "metrics": {' + #10 + '      "type": "boolean",' + #10 +
      '      "default": true,' + #10 +
      '      "description": "Kennzahlen überhaupt: false schaltet die Kennzahlen über den Methode' +
      'n (codeLens.metrics) und alle Regeln metric-* für alle Projekte ab. Ein Projekt übersteuer' +
      't das je Regel, indem es sie in atlas.json unter \"rules\" ausdrücklich setzt, z. B. \"met' +
      'ric-method-length\": \"warning\".",' + #10 +
      '      "x-description-en": "Metrics at all: false turns off the metrics above methods (code' +
      'Lens.metrics) and all rules metric-* for all projects. A project overrides this per rule b' +
      'y setting it explicitly in atlas.json under \"rules\", e.g. \"metric-method-length\": \"wa' + 'rning\".",' +
      #10 + '      "x-scope": "global",' + #10 + '      "x-area": "editor",' + #10 + '      "x-page": "Editor",' + #10,
    '      "x-control": "Kontrollkästchen",' + #10 + '      "x-issue": "#66"' + #10 + '    },' + #10 +
      '    "experimental": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Experimentelle Funktionen (#834): riskant oder noch unreif, abschalt' +
      'bar, als „Experimentell“ gekennzeichnet und nach der Installation aus.",' + #10 +
      '      "x-description-en": "Experimental features (#834): risky or not yet mature, can be t' +
      'urned off, marked as \"Experimental\" and off after installation.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "enabled": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Hauptschalter: false = keine experimentelle Funktion wirkt, auch' +
      ' wenn ihr eigener Schalter an ist; die Einzelschalter behalten ihren Wert. true = die Einz' +
      'elschalter (Kennzeichen „Experimentell“, Vorgabe aus) gelten.",' + #10,
    '          "x-description-en": "Main switch: false = no experimental feature is active, eve' +
      'n if its own switch is on; the individual switches keep their value. true = the individual' +
      ' switches (marked \"Experimental\", default off) apply.",' + #10 + '          "x-issue": "#834"' + #10 +
      '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "general",' + #10 +
      '      "x-page": "Allgemein",' + #10 +
      '      "x-control": "Kontrollkästchen „Experimentelle Funktionen erlauben“",' + #10 + '      "x-issue": "#834"' +
      #10 + '    },' + #10 + '    "slashCommands": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Schnellbefehle: Eine Zeile, die mit /name beginnt, wird nach Enter a' +
      'usgeführt und verschwindet. Nach / schlägt die Vervollständigung alle Befehle vor.",' + #10,
    '      "x-description-en": "Slash commands: a line starting with /name is executed after En' +
      'ter and disappears. After / completion suggests all commands.",' + #10 + '      "additionalProperties": false,' +
      #10 + '      "properties": {' + #10 + '        "enabled": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 + '          "description": "Schnellbefehle auswerten.",' + #10 +
      '          "x-description-en": "Evaluate slash commands."' + #10 + '        },' + #10 + '        "disabled": {' +
      #10 + '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [],' + #10 +
      '          "description": "Abgeschaltete Befehle ohne /, z. B. [\"uses\"]. usesCommand: fal' +
      'se wirkt wie \"uses\" in dieser Liste.",' + #10,
    '          "x-description-en": "Disabled commands without /, e.g. [\"uses\"]. usesCommand: ' +
      'false acts like \"uses\" in this list."' + #10 + '        },' + #10 + '        "headerTemplate": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "description": "Vorlage für /header mit den Platzhaltern {unit}, {jahr} und {aut' +
      'or}. Leer: die Vorlage der Regel file-header, sonst ein einfacher Kopf.",' + #10 +
      '          "x-description-en": "Template for /header with the placeholders {unit}, {jahr} (' +
      'year) and {autor} (author). Empty: the template of the rule file-header, otherwise a simpl' + 'e header."' +
      #10 + '        },' + #10 + '        "logCall": {' + #10 + '          "type": "string",' + #10 +
      '          "default": "",' + #10,
    '          "description": "Protokollaufruf für /log, /except und /measure: ein Routinenname' +
      ' wie \"Log.Debug\" bekommt den Text als Argument, {text} setzt ihn an diese Stelle, z. B. ' +
      '\"Logger.Send(TLogLevel.Debug, {text})\". Leer: OutputDebugString(PChar(…)).",' + #10 +
      '          "x-description-en": "Logging call for /log, /except and /measure: a routine name' +
      ' such as \"Log.Debug\" gets the text as argument, {text} puts it at that place, e.g. \"Log' +
      'ger.Send(TLogLevel.Debug, {text})\". Empty: OutputDebugString(PChar(…)).",' + #10 +
      '          "x-issue": "#304"' + #10 + '        },' + #10 + '        "componentPalette": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "Eigene",' + #10 +
      '          "description": "Palettenseite, auf der /component die neue Komponente mit Regist' +
      'erComponents einträgt.",' + #10,
    '          "x-description-en": "Palette page on which /component registers the new componen' +
      't with RegisterComponents.",' + #10 + '          "x-issue": "#299"' + #10 + '        },' + #10 +
      '        "todoOwner": {' + #10 + '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "description": "Name hinter -o, den /todo einträgt. Leer: user.name aus der git-' +
      'Konfiguration (Repository, dann Benutzerordner), sonst der Anmeldename. /todo -oName in de' +
      'r Zeile geht vor.",' + #10 +
      '          "x-description-en": "Name after -o that /todo writes. Empty: user.name from the ' +
      'git configuration (repository, then user folder), otherwise the login name. /todo -oName i' +
      'n the line takes precedence.",' + #10 + '          "x-issue": "#297"' + #10 + '        },' + #10 +
      '        "todoCategory": {' + #10 + '          "type": "string",' + #10 + '          "default": "",' + #10,
    '          "description": "Kategorie hinter -c, die /todo einträgt. Leer: keine. /todo -cKa' +
      'tegorie in der Zeile geht vor.",' + #10 +
      '          "x-description-en": "Category after -c that /todo writes. Empty: none. /todo -cC' +
      'ategory in the line takes precedence.",' + #10 + '          "x-issue": "#297"' + #10 + '        },' + #10 +
      '        "sortUsesRemoveUnused": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "/sortuses streicht auch ungenutzte Units laut Index. Units mit i' +
      'nitialization oder finalization und die aus usesKeep bleiben.",' + #10 +
      '          "x-description-en": "/sortuses also removes units unused according to the index.' +
      ' Units with initialization or finalization and those from usesKeep stay.",' + #10 +
      '          "x-issue": "#297"' + #10 + '        },' + #10 + '        "enumHelper": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "/helper für eine Aufzählung legt die Namenstabelle cNames sowie ' +
      'ToString und FromString an. Aus: ein leerer record helper wie bei anderen Typen.",' + #10 +
      '          "x-description-en": "/helper for an enumeration creates the name table cNames as' +
      ' well as ToString and FromString. Off: an empty record helper as for other types.",' + #10 +
      '          "x-issue": "#875"' + #10 + '        },' + #10 + '        "setHelper": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "/helper für eine Menge (set of) legt Contains, ToText, Toggle un' +
      'd All an. Aus: ein leerer record helper wie bei anderen Typen.",' + #10 +
      '          "x-description-en": "/helper for a set (set of) creates Contains, ToText, Toggle' +
      ' and All. Off: an empty record helper as for other types.",' + #10 + '          "x-issue": "#875"' + #10 +
      '        }' + #10 + '      },' + #10,
    '      "x-scope": "global",' + #10 + '      "x-area": "codeActions",' + #10 + '      "x-page": "Eingabehilfen",' +
      #10 + '      "x-control": "Kontrollkästchen, Liste",' + #10 + '      "x-issue": "#293"' + #10 + '    },' + #10 +
      '    "sortUses": {' + #10 + '      "type": [' + #10 + '        "boolean",' + #10 + '        "string"' + #10 +
      '      ],' + #10 + '      "enum": [' + #10 + '        true,' + #10 + '        false,' + #10 +
      '        "alphabetic",' + #10 + '        "namespace"' + #10 + '      ],' + #10 + '      "default": false,' + #10 +
      '      "description": "\"uses aufräumen\" (source.organizeImports, z. B. beim Speichern) so' +
      'rtiert die uses: true oder \"alphabetic\" alphabetisch, \"namespace\" nach Namespace grupp' +
      'iert (System, Vcl, ... und Units ohne Namespace zuletzt). Achtung: Die Reihenfolge bestimm' +
      't die Initialisierung der Units.",' + #10,
    '      "x-description-en": "\"Organize uses\" (source.organizeImports, e.g. on save) sorts ' +
      'the uses: true or \"alphabetic\" alphabetically, \"namespace\" grouped by namespace (Syste' +
      'm, Vcl, ... and units without namespace last). Caution: the order determines the initializ' +
      'ation of the units.",' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Eingabehilfen",' + #10 +
      '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#182, #284"' + #10 + '    },' + #10 +
      '    "usesKeep": {' + #10 + '      "type": "array",' + #10 + '      "items": {' + #10 +
      '        "type": "string"' + #10 + '      },' + #10 + '      "default": [],' + #10 +
      '      "description": "Units, die \"ungenutzte uses entfernen\" nie entfernt, zusätzlich zu' +
      ' allen Units mit initialization-Abschnitt.",' + #10 +
      '      "x-description-en": "Units that \"Remove unused uses\" never removes, in addition to' +
      ' all units with an initialization section.",' + #10,
    '      "x-scope": "project",' + #10 + '      "x-page": "Eingabehilfen",' + #10 + '      "x-control": "Liste",' +
      #10 + '      "x-issue": "#284"' + #10 + '    },' + #10 + '    "deadCode": {' + #10 + '      "type": "object",' +
      #10 + '      "description": "Toter Code: Elemente, die als verwendet gelten, obwohl ihr Name im C' +
      'ode nicht vorkommt (RTTI, Serialisierung, Plugins). Gilt für unused-private-member, unused' +
      '-public-member und unused-declaration, zusätzlich zu den Optionen keepAttributes und keepP' +
      'atterns der Regeln.",' + #10 +
      '      "x-description-en": "Dead code: elements that count as used although their name does' +
      ' not appear in the code (RTTI, serialization, plugins). Applies to unused-private-member, ' +
      'unused-public-member and unused-declaration, in addition to the options keepAttributes and' +
      ' keepPatterns of the rules.",' + #10 + '      "additionalProperties": false,' + #10 + '      "properties": {' +
      #10 + '        "keepAttributes": {' + #10,
    '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [],' + #10 +
      '          "description": "Attributnamen ohne \"Attribute\", z. B. \"JsonName\": Alle Mitgl' +
      'ieder eines Typs mit diesem Attribut gelten als verwendet.",' + #10 +
      '          "x-description-en": "Attribute names without \"Attribute\", e.g. \"JsonName\": a' +
      'll members of a type with this attribute count as used."' + #10 + '        },' + #10 +
      '        "keepPatterns": {' + #10 + '          "type": "array",' + #10 + '          "items": {' + #10 +
      '            "type": "string"' + #10 + '          },' + #10 + '          "default": [],' + #10 +
      '          "description": "Namensmuster mit * und ?, auch als Typ.Name, z. B. \"*Handler\" ' +
      'oder \"TPlugin.*\": Passende Elemente gelten als verwendet.",' + #10,
    '          "x-description-en": "Name patterns with * and ?, also as Type.Name, e.g. \"*Hand' +
      'ler\" or \"TPlugin.*\": matching elements count as used."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "project",' + #10 + '      "x-page": "Prüfregeln",' + #10 +
      '      "x-control": "Liste mit Hinzufügen/Entfernen",' + #10 + '      "x-issue": "#64"' + #10 + '    },' + #10 +
      '    "dfmPropertyRules": {' + #10 + '      "type": "array",' + #10 + '      "default": [],' + #10 +
      '      "description": "Eigenschaftsregeln für Formulardateien: Vorgaben für Komponenten-Pro' +
      'perties, gemeldet als dfm-property am Feld der Komponente in der Unit. Nicht gespeicherte ' +
      'Properties gelten mit ihrem default-Wert.",' + #10 +
      '      "x-description-en": "Property rules for form files: requirements for component prope' +
      'rties, reported as dfm-property on the field of the component in the unit. Properties not ' +
      'stored count with their default value.",' + #10,
    '      "items": {' + #10 + '        "type": "object",' + #10 + '        "additionalProperties": false,' + #10 +
      '        "required": ["class", "property"],' + #10 + '        "properties": {' + #10 +
      '          "class": { "type": "string", "description": "Komponentenklasse, z. B. TLabel.", ' +
      '"x-description-en": "Component class, e.g. TLabel." },' + #10 +
      '          "property": { "type": "string", "description": "Property-Pfad, auch Font.Name (n' +
      'ur gespeicherte Werte).", "x-description-en": "Property path, also Font.Name (stored value' + 's only)." },' +
      #10 + '          "condition": { "type": "string", "enum": ["=", "<>", "contains", "notContains", ' +
      '"empty", "notEmpty"], "default": "=", "description": "Bedingung; contains und notContains ' +
      'für Mengen und Strings.", "x-description-en": "Condition; contains and notContains for set' +
      's and strings." },' + #10,
    '          "value": { "type": "string", "description": "Sollwert wie in der DFM, z. B. True' +
      ', poScreenCenter, dgRowSelect.", "x-description-en": "Expected value as in the DFM, e.g. T' +
      'rue, poScreenCenter, dgRowSelect." },' + #10 +
      '          "message": { "type": "string", "description": "Meldung; ohne Angabe aus Klasse, ' +
      'Property und Bedingung gebildet.", "x-description-en": "Message; if missing, built from cl' +
      'ass, property and condition." },' + #10 +
      '          "severity": { "type": "string", "enum": ["off", "hint", "info", "warning", "erro' +
      'r"], "default": "warning", "description": "Schweregrad der Meldung.", "x-description-en": ' +
      '"Severity of the message." },' + #10 +
      '          "includeDescendants": { "type": "boolean", "default": true, "description": "Gilt' +
      ' auch für Nachfahren der Klasse.", "x-description-en": "Also applies to descendants of the' + ' class." },' +
      #10,
    '          "fix": { "type": "string", "enum": ["auto", "prompt", "none"], "default": "promp' +
      't", "description": "Korrektur: auto sicher mit source.fixAll, prompt nur als Code-Aktion, ' +
      'none keine.", "x-description-en": "Fix: auto safely with source.fixAll, prompt only as cod' +
      'e action, none no fix." },' + #10 +
      '          "exclude": { "type": "array", "items": { "type": "string" }, "default": [], "des' +
      'cription": "Glob-Muster für Dateien, die die Regel nicht prüft.", "x-description-en": "Glo' +
      'b patterns for files the rule does not check." }' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "project",' + #10 + '      "x-page": "Prüfregeln",' + #10 +
      '      "x-control": "Eigener Editor (Klasse und Property aus dem Index)",' + #10 + '      "x-issue": "#309"' +
      #10 + '    },' + #10 + '    "memoryBudgetMb": {' + #10 + '      "type": "integer",' + #10 +
      '      "minimum": 0,' + #10 + '      "default": 768,' + #10,
    '      "description": "Obergrenze für den Symbolindex im Arbeitsspeicher in MB. Darüber wer' +
      'den zuerst Bibliotheks-Units (RTL, VCL) kompakt gehalten (nur interface-Symbole), dann die' +
      ' Verwendungen der Projekt-Units ausgelagert (sie bleiben im Cache auf der Platte) und zule' +
      'tzt Projekt-Units kompakt gehalten. 0: unbegrenzt.",' + #10 +
      '      "x-description-en": "Upper limit for the symbol index in memory in MB. Above it firs' +
      't library units (RTL, VCL) are kept compact (interface symbols only), then the usages of p' +
      'roject units are swapped out (they stay in the cache on disk) and finally project units ar' +
      'e kept compact. 0: unlimited.",' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "general",' +
      #10 + '      "x-page": "Speicher",' + #10 + '      "x-control": "Zahlenfeld (MB)",' + #10 +
      '      "x-issue": "#185, #492"' + #10 + '    },' + #10 + '    "index": {' + #10 + '      "type": "object",' +
      #10,
    '      "description": "Umfang des Symbolindex. Standard: alle Projekte der Projektgruppe, a' +
      'lle Units der Projekt-Suchpfade und alle Units der Bibliotheks- und Suchpfade der Delphi-I' +
      'nstallation, auch wenn keine Unit sie einbindet. Reihenfolge: aktives Projekt, übrige Proj' +
      'ekte, Suchpfade, Bibliothek; alles im Hintergrund, die Bibliothek aus dem gemeinsamen Cach' + 'e.",' + #10 +
      '      "x-description-en": "Scope of the symbol index. Default: all projects of the project' +
      ' group, all units of the project search paths and all units of the library and search path' +
      's of the Delphi installation, even if no unit uses them. Order: active project, other proj' +
      'ects, search paths, library; everything in the background, the library from the shared cac' + 'he.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "projectGroup": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Alle Projekte der Projektgruppe indizieren; aus = nur das Projek' +
      't der geöffneten Datei.",' + #10 +
      '          "x-description-en": "Index all projects of the project group; off = only the pro' +
      'ject of the open file."' + #10 + '        },' + #10 + '        "searchPaths": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Alle Units der Projekt-Suchpfade indizieren; aus = nur über uses' + ' erreichbare.",' +
      #10 + '          "x-description-en": "Index all units of the project search paths; off = only tho' +
      'se reachable via uses."' + #10 + '        },' + #10 + '        "libraryPaths": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Alle Units der Bibliotheks- und Suchpfade der Installation indiz' +
      'ieren (RTL, VCL, Komponenten); aus = nur über uses erreichbare.",' + #10,
    '          "x-description-en": "Index all units of the library and search paths of the inst' +
      'allation (RTL, VCL, components); off = only those reachable via uses."' + #10 + '        },' + #10 +
      '        "usages": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Verwendungen der Bezeichner in Projekt-Units mit indizieren (Ver' +
      'wendungsbeispiele); aus = nur Deklarationen, kleinerer Index.",' + #10 +
      '          "x-description-en": "Also index usages of identifiers in project units (usage ex' +
      'amples); off = declarations only, smaller index."' + #10 + '        },' + #10 + '        "removeOrphans": {' +
      #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Index-Caches gelöschter Projekte (z. B. entfernter Branch-Ordner' +
      ') und Caches im alten Format beim Laden eines Projekts löschen. Liegt das Projekt auf eine' +
      'm gerade nicht verbundenen Laufwerk, bleibt der Cache.",' + #10 +
      '          "x-description-en": "Delete index caches of deleted projects (e.g. removed branc' +
      'h folders) and caches in the old format when loading a project. If the project is on a dri' +
      've that is currently not connected, the cache stays."' + #10 + '        },' + #10 +
      '        "cacheMaxAgeDays": {' + #10 + '          "type": "integer",' + #10 + '          "minimum": 0,' + #10 +
      '          "maximum": 3650,' + #10 + '          "default": 14,' + #10 +
      '          "description": "Index-Caches löschen, die so viele Tage nicht benutzt wurden (La' +
      'den des Projekts zählt als Benutzung); 0 = aus. Das betrifft auch die Bibliotheks-Caches d' +
      'einstallierter Delphi-Versionen.",' + #10,
    '          "x-description-en": "Delete index caches not used for this many days (loading th' +
      'e project counts as use); 0 = off. This also affects the library caches of uninstalled Del' + 'phi versions."' +
      #10 + '        },' + #10 + '        "cacheMaxMb": {' + #10 + '          "type": "integer",' + #10 +
      '          "minimum": 0,' + #10 + '          "maximum": 1048576,' + #10 + '          "default": 1024,' + #10 +
      '          "description": "Höchstgröße des Cache-Ordners in MB; darüber gehen die am längst' +
      'en nicht benutzten Caches zuerst. 0 = ohne Grenze.",' + #10 +
      '          "x-description-en": "Maximum size of the cache folder in MB; above it the caches' +
      ' unused for the longest time go first. 0 = no limit."' + #10 + '        },' + #10 + '        "exclude": {' +
      #10 + '          "x-scope": "project",' + #10 + '          "type": "array",' + #10 +
      '          "items": { "type": "string" },' + #10 + '          "default": [],' + #10,
    '          "description": "Ordner oder Dateien, die nicht indiziert werden (Glob-Muster geg' +
      'en den vollen Pfad: *, **, ?).",' + #10 +
      '          "x-description-en": "Folders or files that are not indexed (glob patterns agains' +
      't the full path: *, **, ?).",' + #10 + '          "examples": [["**/Demos/**", "**/Samples/**"]]' + #10 +
      '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "general",' + #10 +
      '      "x-page": "Speicher",' + #10 + '      "x-control": "Kontrollkästchen, Liste mit Hinzufügen/Entfernen",' +
      #10 + '      "x-issue": "#648, #492, #905"' + #10 + '    },' + #10 + '    "architecture": {' + #10 +
      '      "type": "object",' + #10 +
      '      "description": "Architekturübersicht aus dem Index: zentrale Units, Teilsysteme, Zyk' +
      'len und Querverbindungen im Fenster „Atlas-Architektur“, als Bericht (Markdown oder HTML, ' +
      'auch AtlasServer --architecture) und im MCP-Werkzeug get_architecture.",' + #10,
    '      "x-description-en": "Architecture overview from the index: central units, subsystems' +
      ', cycles and cross connections in the window \"Atlas Architecture\", as a report (Markdown' +
      ' or HTML, also AtlasServer --architecture) and in the MCP tool get_architecture.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "enabled": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Hauptschalter: false = kein Fenster, kein Menüeintrag, kein Beri' +
      'cht, kein get_architecture.",' + #10 +
      '          "x-description-en": "Main switch: false = no window, no menu item, no report, no' +
      ' get_architecture."' + #10 + '        },' + #10 + '        "scope": {' + #10 + '          "type": "string",' +
      #10 + '          "enum": [' + #10 + '            "project",' + #10 + '            "projectGroup"' + #10 +
      '          ],' + #10 + '          "default": "projectGroup",' + #10,
    '          "description": "Umfang der Auswertung: nur das aktive Projekt oder die ganze Pro' + 'jektgruppe.",' +
      #10 + '          "x-description-en": "Scope of the analysis: only the active project or the whole' +
      ' project group."' + #10 + '        },' + #10 + '        "includeLibraryUnits": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Units aus RTL, VCL und den Bibliothekspfaden mitzählen; aus = nu' +
      'r Units der Projekte und ihrer Suchpfade.",' + #10 +
      '          "x-description-en": "Count units from RTL, VCL and the library paths; off = only' +
      ' units of the projects and their search paths."' + #10 + '        },' + #10 + '        "centralUnits": {' + #10 +
      '          "type": "integer",' + #10 + '          "minimum": 5,' + #10 + '          "maximum": 100,' + #10 +
      '          "default": 15,' + #10,
    '          "description": "Wie viele zentrale Units Fenster, Bericht und get_architecture z' + 'eigen.",' + #10 +
      '          "x-description-en": "How many central units window, report and get_architecture ' + 'show."' + #10 +
      '        },' + #10 + '        "exclude": {' + #10 + '          "x-scope": "project",' + #10 +
      '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [],' + #10 +
      '          "description": "Units, die nicht in die Auswertung eingehen: Glob-Muster auf den' +
      ' Unit-Namen oder den Pfad relativ zum Projekt (*, **, ?).",' + #10 +
      '          "x-description-en": "Units that are left out of the analysis: glob patterns on t' +
      'he unit name or the path relative to the project (*, **, ?).",' + #10 + '          "examples": [' + #10 +
      '            [' + #10 + '              "Tests/**",' + #10 + '              "*.Tests"' + #10 + '            ]' +
      #10 + '          ]' + #10,
    '        },' + #10 + '        "baseline": {' + #10 + '          "x-scope": "project",' + #10 +
      '          "x-control": "Datei wählen",' + #10 + '          "x-issue": "#1121",' + #10 +
      '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "description": "Gespeicherter Architekturstand (JSON aus AtlasServer --architect' +
      'ure <Datei.json> oder „Stand speichern …“), Pfad relativ zum Projekt: Fenster, Bericht und' +
      ' get_architecture vergleichen automatisch damit. Leer = kein Vergleich.",' + #10 +
      '          "x-description-en": "Saved architecture state (JSON from AtlasServer --architect' +
      'ure <file.json> or \"Save state …\"), path relative to the project: window, report and get' +
      '_architecture compare with it automatically. Empty = no comparison.",' + #10 + '          "examples": [' + #10 +
      '            "architektur-main.json"' + #10 + '          ]' + #10 + '        },' + #10 + '        "failOn": {' +
      #10,
    '          "x-scope": "project",' + #10 +
      '          "x-control": "Liste mit Hinzufügen/Entfernen (newCycle, newCrossLink, subsystemC' +
      'hange, centralGrowth)",' + #10 + '          "x-issue": "#1121",' + #10 + '          "type": "array",' + #10 +
      '          "items": {' + #10 + '            "type": "string",' + #10 + '            "enum": [' + #10 +
      '              "newCycle",' + #10 + '              "newCrossLink",' + #10 + '              "subsystemChange",' +
      #10 + '              "centralGrowth"' + #10 + '            ]' + #10 + '          },' + #10 +
      '          "default": [' + #10 + '            "newCycle"' + #10 + '          ],' + #10 +
      '          "description": "Welche Abweichungen AtlasServer --compare als Fehler meldet (Exi' +
      'tcode 1), wenn --fail-on fehlt: neue Zyklen, neue Querverbindungen, Units mit Teilsystemwe' +
      'chsel, zentrale Units mit stark gewachsener Abhängigkeit.",' + #10,
    '          "x-description-en": "Which deviations AtlasServer --compare reports as errors (e' +
      'xit code 1) if --fail-on is missing: new cycles, new cross connections, units changing sub' +
      'system, central units with strongly grown dependency."' + #10 + '        },' + #10 +
      '        "explainAssignment": {' + #10 + '          "x-page": "Architektur",' + #10 +
      '          "x-control": "Kontrollkästchen",' + #10 + '          "x-issue": "#1368",' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Zuordnung jeder Unit erklären: Tabelle der Kanten je Teilsystem ' +
      '(interface, implementation, gewichtete Summe) im Hinweis und Steckbrief des Fensters, im B' +
      'ericht und in get_architecture mit unit, dazu die Spalte „knapp“ für Units, bei denen ein ' +
      'anderes Teilsystem mindestens 75 % der Summe erreicht.",' + #10,
    '          "x-description-en": "Explain the assignment of each unit: table of edges per sub' +
      'system (interface, implementation, weighted sum) in the hint and profile of the window, in' +
      ' the report and in get_architecture with unit, plus the column \"close\" for units where a' +
      'nother subsystem reaches at least 75 % of the sum."' + #10 + '        },' + #10 + '        "grouping": {' + #10 +
      '          "type": "object",' + #10 + '          "x-page": "Architektur",' + #10 +
      '          "x-control": "resolution: Zahl (0,2–5,0) und Regler „Feinheit“ im Fenster; showR' +
      'esolutionSlider: Kontrollkästchen; maxShare: Zahl (0–0,9); minCohesion: Zahl (0–1); founda' +
      'tions: Auswahl",' + #10 + '          "x-issue": "#1366, #1364, #1365",' + #10 +
      '          "description": "Wie die Architekturübersicht die Units in Teilsysteme gruppiert ' +
      '(Louvain auf dem uses-Graphen). Gilt für Fenster, Bericht, AtlasServer --architecture und ' +
      'get_architecture.",' + #10,
    '          "x-description-en": "How the architecture overview groups the units into subsyst' +
      'ems (Louvain on the uses graph). Applies to window, report, AtlasServer --architecture and' +
      ' get_architecture.",' + #10 + '          "additionalProperties": false,' + #10 + '          "properties": {' +
      #10 + '            "resolution": {' + #10 +
      '              "x-control": "Zahl (0,2–5,0); im Fenster Regler „Feinheit“ (grob … fein, Dop' +
      'pelklick = 1,0)",' + #10 + '              "x-issue": "#1366",' + #10 + '              "type": "number",' + #10 +
      '              "minimum": 0.2,' + #10 + '              "maximum": 5,' + #10 + '              "default": 1,' +
      #10,
    '              "description": "Feinheit der Teilsysteme (Auflösung γ des Louvain-Verfahrens' +
      '): größer = mehr und kleinere Teilsysteme, kleiner = weniger und größere; 1,0 = Verhalten ' +
      'wie bisher. atlas/architecture und get_architecture übersteuern den Wert mit \"resolution\' +
      '" für einen Aufruf.",' + #10 +
      '              "x-description-en": "Granularity of the subsystems (resolution γ of the Louv' +
      'ain method): larger = more and smaller subsystems, smaller = fewer and larger ones; 1.0 = ' +
      'behavior as before. atlas/architecture and get_architecture override the value with \"reso' +
      'lution\" for one call."' + #10 + '            },' + #10 + '            "showResolutionSlider": {' + #10 +
      '              "x-control": "Kontrollkästchen",' + #10 + '              "x-issue": "#1366",' + #10 +
      '              "type": "boolean",' + #10 + '              "default": true,' + #10,
    '              "description": "Regler „Feinheit“ in der Werkzeugleiste des Fensters „Atlas-' +
      'Architektur“ zeigen; aus = kein Regler, resolution wirkt weiter.",' + #10 +
      '              "x-description-en": "Show the slider \"Granularity\" in the toolbar of the w' +
      'indow \"Atlas Architecture\"; off = no slider, resolution still applies."' + #10 + '            },' + #10 +
      '            "maxShare": {' + #10 + '              "x-control": "Zahl (0–0,9)",' + #10 +
      '              "x-issue": "#1364",' + #10 + '              "type": "number",' + #10 +
      '              "minimum": 0,' + #10 + '              "maximum": 0.9,' + #10 + '              "default": 0.25,' +
      #10,
    '              "description": "Ab diesem Anteil aller Units wird ein Teilsystem (ab 10 Unit' +
      's) mit einem zweiten Louvain-Lauf auf seinen Units nachgeteilt, höchstens zwei Stufen tief' +
      '; die Teile tragen den Namen des ursprünglichen Teilsystems als „Teil von …“. 0 = nie nach' +
      ' Größe teilen.",' + #10 +
      '              "x-description-en": "From this share of all units a subsystem (from 10 units' +
      ') is split again with a second Louvain run on its units, at most two levels deep; the part' +
      's carry the name of the original subsystem as \"part of …\". 0 = never split by size."' + #10 +
      '            },' + #10 + '            "minCohesion": {' + #10 + '              "x-control": "Zahl (0–1)",' + #10 +
      '              "x-issue": "#1364",' + #10 + '              "type": "number",' + #10 +
      '              "minimum": 0,' + #10 + '              "maximum": 1,' + #10 + '              "default": 0.3,' +
      #10,
    '              "description": "Teilsysteme ab 30 Units, deren Zusammenhalt (Anteil der Kant' +
      'en, die im Teilsystem bleiben) darunter liegt, werden ebenso nachgeteilt. 0 = nie nach Zus' +
      'ammenhalt teilen.",' + #10 +
      '              "x-description-en": "Subsystems from 30 units whose cohesion (share of edges' +
      ' staying in the subsystem) is below this value are split as well. 0 = never split by cohes' + 'ion."' + #10 +
      '            },' + #10 + '            "foundations": {' + #10 +
      '              "x-control": "Auswahl (mitgruppieren, anhängen, eigenes Teilsystem)",' + #10 +
      '              "x-issue": "#1365",' + #10 + '              "type": "string",' + #10 +
      '              "enum": ["group", "attach", "separate"],' + #10 + '              "default": "separate",' + #10,
    '              "description": "Übergreifende Fundament-Units (Rolle Fundament, direkt Abhän' +
      'gige in mindestens drei Teilsystemen oder höchstens zu 60 % im eigenen) beim Gruppieren: g' +
      'roup = mitgruppieren wie bisher; attach = ohne sie gruppieren und danach ins Teilsystem mi' +
      't den meisten Abhängigen; separate = eigenes Teilsystem „Fundament“ in der Mitte der Karte' +
      ', Kanten dorthin keine Querverbindungen.",' + #10 +
      '              "x-description-en": "Cross-cutting foundation units (role foundation, direct' +
      ' dependents in at least three subsystems or at most 60 % in their own) when grouping: grou' +
      'p = group them as before; attach = group without them and then add them to the subsystem w' +
      'ith the most dependents; separate = own subsystem \"Foundation\" in the middle of the map,' +
      ' edges to it are no cross connections."' + #10 + '            },' + #10 + '            "keepPrevious": {' + #10,
    '              "x-control": "Kontrollkästchen; im Fenster Befehl „Teilsysteme neu benennen“' + '",' + #10 +
      '              "x-issue": "#1367",' + #10 + '              "type": "boolean",' + #10 +
      '              "default": true,' + #10 +
      '              "description": "Farben und Namen der Teilsysteme an den vorigen Stand anglei' +
      'chen: an architecture.baseline, sonst an den zuletzt berechneten Stand im Cache-Verzeichni' +
      's. Ein Teilsystem behält Farbe und Namen, wenn es mit einem alten mehr als die Hälfte der ' +
      'Units beider teilt. aus = Farben und Namen nach Reihenfolge wie bisher. AtlasServer --arch' +
      'itecture gleicht nur an architecture.baseline an und schreibt keinen Stand.",' + #10,
    '              "x-description-en": "Align colors and names of the subsystems with the previ' +
      'ous state: with architecture.baseline, otherwise with the last computed state in the cache' +
      ' directory. A subsystem keeps color and name if it shares more than half of the units of b' +
      'oth with an old one. off = colors and names by order as before. AtlasServer --architecture' +
      ' only aligns with architecture.baseline and writes no state."' + #10 + '            }' + #10 + '          }' +
      #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "general",' +
      #10 + '      "x-page": "Architektur",' + #10,
    '      "x-control": "Kontrollkästchen, Auswahl, Kontrollkästchen, Zahl (5–100); exclude: Li' +
      'ste mit Hinzufügen/Entfernen in den Projekt-Einstellungen; baseline: Datei wählen, failOn:' +
      ' Liste (Projekt-Einstellungen, #1121); grouping: Gruppierung der Teilsysteme (#1366), keep' +
      'Previous: Farben und Namen halten (#1367)",' + #10 + '      "x-issue": "#1118"' + #10 + '    },' + #10 +
      '    "query": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Code-Abfragen über den Index (#1351): eine kleine Sprache wie „class' +
      'es where inherits TForm and methods > 40 order by methods desc“ im Fenster „Atlas-Abfrage“' +
      ', im MCP-Werkzeug query_code und mit AtlasServer --check <Ziel> --query. Felder und Zahlen' +
      ' stammen aus Index, Metriken, Uses-Graph, Formulardateien und Aufrufhierarchie (dieselben ' +
      'wie get_metrics und find_unused_code).",' + #10,
    '      "x-description-en": "Code queries over the index (#1351): a small language such as \' +
      '"classes where inherits TForm and methods > 40 order by methods desc\" in the window \"Atl' +
      'as Query\", in the MCP tool query_code and with AtlasServer --check <target> --query. Fiel' +
      'ds and numbers come from index, metrics, uses graph, form files and call hierarchy (the sa' +
      'me as get_metrics and find_unused_code).",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "enabled": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Hauptschalter: false = kein Fenster, kein Menü- und Palettenbefe' +
      'hl, kein query_code; --query endet mit Exitcode 3 und Hinweis. Gespeicherte Abfragen mit f' +
      'ailIfAny melden dann nichts.",' + #10,
    '          "x-description-en": "Main switch: false = no window, no menu or palette command,' +
      ' no query_code; --query ends with exit code 3 and a notice. Saved queries with failIfAny t' +
      'hen report nothing."' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-page": "Allgemein",' + #10 +
      '      "x-control": "Kontrollkästchen „Code-Abfragen (Fenster Atlas-Abfrage, query_code)“",' + #10 +
      '      "x-issue": "#1351"' + #10 + '    },' + #10 + '    "queries": {' + #10 + '      "type": "array",' + #10 +
      '      "default": [],' + #10 +
      '      "description": "Gespeicherte Code-Abfragen (#1351) für das Fenster „Atlas-Abfrage“, ' +
      'query_code und AtlasServer --query @name. Mit failIfAny wird jeder Treffer ein Befund der ' +
      'Regel query:<name> im Editor, bei --check und in SARIF; Baseline, Unterdrückungen und rule' +
      's wirken wie bei anderen Regeln.",' + #10,
    '      "x-description-en": "Saved code queries (#1351) for the window \"Atlas Query\", quer' +
      'y_code and AtlasServer --query @name. With failIfAny every hit becomes a finding of the ru' +
      'le query:<name> in the editor, with --check and in SARIF; baseline, suppressions and rules' +
      ' act as for other rules.",' + #10 + '      "items": {' + #10 + '        "type": "object",' + #10 +
      '        "additionalProperties": false,' + #10 + '        "required": [' + #10 + '          "name",' + #10 +
      '          "query"' + #10 + '        ],' + #10 + '        "properties": {' + #10 + '          "name": {' + #10 +
      '            "type": "string",' + #10 + '            "pattern": "^[A-Za-z0-9._-]+$",' + #10 +
      '            "description": "Name der Abfrage: Buchstaben, Ziffern, „-“, „_“ und „.“; Kennu' +
      'ng der Regel query:<name> und von --query @name. Groß-/Kleinschreibung zählt nicht, doppel' +
      'te Namen gelten nicht.",' + #10,
    '            "x-description-en": "Name of the query: letters, digits, \"-\", \"_\" and \".\' +
      '"; id of the rule query:<name> and of --query @name. Case does not matter, duplicate names' + ' are invalid."' +
      #10 + '          },' + #10 + '          "query": {' + #10 + '            "type": "string",' + #10 +
      '            "description": "Die Abfrage, z. B. „classes where methods > 40 order by method' + 's desc“.",' +
      #10 + '            "x-description-en": "The query, e.g. \"classes where methods > 40 order by met' +
      'hods desc\"."' + #10 + '          },' + #10 + '          "description": {' + #10 +
      '            "type": "string",' + #10 + '            "default": "",' + #10 +
      '            "description": "Beschreibung für Auswahlliste und Regelbeschreibung (SARIF).",' + #10 +
      '            "x-description-en": "Description for the selection list and the rule descripti' + 'on (SARIF)."' +
      #10 + '          },' + #10 + '          "failIfAny": {' + #10,
    '            "type": "boolean",' + #10 + '            "default": false,' + #10 +
      '            "description": "Jeder Treffer wird ein Befund der Regel query:<name>; --check ' +
      '--query @name endet dann mit Exitcode 1.",' + #10 +
      '            "x-description-en": "Every hit becomes a finding of the rule query:<name>; --c' +
      'heck --query @name then ends with exit code 1."' + #10 + '          },' + #10 + '          "severity": {' + #10 +
      '            "type": "string",' + #10 + '            "enum": [' + #10 + '              "off",' + #10 +
      '              "hint",' + #10 + '              "info",' + #10 + '              "warning",' + #10 +
      '              "error"' + #10 + '            ],' + #10 + '            "default": "warning",' + #10 +
      '            "description": "Schweregrad der Befunde mit failIfAny.",' + #10 +
      '            "x-description-en": "Severity of the findings with failIfAny."' + #10 + '          },' + #10 +
      '          "message": {' + #10,
    '            "type": "string",' + #10 + '            "default": "",' + #10 +
      '            "description": "Meldung je Treffer mit Platzhaltern aus den Feldern, {query} u' +
      'nd {path}, z. B. „{name} hat {methods} Methoden“. Leer: „{name}: Treffer der Abfrage {quer' + 'y}“.",' + #10 +
      '            "x-description-en": "Message per hit with placeholders from the fields, {query' +
      '} and {path}, e.g. \"{name} has {methods} methods\". Empty: \"{name}: hit of the query {qu' + 'ery}\"."' + #10 +
      '          }' + #10 + '        }' + #10 + '      },' + #10 + '      "examples": [' + #10 + '        [' + #10 +
      '          {' + #10 + '            "name": "grosse-formulare",' + #10 +
      '            "query": "classes where inherits TForm and methods > 40",' + #10 + '            "failIfAny": true,' +
      #10 + '            "severity": "warning",' + #10 + '            "message": "{name} hat {methods} Methoden"' +
      #10 + '          }' + #10 + '        ]' + #10 + '      ],' + #10,
    '      "x-scope": "project",' + #10 + '      "x-page": "Allgemein",' + #10 +
      '      "x-control": "Bearbeiten im Fenster „Atlas-Abfrage“ („Als Regel speichern …“) oder i' + 'n atlas.json",' +
      #10 + '      "x-issue": "#1351"' + #10 + '    },' + #10 + '    "hotspots": {' + #10 + '      "type": "object",' +
      #10 + '      "description": "Hotspots: Units und Methoden, die oft geändert werden und zugleich k' +
      'omplex sind (Änderungen aus Git oder SVN im Zeitraum × kognitive Komplexität), mit Trend g' +
      'egenüber vor drei Monaten und Änderungskopplung (Units ohne uses-Kante, die oft zusammen g' +
      'eändert werden). Fenster „Atlas-Hotspots“, Bericht (AtlasServer --hotspots <Datei.html|.md' +
      '|.json>) und MCP-Werkzeug get_hotspots. Bibliotheks-Units und architecture.exclude zählen ' +
      'nicht; die Versionsverwaltung kommt aus vcs.provider.",' + #10,
    '      "x-description-en": "Hotspots: units and methods that are changed often and are comp' +
      'lex at the same time (changes from Git or SVN in the period × cognitive complexity), with ' +
      'trend compared to three months ago and change coupling (units without uses edge that are o' +
      'ften changed together). Window \"Atlas Hotspots\", report (AtlasServer --hotspots <file.ht' +
      'ml|.md|.json>) and MCP tool get_hotspots. Library units and architecture.exclude do not co' +
      'unt; the version control comes from vcs.provider.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "enabled": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 +
      '          "description": "Hauptschalter: false = kein Fenster, kein Menüeintrag, kein get_' +
      'hotspots; AtlasServer --hotspots endet mit Exitcode 3.",' + #10,
    '          "x-description-en": "Main switch: false = no window, no menu item, no get_hotspo' +
      'ts; AtlasServer --hotspots ends with exit code 3."' + #10 + '        },' + #10 + '        "months": {' + #10 +
      '          "type": "integer",' + #10 + '          "minimum": 1,' + #10 + '          "maximum": 60,' + #10 +
      '          "default": 12,' + #10 +
      '          "description": "Ausgewerteter Zeitraum in Monaten (Commits seit heute minus mont' + 'hs).",' + #10 +
      '          "x-description-en": "Analyzed period in months (commits since today minus months' + ')."' + #10 +
      '        },' + #10 + '        "coupling": {' + #10 + '          "type": "object",' + #10 +
      '          "additionalProperties": false,' + #10 +
      '          "description": "Änderungskopplung: Paare mit mindestens minCommits gemeinsamen C' +
      'ommits und einem Anteil von mindestens 70 % ohne uses-Kante zwischen ihnen; .pas/.dfm ders' +
      'elben Unit und Commits mit mehr als 50 Dateien zählen nicht.",' + #10,
    '          "x-description-en": "Change coupling: pairs with at least minCommits common comm' +
      'its and a share of at least 70 % without uses edge between them; .pas/.dfm of the same uni' +
      't and commits with more than 50 files do not count.",' + #10 + '          "properties": {' + #10 +
      '            "minCommits": {' + #10 + '              "type": "integer",' + #10 + '              "minimum": 2,' +
      #10 + '              "maximum": 1000,' + #10 + '              "default": 5,' + #10 +
      '              "description": "Mindestzahl gemeinsamer Commits eines Paares.",' + #10 +
      '              "x-description-en": "Minimum number of common commits of a pair."' + #10 + '            }' + #10 +
      '          }' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-page": "Hotspots",' + #10 +
      '      "x-control": "Kontrollkästchen, Zahl (1–60), Zahl (2–1000)",' + #10 + '      "x-issue": "#1354"' + #10,
    '    },' + #10 + '    "requestTimeoutMs": {' + #10 + '      "type": "integer",' + #10 + '      "minimum": 1000,' +
      #10 + '      "default": 10000,' + #10 +
      '      "description": "Zeitlimit für Anfragen in Millisekunden. Länger laufende Anfragen we' +
      'rden abgebrochen und im Log gemeldet.",' + #10 +
      '      "x-description-en": "Time limit for requests in milliseconds. Requests running longe' +
      'r are cancelled and reported in the log.",' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-page": "Robustheit",' + #10 +
      '      "x-control": "Zahlenfeld (ms)",' + #10 + '      "x-issue": "#283"' + #10 + '    },' + #10 +
      '    "server": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Absturzfälle des Servers: Stürzt eine Anfrage mit einer unerwarteten' +
      ' Ausnahme ab oder bricht der Watchdog sie ab, sichert der Server einen nachstellbaren Fall' +
      ' unter %LOCALAPPDATA%\\Atlas\\crash (Anfrage, Schnappschuss der Datei, Einstellungen ohne ' +
      'Zugangsdaten, Aufrufstapel, wiederholen.cmd; höchstens 20). Kein Netzzugriff.",' + #10 +
      '      "x-description-en": "Crash cases of the server: if a request crashes with an unexpec' +
      'ted exception or the watchdog cancels it, the server saves a reproducible case under %LOCA' +
      'LAPPDATA%\\Atlas\\crash (request, snapshot of the file, settings without credentials, call' +
      ' stack, wiederholen.cmd; at most 20). No network access.",' + #10 + '      "additionalProperties": false,' +
      #10 + '      "properties": {' + #10 + '        "crashCases": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Absturzfälle sichern und im Plugin melden (Fall öffnen, Issue an' +
      'legen). AtlasServer --replay <anfrage.json> stellt einen Fall nach.",' + #10 +
      '          "x-description-en": "Save crash cases and report them in the plugin (open case, ' +
      'create issue). AtlasServer --replay <request.json> reproduces a case."' + #10 + '        },' + #10 +
      '        "crashSkip": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Sicherheitsnetz, zusätzlich zur Behebung: Eine Anfrage, die an d' +
      'erselben unveränderten Datei zweimal abgestürzt ist, beantwortet der Server mit „Übersprun' +
      'gen nach Absturz“, bis sich die Datei ändert oder „Erneut versuchen“ gewählt wird. Statusl' +
      'eiste und Prüffenster zeigen das an.",' + #10,
    '          "x-description-en": "Safety net, in addition to the fix: the server answers a re' +
      'quest that crashed twice on the same unchanged file with \"Skipped after crash\" until the' +
      ' file changes or \"Try again\" is chosen. Status bar and check window show this."' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "general",' + #10 +
      '      "x-page": "Robustheit",' + #10 + '      "x-control": "Kontrollkästchen",' + #10 +
      '      "x-issue": "#1355"' + #10 + '    },' + #10 + '    "diagnostics": {' + #10 + '      "type": "object",' +
      #10 + '      "description": "Anonymisiertes Diagnoselog des Servers (je Anfrage Dauer, Ergebnis u' +
      'nd Grundcode, je Lauf Start und Ende mit Grund). Es enthält keine Pfade, keine Projekt-, U' +
      'nit- oder Bezeichnernamen und keinen Quelltext und lässt sich über „Diagnoselog exportiere' +
      'n“ weitergeben.",' + #10,
    '      "x-description-en": "Anonymized diagnostic log of the server (per request duration, ' +
      'result and reason code, per run start and end with reason). It contains no paths, no proje' +
      'ct, unit or identifier names and no source code and can be passed on via \"Export diagnost' + 'ic log\".",' +
      #10 + '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "log": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Anonymisiertes Diagnoselog schreiben (%LOCALAPPDATA%\\Atlas\\Log' + 's\\Diagnose).",' +
      #10 + '          "x-description-en": "Write the anonymized diagnostic log (%LOCALAPPDATA%\\Atlas\' +
      '\Logs\\Diagnose)."' + #10 + '        },' + #10 + '        "logDays": {' + #10 + '          "type": "integer",' +
      #10 + '          "minimum": 1,' + #10 + '          "maximum": 365,' + #10 + '          "default": 7,' + #10,
    '          "description": "Aufbewahrung des Diagnoselogs in Tagen.",' + #10 +
      '          "x-description-en": "Retention of the diagnostic log in days."' + #10 + '        },' + #10 +
      '        "logMapFile": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Zuordnung Kurz-ID (doc#4) → Pfad lokal speichern, nur für die ei' +
      'gene Analyse. Der Export nimmt sie nie mit.",' + #10 +
      '          "x-description-en": "Store the mapping short id (doc#4) → path locally, only for' +
      ' your own analysis. The export never includes it."' + #10 + '        },' + #10 + '        "usesCycleLive": {' +
      #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Zirkuläre Unit-Referenz schon beim Tippen melden (Regel uses-cyc' +
      'le): Ein Zyklus, in dem jede Kante im interface-Teil liegt, ist ein Fehler am auslösenden ' +
      'uses-Eintrag mit dem kürzesten Pfad; jede Unit im Hover springt an ihren uses-Eintrag. Sch' +
      'nellkorrektur „In implementation-uses verschieben“, wenn kein Bezeichner der Unit im inter' +
      'face-Teil gebraucht wird, sonst Sprung zu diesen Bezeichnern und „Graph zeigen“. Berücksic' +
      'htigt den ungespeicherten Stand offener Units. false: keine Meldung im Editor; die projekt' +
      'weite Prüfung (--check, find_unused_code) bleibt.",' + #10,
    '          "x-description-en": "Report circular unit references while typing (rule uses-cyc' +
      'le): a cycle in which every edge lies in the interface part is an error at the triggering ' +
      'uses entry with the shortest path; each unit in the hover jumps to its uses entry. Quick f' +
      'ix \"Move to implementation uses\" if no identifier of the unit is needed in the interface' +
      ' part, otherwise jump to these identifiers and \"Show graph\". Takes the unsaved state of ' +
      'open units into account. false: no message in the editor; the project-wide check (--check,' +
      ' find_unused_code) stays.",' + #10 + '          "x-scope": "project",' + #10 +
      '          "x-page": "Prüfregeln",' + #10 + '          "x-control": "Kontrollkästchen",' + #10 +
      '          "x-issue": "#896"' + #10 + '        },' + #10 + '        "usesCycleImplementation": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10,
    '          "description": "Im Editor auch Zyklen mit mindestens einer implementation-Kante ' +
      'melden, als Hinweis (der Compiler erlaubt sie). Braucht usesCycleLive.",' + #10 +
      '          "x-description-en": "In the editor also report cycles with at least one implemen' +
      'tation edge, as a hint (the compiler allows them). Requires usesCycleLive.",' + #10 +
      '          "x-scope": "project",' + #10 + '          "x-page": "Prüfregeln",' + #10 +
      '          "x-control": "Kontrollkästchen",' + #10 + '          "x-issue": "#896"' + #10 + '        },' + #10 +
      '        "librarySources": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' + #10,
    '          "description": "Auch Units der Delphi-Installation ($(BDS), also RTL und VCL) un' +
      'd der Bibliothekspfade prüfen, die zu keinem Projekt der Gruppe gehören, etwa nach Strg+Kl' +
      'ick in System.Classes.pas. false: In solchen Dateien zeigt der Editor keine Befunde der Pr' +
      'üfregeln; Dateien im Projektordner, DCCReference-Units und Units der Projekt-Suchpfade wer' +
      'den immer geprüft.",' + #10 +
      '          "x-description-en": "Also check units of the Delphi installation ($(BDS), i.e. R' +
      'TL and VCL) and the library paths that belong to no project of the group, for example afte' +
      'r Ctrl+click into System.Classes.pas. false: in such files the editor shows no findings of' +
      ' the rules; files in the project folder, DCCReference units and units of the project searc' +
      'h paths are always checked."' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-page": "Robustheit",' + #10,
    '      "x-control": "Kontrollkästchen, Zahlenfeld (Tage)",' + #10 + '      "x-issue": "#647"' + #10 + '    },' +
      #10 + '    "highlight": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Zusammengehörige Schlüsselwörter hervorheben, wenn der Cursor auf ei' + 'nem steht.",' +
      #10 + '      "x-description-en": "Highlight related keywords when the cursor is on one of them.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "blockPairs": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Blockpaare (begin/end, try/finally/except/end, case/of/end, repe' +
      'at/until, if/then/else, Typen) und Routinen hervorheben.",' + #10 +
      '          "x-description-en": "Highlight block pairs (begin/end, try/finally/except/end, c' +
      'ase/of/end, repeat/until, if/then/else, types) and routines."' + #10 + '        },' + #10 +
      '        "directives": {' + #10,
    '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} sowie {$REGION}/{$ENDRE' +
      'GION} hervorheben.",' + #10 +
      '          "x-description-en": "Highlight matching {$IF…}/{$ELSE}/{$ENDIF} as well as {$REG' +
      'ION}/{$ENDREGION}."' + #10 + '        },' + #10 + '        "exitPoints": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Ausstiegspunkte der Routine sowie Kopf und Ende der Schleife bei' +
      ' Break/Continue hervorheben.",' + #10 +
      '          "x-description-en": "Highlight exit points of the routine as well as head and en' +
      'd of the loop for Break/Continue."' + #10 + '        },' + #10 + '        "exitKeywords": {' + #10 +
      '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [' + #10 + '            "Exit",' + #10,
    '            "raise",' + #10 + '            "Abort",' + #10 + '            "Halt"' + #10 + '          ],' + #10 +
      '          "description": "Was als Ausstiegspunkt gilt; eigene Routinen, die immer eine Exc' +
      'eption auslösen, lassen sich ergänzen.",' + #10 +
      '          "x-description-en": "What counts as an exit point; your own routines that always' +
      ' raise an exception can be added."' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' +
      #10 + '      "x-area": "highlighting",' + #10 + '      "x-page": "Editor",' + #10 +
      '      "x-control": "Kontrollkästchen, Liste",' + #10 + '      "x-issue": "#307"' + #10 + '    },' + #10 +
      '    "inlayHints": {' + #10 + '      "type": "object",' + #10 + '      "description": "Inlay Hints im Editor.",' +
      #10 + '      "x-description-en": "Inlay hints in the editor.",' + #10 + '      "additionalProperties": false,' +
      #10 + '      "properties": {' + #10 + '        "parameterNames": {' + #10,
    '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Parameternamen vor den Argumenten eines Aufrufs.",' + #10 +
      '          "x-description-en": "Parameter names before the arguments of a call."' + #10 + '        },' + #10 +
      '        "inferredTypes": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Abgeleiteter Typ hinter var X := …, const X = … und for var X in' +
      ' … (im Plugin als Typmarke am Zeilenende).",' + #10 +
      '          "x-description-en": "Inferred type after var X := …, const X = … and for var X i' +
      'n … (in the plugin as a type label at the end of the line)."' + #10 + '        },' + #10 +
      '        "endMarkers": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Hinter dem end langer Blöcke anzeigen, was dort endet.",' + #10,
    '          "x-description-en": "Show after the end of long blocks what ends there."' + #10 + '        },' + #10 +
      '        "endMarkerMinLines": {' + #10 + '          "type": "integer",' + #10 + '          "minimum": 1,' + #10 +
      '          "default": 20,' + #10 +
      '          "description": "Mindestlänge eines Blocks in Zeilen für eine Endmarkierung.",' + #10 +
      '          "x-description-en": "Minimum length of a block in lines for an end marker."' + #10 + '        },' +
      #10 + '        "includeDefines": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "Hinter {$I datei.inc} die Symbole, die die Include-Datei setzt u' +
      'nd die eine Bedingung der Unit prüft (\"definiert COMPLIB_VCL\").",' + #10 +
      '          "x-description-en": "After {$I file.inc} the symbols that the include file sets ' +
      'and that a condition of the unit checks (\"defines COMPLIB_VCL\")."' + #10 + '        },' + #10,
    '        "controlChars": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Hinter Steuerzeichen wie ^C oder ^[ im Wert einer Konstanten ihr' +
      ' Code (#3, #27).",' + #10 +
      '          "x-description-en": "After control characters such as ^C or ^[ in the value of a' +
      ' constant their code (#3, #27)."' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' +
      #10 + '      "x-area": "editor",' + #10 + '      "x-page": "Editor",' + #10 +
      '      "x-control": "Kontrollkästchen, Zahlenfeld",' + #10 + '      "x-issue": "#35, #453, #860, #862"' + #10 +
      '    },' + #10 + '    "codeLens": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Code Lens im Editor.",' + #10 + '      "x-description-en": "Code lens in the editor.",' +
      #10 + '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "metrics": {' +
      #10 + '          "type": "boolean",' + #10,
    '          "default": true,' + #10 +
      '          "description": "Kennzahlen über jeder Methode: Länge in Codezeilen, Verschachtel' +
      'ungstiefe, zyklomatische und kognitive Komplexität, Parameteranzahl. Die Grenzwerte stehen' +
      ' bei den Regeln metric-* unter \"max\".",' + #10 +
      '          "x-description-en": "Metrics above every method: length in lines of code, nestin' +
      'g depth, cyclomatic and cognitive complexity, number of parameters. The limits are set wit' +
      'h the rules metric-* under \"max\"."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "editor",' + #10 + '      "x-page": "Editor",' + #10 +
      '      "x-control": "Kontrollkästchen",' + #10 + '      "x-issue": "#66"' + #10 + '    },' + #10 +
      '    "smartIndent": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Einrückung beim Tippen (#1827): Nach Enter rechnet Atlas mit derselb' +
      'en Blocklogik wie format.reindent aus, wo die Schreibmarke stehen soll. Atlas setzt kein e' +
      'nd; ein, das macht der Blockabschluss der IDE; geändert werden nur Leerraum und beim Strin' +
      'g das Hochkomma und +. Breite einer Ebene und Tabulatoren nach format bzw. .editorconfig."' + ',' + #10 +
      '      "x-description-en": "Indentation while typing (#1827): after Enter Atlas computes wh' +
      'ere the cursor belongs, with the same block logic as format.reindent. Atlas never inserts ' +
      'end; (the IDE''s block completion does that); only whitespace changes, and for a string the' +
      ' quote and +. Width of one level and tabs follow format or .editorconfig.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "enabled": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Hauptschalter: false = keiner der Teile wirkt, die IDE rückt wie' + ' gewohnt ein.",' +
      #10 + '          "x-description-en": "Main switch: false = none of the parts is active, the IDE i' +
      'ndents as usual."' + #10 + '        },' + #10 + '        "afterEnter": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Neue Zeile nach der Blockstruktur einrücken: eine Ebene tiefer h' +
      'inter then, else, do, begin, try, repeat, case-Marken, var/type/const und Sichtbarkeiten, ' +
      'nach der einzelnen Anweisung hinter then/do zurück, in einer offenen Klammer unter dem ers' + 'ten Argument.",' +
      #10,
    '          "x-description-en": "Indent the new line by the block structure: one level deepe' +
      'r after then, else, do, begin, try, repeat, case labels, var/type/const and visibilities, ' +
      'back after the single statement behind then/do, inside an open parenthesis under the first' + ' argument.",' +
      #10 + '          "x-issue": "#1828"' + #10 + '        },' + #10 + '        "outdentClosers": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Beginnt die Zeile vor Enter mit end, until, finally, except oder' +
      ' else, rückt Atlas sie auf die Spalte ihres Gegenstücks (begin, repeat, try, if).",' + #10 +
      '          "x-description-en": "If the line before Enter starts with end, until, finally, e' +
      'xcept or else, Atlas moves it to the column of its counterpart (begin, repeat, try, if).",' + #10 +
      '          "x-issue": "#1829"' + #10 + '        },' + #10 + '        "splitStrings": {' + #10,
    '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Enter in einem String schließt ihn mit '' + und öffnet ihn in der' +
      ' neuen Zeile wieder, statt einen offenen String (E2052) zu hinterlassen. Nicht in mehrzeil' +
      'igen Strings ('''''').",' + #10 +
      '          "x-description-en": "Enter inside a string closes it with '' + and reopens it on ' +
      'the new line instead of leaving an unterminated string (E2052). Not in multiline strings (' + ''''''').",' +
      #10 + '          "x-issue": "#1831"' + #10 + '        },' + #10 + '        "splitStringsIndent": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["indent", "align"],' + #10 +
      '          "default": "indent",' + #10 +
      '          "description": "Fortsetzungszeile eines getrennten Strings: indent = eine Ebene ' +
      'tiefer als die Anweisung; align = unter dem ersten Argument der offenen Klammer, ohne Klam' +
      'mer unter dem ersten Wert hinter :=.",' + #10,
    '          "x-description-en": "Continuation line of a split string: indent = one level dee' +
      'per than the statement; align = under the first argument of the open parenthesis, without ' +
      'parenthesis under the first value after :=.",' + #10 + '          "x-control": "Auswahl",' + #10 +
      '          "x-issue": "#1831"' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "codeActions",' + #10 + '      "x-page": "Eingabehilfen",' + #10 +
      '      "x-control": "Kontrollkästchen, Auswahl",' + #10 + '      "x-issue": "#1827, #1828, #1829, #1831"' + #10 +
      '    },' + #10 + '    "classCompletion": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Klassenvervollständigung (#1834): Kommentar über dem Abschnitt einer' +
      ' Klasse im implementation-Teil, Reihenfolge und Inhalt neuer Methodenrümpfe aus der Aktion' +
      ' „Fehlende Methodenrümpfe anlegen“, /impl und dem Ordnen der Methoden (editor.methodPlacem' +
      'ent im Plugin).",' + #10 +
      '      "x-description-en": "Class completion (#1834): comment above a class section in the ' +
      'implementation part, order and content of new method bodies from the action \"Create missi' +
      'ng method bodies\", /impl and method ordering (editor.methodPlacement in the plugin).",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "typeComment": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "brace",' + #10 +
      '            "line",' + #10 + '            "summary",' + #10 + '            "region",' + #10 +
      '            "off"' + #10 + '          ],' + #10,
    '          "default": "brace",' + #10 +
      '          "description": "Kommentar über dem ersten Rumpf einer Klasse: brace = { TFoo } w' +
      'ie die IDE, line = Trennlinie mit // TFoo, summary = { TFoo: erster Satz der XML-Doku }, r' +
      'egion = {$REGION ''TFoo''} … {$ENDREGION} um alle Rümpfe, off = keiner. Ein vorhandener Komm' +
      'entar wird erkannt und nicht verdoppelt; beim Ordnen wandert er mit der Klasse.",' + #10 +
      '          "x-description-en": "Comment above the first body of a class: brace = { TFoo } l' +
      'ike the IDE, line = separator line with // TFoo, summary = { TFoo: first sentence of the X' +
      'ML doc }, region = {$REGION ''TFoo''} … {$ENDREGION} around all bodies, off = none. An exist' +
      'ing comment is recognized and not duplicated; when ordering it moves with the class.",' + #10 +
      '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#1835"' + #10 + '        },' + #10 +
      '        "lifecycleFirst": {' + #10 + '          "type": "boolean",' + #10,
    '          "default": true,' + #10 +
      '          "description": "Konstruktoren und Destruktor (auch class constructor/destructor,' +
      ' AfterConstruction, BeforeDestruction) stehen auch bei editor.methodPlacement = declaratio' +
      'n oder alphabetical und in neuen Rümpfen vor den übrigen ihrer Klasse. Bei grouped stehen ' +
      'sie immer vorn.",' + #10 +
      '          "x-description-en": "Constructors and destructor (also class constructor/destruc' +
      'tor, AfterConstruction, BeforeDestruction) come before the other bodies of their class als' +
      'o with editor.methodPlacement = declaration or alphabetical and in new bodies. With groupe' +
      'd they always come first.",' + #10 + '          "x-issue": "#1836"' + #10 + '        },' + #10 +
      '        "bodyStubs": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Neue Rümpfe vorbefüllen: override mit inherited (Funktionen mit ' +
      'Result := inherited …), Destruktor mit inherited am Ende, Getter Result := FName und Sette' +
      'r FName := AValue, wenn ein Feld FName gleichen Typs existiert. false = leere Rümpfe.",' + #10 +
      '          "x-description-en": "Prefill new bodies: override with inherited (functions with' +
      ' Result := inherited …), destructor with inherited at the end, getter Result := FName and ' +
      'setter FName := AValue when a field FName of the same type exists. false = empty bodies.",' + #10 +
      '          "x-issue": "#1837"' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "codeActions",' + #10 + '      "x-page": "Eingabehilfen",' + #10 +
      '      "x-control": "Auswahl, Kontrollkästchen",' + #10 + '      "x-issue": "#1834, #1835, #1836, #1837"' + #10 +
      '    },' + #10 + '    "references": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Treffersicherheit von Verwendungen, Aufrufhierarchie und Umbenennen:' +
      ' Neben den sicheren (eindeutig aufgelösten) Stellen erscheinen erschlossene mit Grund, etw' +
      'a Aufrufe über ein Interface oder in einem inaktiven {$IFDEF}-Zweig. Umbenennen ändert nur' +
      ' sichere Stellen und listet die erschlossenen.",' + #10 +
      '      "x-description-en": "Accuracy of usages, call hierarchy and rename: besides the cert' +
      'ain (uniquely resolved) places, inferred ones appear with a reason, for example calls via ' +
      'an interface or in an inactive {$IFDEF} branch. Rename only changes certain places and lis' +
      'ts the inferred ones.",' + #10 + '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 +
      '        "inferred": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Erschlossene Treffer zeigen: über ein Interface, das die Klasse ' +
      'umsetzt, über die überschriebene Methode eines Vorfahren, nicht eindeutige Überladungen, g' +
      'leicher Name mit unbekanntem Typ (with, unbekannter Ausdruck) und Stellen in inaktiven Zwe' +
      'igen; aus = nur sichere Treffer wie bisher.",' + #10 +
      '          "x-description-en": "Show inferred hits: via an interface the class implements, ' +
      'via the overridden method of an ancestor, ambiguous overloads, same name with unknown type' +
      ' (with, unknown expression) and places in inactive branches; off = only certain hits as be' + 'fore."' + #10 +
      '        },' + #10 + '        "textMatches": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10 +
      '          "description": "Auch den Namen in String-Literalen als erschlossen melden, etwa ' +
      'für RTTI oder MethodAddress(''Speichern'').",' + #10,
    '          "x-description-en": "Also report the name in string literals as inferred, for ex' +
      'ample for RTTI or MethodAddress(''Save'')."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "editor",' + #10 + '      "x-page": "Befehle",' + #10 +
      '      "x-control": "Kontrollkästchen",' + #10 + '      "x-issue": "#1119"' + #10 + '    },' + #10 +
      '    "navigation": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Navigation über den Code: Weg zwischen zwei Symbolen oder Units über' +
      ' Aufrufe, Felder, Interfaces, Vererbung und uses (Plugin-Befehl „Weg zwischen Symbolen…“, ' +
      'MCP-Werkzeug find_path) und Auswirkungsanalyse: Was ist betroffen, wenn ich ein Symbol änd' +
      'ere? Aufrufer, Verweise, Overrides, Interface-Umsetzungen und Formularbindungen nach Ebene' +
      'n, dazu die betroffenen Tests (Plugin-Befehl „Auswirkungen anzeigen“, MCP-Werkzeug get_imp' + 'act).",' + #10,
    '      "x-description-en": "Navigation through the code: path between two symbols or units ' +
      'via calls, fields, interfaces, inheritance and uses (plugin command \"Path between symbols' +
      '…\", MCP tool find_path) and impact analysis: what is affected if I change a symbol? Calle' +
      'rs, references, overrides, interface implementations and form bindings by level, plus the ' +
      'affected tests (plugin command \"Show impact\", MCP tool get_impact).",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "symbolPath": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Befehl „Weg zwischen Symbolen…“ im Plugin mit Einträgen im Menü ' +
      'Atlas, im Kontextmenü des Editors („Weg von hier nach…“) und in der Befehlspalette; aus = ' +
      'Befehl und Menüeinträge fehlen. Das MCP-Werkzeug schaltet mcp.disabledTools (find_path) ab' + '.",' + #10,
    '          "x-description-en": "Command \"Path between symbols…\" in the plugin with entrie' +
      's in the Atlas menu, in the editor context menu (\"Path from here to…\") and in the comman' +
      'd palette; off = command and menu items are missing. The MCP tool is turned off by mcp.dis' +
      'abledTools (find_path)."' + #10 + '        },' + #10 + '        "impact": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Befehl „Auswirkungen anzeigen“ im Plugin mit Einträgen im Kontex' +
      'tmenü, im Menü Atlas und in der Befehlspalette; aus = Befehl und Menüeinträge fehlen. Das ' +
      'MCP-Werkzeug schaltet mcp.disabledTools (get_impact) ab.",' + #10 +
      '          "x-description-en": "Command \"Show impact\" in the plugin with entries in the c' +
      'ontext menu, the Atlas menu and the command palette; off = command and menu items are miss' +
      'ing. The MCP tool is turned off by mcp.disabledTools (get_impact)."' + #10,
    '        },' + #10 + '        "impactDepth": {' + #10 + '          "type": "integer",' + #10 +
      '          "default": 2,' + #10 + '          "minimum": 1,' + #10 + '          "maximum": 5,' + #10 +
      '          "description": "Vorgabe der Tiefe der Auswirkungsanalyse in IDE und MCP: 1 = nur' +
      ' direkte Aufrufer und Verweise, jede weitere Ebene geht einen Schritt weiter zurück.",' + #10 +
      '          "x-description-en": "Default depth of the impact analysis in IDE and MCP: 1 = on' +
      'ly direct callers and references, each further level goes one step further back."' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "editor",' + #10 +
      '      "x-page": "Befehle",' + #10 + '      "x-control": "Kontrollkästchen, Zahlenfeld",' + #10 +
      '      "x-issue": "#1117, #1120"' + #10 + '    },' + #10 + '    "hints": {' + #10 + '      "type": "object",' +
      #10,
    '      "description": "Anzeige von XMLDoc-Kommentaren (///) und Begründungen (// WHY: …, #1' +
      '123) im Hover-Tooltip und im Detailpanel der Vervollständigung des IDE-Plugins. Der Server' +
      ' bereitet die Doku immer vollständig auf; die Werte steuern nur die Anzeige. Ohne Angabe g' +
      'elten die Werte aus Tools › Optionen › Drittanbieter › Atlas.",' + #10 +
      '      "x-description-en": "Display of XMLDoc comments (///) and rationales (// WHY: …, #11' +
      '23) in the hover tooltip and in the detail panel of the completion of the IDE plugin. The ' +
      'server always prepares the documentation completely; the values only control the display. ' +
      'Without a value the values from Tools › Options › Third Party › Atlas apply.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "xmlDocExpand": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "collapsed",' + #10,
    '            "last",' + #10 + '            "expanded"' + #10 + '          ],' + #10 +
      '          "default": "last",' + #10 +
      '          "description": "XMLDoc beim Öffnen (#770): \"collapsed\" zeigt nur Deklaration, ' +
      'Summary und „Mehr anzeigen“, \"last\" wie zuletzt in dieser Sitzung (getrennt für Tooltip ' +
      'und Detailpanel, nach dem Neustart zugeklappt), \"expanded\" alle Abschnitte mit Überschri' +
      'ft (Parameter, Rückgabe, Ausnahmen, Hinweise, Beispiel …).",' + #10 +
      '          "x-description-en": "XMLDoc when opening (#770): \"collapsed\" shows only declar' +
      'ation, summary and \"Show more\", \"last\" as last time in this session (separately for to' +
      'oltip and detail panel, collapsed after restart), \"expanded\" all sections with heading (' +
      'parameters, return value, exceptions, remarks, example …).",' + #10 + '          "x-plugin": "XmlDocExpand"' +
      #10 + '        },' + #10 + '        "xmlDocFull": {' + #10 + '          "type": "boolean",' + #10,
    '          "description": "Veraltet (#770), ersetzt durch xmlDocExpand: true wirkt wie \"ex' +
      'panded\", false wie \"collapsed\", solange xmlDocExpand fehlt.",' + #10 +
      '          "x-description-en": "Deprecated (#770), replaced by xmlDocExpand: true acts like' +
      ' \"expanded\", false like \"collapsed\" as long as xmlDocExpand is missing."' + #10 + '        },' + #10 +
      '        "xmlDocMaxLines": {' + #10 + '          "type": "integer",' + #10 + '          "minimum": 0,' + #10 +
      '          "maximum": 50,' + #10 + '          "default": 0,' + #10 +
      '          "description": "Höchstzahl der Doku-Zeilen, bevor der Inhalt mit dem Mausrad scr' +
      'ollt (0 = unbegrenzt, nur durch Bildschirm bzw. Popup begrenzt).",' + #10 +
      '          "x-description-en": "Maximum number of documentation lines before the content sc' +
      'rolls with the mouse wheel (0 = unlimited, only limited by screen or popup)."' + #10 + '        },' + #10 +
      '        "publishedMembers": {' + #10,
    '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Hover über einer Komponentenklasse (#110): published-Properties ' +
      'und Ereignisse samt geerbter in Tabellen mit Typ, Vorgabe (default, implizit, nodefault, s' +
      'tored) und deklarierender Klasse, Filter für geerbte und nur mit Vorgabe, die Standard-Pro' +
      'perty einer Array-Property und „Liste kopieren“ mit Strg+C. Aus: nur Deklaration, Doku und' + ' Vererbung.",' +
      #10 + '          "x-description-en": "Hover over a component class (#110): published properties a' +
      'nd events including inherited ones in tables with type, default (default, implicit, nodefa' +
      'ult, stored) and declaring class, filters for inherited and only with default, the default' +
      ' property of an array property and \"Copy list\" with Ctrl+C. Off: only declaration, docum' +
      'entation and inheritance.",' + #10 + '          "x-issue": "#110"' + #10 + '        },' + #10,
    '        "rationale": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Begründungen im Hover und in get_declaration (#1123): Kommentare' +
      ' wie // WHY: …, // HACK: … oder { NOTE: … } direkt über einer Deklaration (höchstens eine ' +
      'Leerzeile dazwischen) und im Rumpf einer Routine erscheinen im Abschnitt „Begründung“ unte' +
      'r Deklaration und XMLDoc, ab vier Einträgen hinter „Mehr anzeigen“. ADR-0007 öffnet die Da' +
      'tei aus adrFolder, #312 das Issue (Tracker der Willkommensseite), URLs den Browser. Aus: A' +
      'tlas zeigt keine Begründungen; get_rationale bleibt über mcp.disabledTools abschaltbar.",' + #10,
    '          "x-description-en": "Rationales in hover and in get_declaration (#1123): comment' +
      's such as // WHY: …, // HACK: … or { NOTE: … } directly above a declaration (at most one b' +
      'lank line in between) and in the body of a routine appear in the section \"Rationale\" bel' +
      'ow declaration and XMLDoc, from four entries behind \"Show more\". ADR-0007 opens the file' +
      ' from adrFolder, #312 the issue (tracker of the welcome page), URLs the browser. Off: Atla' +
      's shows no rationales; get_rationale stays switchable via mcp.disabledTools.",' + #10 +
      '          "x-issue": "#1123"' + #10 + '        },' + #10 + '        "rationaleMarkers": {' + #10 +
      '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [' + #10 + '            "NOTE",' + #10 + '            "WHY",' + #10 +
      '            "HACK",' + #10 + '            "IMPORTANT",' + #10 + '            "RATIONALE"' + #10,
    '          ],' + #10 +
      '          "description": "Marken, die als Begründung gelten (#1123), Groß-/Kleinschreibung' +
      ' egal; die Liste ersetzt die Vorgabe. Nach der Marke folgt ein Doppelpunkt; ohne Doppelpun' +
      'kt zählt sie nur in Großbuchstaben (// NOTE das …). TODO und FIXME bleiben bei der TODO-Üb' +
      'ersicht (todo-comment) und erscheinen hier nie.",' + #10 +
      '          "x-description-en": "Markers that count as rationale (#1123), case-insensitive; ' +
      'the list replaces the default. The marker is followed by a colon; without a colon it only ' +
      'counts in capitals (// NOTE this …). TODO and FIXME stay with the TODO overview (todo-comm' +
      'ent) and never appear here.",' + #10 + '          "x-issue": "#1123"' + #10 + '        },' + #10 +
      '        "adrFolder": {' + #10 + '          "type": "string",' + #10 + '          "default": "docs/adr",' + #10,
    '          "description": "Ordner der Architekturentscheidungen (#1123), relativ zum Projek' +
      't (Ordner der atlas.json): ADR-0007 bzw. ADR 7 in einer Begründung öffnet die Datei, deren' +
      ' Name mit 0007 (auch ADR-0007) beginnt, z. B. docs/adr/0007-threads.md. Ohne passende Date' +
      'i ist der Verweis nicht anklickbar.",' + #10 +
      '          "x-description-en": "Folder of the architecture decisions (#1123), relative to t' +
      'he project (folder of atlas.json): ADR-0007 or ADR 7 in a rationale opens the file whose n' +
      'ame starts with 0007 (also ADR-0007), e.g. docs/adr/0007-threads.md. Without a matching fi' +
      'le the reference is not clickable.",' + #10 + '          "x-issue": "#1123"' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "editor",' + #10 +
      '      "x-page": "Hints",' + #10 + '      "x-control": "Kontrollkästchen, Zahlenfeld",' + #10 +
      '      "x-issue": "#654"' + #10 + '    },' + #10,
    '    "directives": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Hilfen in Compiler-Direktiven: Vervollständigung und Hover für Direk' +
      'tiven wie {$R+} oder {$WARN …} und für bedingte Symbole in {$IFDEF}, {$IFNDEF}, {$IF Defin' +
      'ed(…)}, {$DEFINE} und {$UNDEF}.",' + #10 +
      '      "x-description-en": "Help in compiler directives: completion and hover for directive' +
      's such as {$R+} or {$WARN …} and for conditional symbols in {$IFDEF}, {$IFNDEF}, {$IF Defi' +
      'ned(…)}, {$DEFINE} and {$UNDEF}.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "completion": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "In {$ die Direktivennamen, nach {$WARN die Warnungsbezeichner un' +
      'd nach {$IFDEF, {$IFNDEF, {$DEFINE, {$UNDEF und in Defined( die bedingten Symbole vorschla' +
      'gen, jeweils mit Herkunft (Konfiguration, Plattform, Compiler-Vorgabe, {$DEFINE} mit Zeile' + ').",' + #10 +
      '          "x-description-en": "Suggest the directive names in {$, the warning identifiers ' +
      'after {$WARN and the conditional symbols after {$IFDEF, {$IFNDEF, {$DEFINE, {$UNDEF and in' +
      ' Defined(, each with origin (configuration, platform, compiler default, {$DEFINE} with lin' + 'e).",' + #10 +
      '          "x-issue": "#102"' + #10 + '        },' + #10 + '        "hover": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Hover über Schaltern wie {$R+} erklärt die Direktive mit DocWiki' +
      '-Link; über {$IFDEF X} und Co. nennt er, ob X an dieser Stelle aktiv ist und wo es definie' +
      'rt wird (Projekt, Konfiguration und Plattform aus der .dproj, Compiler-Vorgabe, {$DEFINE} ' +
      'mit Datei und Zeile, auch aus Include-Dateien). Über {$IF}, {$ELSEIF} und {$IFOPT} nennt e' +
      'r den Wert der Bedingung mit Teilwerten und Herkunft (SizeOf nach Zielplattform, RTLVersio' +
      'n111 nach Delphi-Version, Declared aus dem Index, Schalter aus der .dproj oder einem {$R-}' +
      ' davor), über {$PUSHOPT}/{$POPOPT} das Gegenstück (#847).",' + #10,
    '          "x-description-en": "Hover over switches such as {$R+} explains the directive wi' +
      'th a DocWiki link; over {$IFDEF X} and similar it tells whether X is active at this place ' +
      'and where it is defined (project, configuration and platform from the .dproj, compiler def' +
      'ault, {$DEFINE} with file and line, also from include files). Over {$IF}, {$ELSEIF} and {$' +
      'IFOPT} it gives the value of the condition with partial values and origin (SizeOf by targe' +
      't platform, RTLVersion111 by Delphi version, Declared from the index, switches from the .d' +
      'proj or a {$R-} before), over {$PUSHOPT}/{$POPOPT} the counterpart (#847).",' + #10 +
      '          "x-issue": "#102"' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "editor",' + #10 + '      "x-page": "Editor",' + #10 + '      "x-control": "Kontrollkästchen",' +
      #10 + '      "x-issue": "#102"' + #10 + '    },' + #10 + '    "stringLiteral": {' + #10,
    '      "type": "object",' + #10 +
      '      "description": "Code-Aktionen „Als String-Literal“ und „Als Klartext kopieren“.",' + #10 +
      '      "x-description-en": "Code actions \"As string literal\" and \"Copy as plain text\"."' + ',' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "style": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": ["auto", "multiline", "concat"],' + #10 +
      '          "default": "auto",' + #10 +
      '          "description": "auto: mehrzeiliger String mit '''''', wenn die Delphi-Version ihn k' +
      'ennt (ab Delphi 12), sonst Verkettung.",' + #10 +
      '          "x-description-en": "auto: multiline string with '''''' if the Delphi version suppo' +
      'rts it (Delphi 12 and later), otherwise concatenation."' + #10 + '        },' + #10 + '        "lineBreak": {' +
      #10 + '          "type": "string",' + #10 +
      '          "enum": ["sLineBreak", "#13#10", "#10", "space", "none"],' + #10,
    '          "default": "sLineBreak",' + #10 +
      '          "description": "Was bei Verkettung zwischen den Zeilen steht; space z. B. für SQ' +
      'L, das einzeilig ankommen soll.",' + #10 +
      '          "x-description-en": "What goes between the lines with concatenation; space e.g. ' +
      'for SQL that should arrive on one line."' + #10 + '        },' + #10 + '        "maxLineLength": {' + #10 +
      '          "type": "integer",' + #10 + '          "minimum": 0,' + #10 + '          "default": 0,' + #10 +
      '          "description": "Bei Verkettung lange Zeilen zusätzlich umbrechen (0 = nicht umbr' + 'echen).",' + #10 +
      '          "x-description-en": "With concatenation also wrap long lines (0 = do not wrap)."' + #10 + '        }' +
      #10 + '      },' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Editor",' + #10 +
      '      "x-control": "Auswahl, Zahlenfeld",' + #10 + '      "x-issue": "#312"' + #10 + '    },' + #10 +
      '    "memberOrder": {' + #10,
    '      "type": "object",' + #10 +
      '      "description": "Code-Aktion „Klassenmitglieder ordnen“: Reihenfolge der Sichtbarkeit' +
      'sabschnitte und der Mitglieder darin.",' + #10 +
      '      "x-description-en": "Code action \"Order class members\": order of the visibility se' +
      'ctions and of the members in them.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "sections": {' + #10 + '          "type": "array",' + #10 +
      '          "items": { "type": "string", "enum": ["strict private", "private", "strict prote' +
      'cted", "protected", "public", "published"] },' + #10 +
      '          "default": ["strict private", "private", "strict protected", "protected", "publi' +
      'c", "published"],' + #10 +
      '          "description": "Zielreihenfolge der Sichtbarkeitsabschnitte; nicht genannte komm' + 'en ans Ende.",' +
      #10 + '          "x-description-en": "Target order of the visibility sections; sections not named' +
      ' go to the end."' + #10,
    '        },' + #10 + '        "members": {' + #10 + '          "type": "array",' + #10 +
      '          "items": { "type": "string", "enum": ["field", "constructor", "destructor", "met' +
      'hod", "property"] },' + #10 +
      '          "default": ["field", "constructor", "destructor", "method", "property"],' + #10 +
      '          "description": "Zielreihenfolge der Mitglieder in einem Abschnitt; innerhalb ein' +
      'er Art bleibt die Reihenfolge.",' + #10 +
      '          "x-description-en": "Target order of the members in a section; within a kind the' + ' order stays."' +
      #10 + '        },' + #10 + '        "sortFields": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10 +
      '          "description": "Abschnitte mit Feldern auch dann verschieben, wenn sich dadurch ' +
      'die Reihenfolge der Felder (Speicherlayout) ändert.",' + #10 +
      '          "x-description-en": "Also move sections with fields if this changes the order of' +
      ' the fields (memory layout)."' + #10,
    '        },' + #10 + '        "sortPublished": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10 +
      '          "description": "Auch published-Abschnitte umsortieren; ihre Reihenfolge bestimmt' +
      ' Streaming und Objektinspektor.",' + #10 +
      '          "x-description-en": "Also reorder published sections; their order determines str' +
      'eaming and the Object Inspector."' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "project",' +
      #10 + '      "x-page": "Editor",' + #10 + '      "x-control": "Liste, Kontrollkästchen",' + #10 +
      '      "x-issue": "#89"' + #10 + '    },' + #10 + '    "testUnits": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Testunits anlegen und zwischen Unit und Testunit wechseln: Namensmus' +
      'ter, Ordner neuer Testunits und Testprojekt.",' + #10,
    '      "x-description-en": "Create test units and switch between unit and test unit: name p' +
      'attern, folder of new test units and test project.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "pattern": {' + #10 + '          "type": "string",' + #10 +
      '          "default": "{unit}.Tests",' + #10 +
      '          "description": "Name der Testunit; {unit} steht für den Namen der getesteten Uni' +
      't, z. B. \"{unit}.Tests\" oder \"Test.{unit}\".",' + #10 +
      '          "x-description-en": "Name of the test unit; {unit} stands for the name of the te' +
      'sted unit, e.g. \"{unit}.Tests\" or \"Test.{unit}\"."' + #10 + '        },' + #10 + '        "folder": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "description": "Ordner für neue Testunits relativ zur Wurzel; leer: Ordner des T' + 'estprojekts.",' +
      #10,
    '          "x-description-en": "Folder for new test units relative to the root; empty: fold' +
      'er of the test project."' + #10 + '        },' + #10 + '        "project": {' + #10 +
      '          "type": "string",' + #10 + '          "default": "",' + #10 +
      '          "description": "Testprojekt (.dproj oder .dpr) relativ zur Wurzel; leer: das Pro' +
      'jekt im Arbeitsbereich, dessen .dpr DUnitX oder DUnit verwendet.",' + #10 +
      '          "x-description-en": "Test project (.dproj or .dpr) relative to the root; empty: ' +
      'the project in the workspace whose .dpr uses DUnitX or DUnit."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "project",' + #10 + '      "x-page": "Projekt",' + #10 +
      '      "x-control": "Textfeld, Dateiauswahl",' + #10 + '      "x-issue": "#274"' + #10 + '    },' + #10 +
      '    "tests": {' + #10 + '      "type": "object",' + #10,
    '      "description": "Betroffene Tests einer Änderung: aus dem Unterschied zur Basis (Git ' +
      'oder SVN) die geänderten Routinen, Typen und Konstanten bestimmen, ihre Auswirkungen verfo' +
      'lgen und nur die DUnitX-Tests nennen, die sie erreichen (Kommandozeile --affected-tests, M' +
      'CP-Werkzeug get_affected_tests, Plugin-Befehl „Betroffene Tests ausführen“).",' + #10 +
      '      "x-description-en": "Affected tests of a change: determine the changed routines, typ' +
      'es and constants from the difference to the base (Git or SVN), follow their impact and onl' +
      'y name the DUnitX tests that reach them (command line --affected-tests, MCP tool get_affec' +
      'ted_tests, plugin command \"Run affected tests\").",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "affected": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10,
    '          "description": "Betroffene Tests ermitteln; aus: Plugin-Befehl und MCP-Werkzeug ' +
      'fehlen, --affected-tests endet mit Exitcode 3.",' + #10 +
      '          "x-description-en": "Determine affected tests; off: plugin command and MCP tool ' +
      'are missing, --affected-tests ends with exit code 3."' + #10 + '        },' + #10 +
      '        "affectedDepth": {' + #10 + '          "type": "integer",' + #10 + '          "default": 3,' + #10 +
      '          "minimum": 1,' + #10 + '          "maximum": 5,' + #10 +
      '          "description": "Ebenen der Auswirkungsanalyse von der Änderung bis zum Test: 1 =' +
      ' nur Tests, die das geänderte Symbol direkt verwenden.",' + #10 +
      '          "x-description-en": "Levels of the impact analysis from the change to the test: ' +
      '1 = only tests that use the changed symbol directly."' + #10 + '        }' + #10 + '      },' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "build",' + #10 + '      "x-page": "Compiler",' + #10,
    '      "x-control": "Kontrollkästchen, Zahlenfeld",' + #10 + '      "x-issue": "#1353"' + #10 + '    },' + #10 +
      '    "minConfidence": {' + #10 + '      "type": "string",' + #10 + '      "enum": [' + #10 + '        "low",' +
      #10 + '        "medium",' + #10 + '        "high"' + #10 + '      ],' + #10 + '      "default": "medium",' + #10 +
      '      "description": "Regeltreffer unter dieser Konfidenz ausblenden.",' + #10 +
      '      "x-description-en": "Hide rule hits below this confidence.",' + #10 + '      "x-scope": "project",' + #10 +
      '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#144"' + #10 +
      '    },' + #10 + '    "fix": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Sammelkorrektur (--fix, MCP fix_findings, „Alle sicheren Treffer kor' +
      'rigieren …“ im Fenster „Atlas-Prüfung“): wendet nur sichere Korrekturen von Regeln mit saf' +
      'eFix im Katalog an.",' + #10,
    '      "x-description-en": "Bulk fix (--fix, MCP fix_findings, \"Fix all safe hits …\" in t' +
      'he window \"Atlas Check\"): only applies safe fixes of rules with safeFix in the catalog."' + ',' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "minConfidence": {' +
      #10 + '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "medium",' + #10 +
      '            "high"' + #10 + '          ],' + #10 + '          "default": "high",' + #10 +
      '          "description": "Untergrenze der Konfidenz für Sammelkorrekturen: Treffer darunte' +
      'r werden übersprungen und gezählt. fix_findings darf sie mit minConfidence nur anheben.",' + #10 +
      '          "x-description-en": "Lower confidence limit for bulk fixes: hits below are skipp' +
      'ed and counted. fix_findings may only raise it with minConfidence."' + #10 + '        }' + #10 + '      },' +
      #10 + '      "x-scope": "project",' + #10,
    '      "x-page": "Prüfregeln",' + #10 + '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#1352"' + #10 +
      '    },' + #10 + '    "exclude": {' + #10 + '      "type": "array",' + #10 + '      "items": {' + #10 +
      '        "type": "string"' + #10 + '      },' + #10 +
      '      "description": "Ordner und Dateien, die nicht geprüft werden (Glob-Muster relativ zu' +
      ' diesem Ordner: *, **, ?).",' + #10 +
      '      "x-description-en": "Folders and files that are not checked (glob patterns relative ' +
      'to this folder: *, **, ?).",' + #10 + '      "examples": [' + #10 + '        [' + #10 +
      '          "ThirdParty/**",' + #10 + '          "Generated/*.pas"' + #10 + '        ]' + #10 + '      ],' + #10 +
      '      "x-scope": "project",' + #10 + '      "x-page": "Projekt",' + #10 +
      '      "x-control": "Liste mit Hinzufügen/Entfernen",' + #10 + '      "x-issue": "#24"' + #10 + '    },' + #10 +
      '    "mcp": {' + #10 + '      "type": "object",' + #10,
    '      "description": "MCP-Modus (--mcp) für KI-Assistenten.",' + #10 +
      '      "x-description-en": "MCP mode (--mcp) for AI assistants.",' + #10 +
      '      "additionalProperties": false,' + #10 + '      "properties": {' + #10 + '        "disabledTools": {' +
      #10 + '          "type": "array",' + #10 + '          "items": {' + #10 + '            "type": "string"' + #10 +
      '          },' + #10 + '          "default": [],' + #10 +
      '          "description": "Werkzeuge, die der MCP-Server nicht anbietet, z. B. rename_symbo' +
      'l oder apply_code_action. Im eingeschränkten Modus (--restricted) sind schreibende Werkzeu' + 'ge immer aus.",' +
      #10 + '          "x-description-en": "Tools the MCP server does not offer, e.g. rename_symbol or ' +
      'apply_code_action. In restricted mode (--restricted) writing tools are always off."' + #10 + '        },' + #10 +
      '        "globalSettings": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Der MCP-Server liest wie der LSP-Server und der Linter die globa' +
      'le Datei %APPDATA%\\Atlas\\settings.json (z. B. mcp.disabledTools, Index, Hints). false: n' +
      'ur atlas.json, etwa für reproduzierbare Ergebnisse im Team.",' + #10 +
      '          "x-description-en": "Like the LSP server and the linter, the MCP server reads th' +
      'e global file %APPDATA%\\Atlas\\settings.json (e.g. mcp.disabledTools, index, hints). fals' +
      'e: only atlas.json, for example for reproducible results in the team.",' + #10 +
      '          "x-scope": "project",' + #10 + '          "x-page": "MCP",' + #10 +
      '          "x-control": "Kontrollkästchen in den Projekt-Einstellungen (Seite MCP)"' + #10 + '        },' + #10 +
      '        "prompts": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10,
    '          "description": "Prompts (in Claude Code Schrägstrich-Befehle wie /mcp__delphi__u' +
      'nit_review) und Ressourcenvorlagen (delphi://unit/{name}, delphi://form/{file}, delphi://f' +
      'indings/{file}, delphi://build/last) anbieten. false: prompts/list und resources/templates' +
      '/list sind leer, die Werkzeuge bleiben.",' + #10 +
      '          "x-description-en": "Offer prompts (in Claude Code slash commands such as /mcp__' +
      'delphi__unit_review) and resource templates (delphi://unit/{name}, delphi://form/{file}, d' +
      'elphi://findings/{file}, delphi://build/last). false: prompts/list and resources/templates' +
      '/list are empty, the tools stay.",' + #10 + '          "x-page": "MCP",' + #10 +
      '          "x-control": "Kontrollkästchen",' + #10 + '          "x-issue": "#1357"' + #10 + '        },' + #10 +
      '        "promptLanguage": {' + #10 + '          "type": "string",' + #10 + '          "enum": [' + #10 +
      '            "de",' + #10 + '            "en"' + #10,
    '          ],' + #10 + '          "default": "de",' + #10 +
      '          "description": "Sprache der Anleitungen in den Prompts.",' + #10 +
      '          "x-description-en": "Language of the instructions in the prompts.",' + #10 +
      '          "x-page": "MCP",' + #10 + '          "x-control": "Auswahl",' + #10 + '          "x-issue": "#1357"' +
      #10 + '        },' + #10 + '        "customPrompts": {' + #10 + '          "type": "array",' + #10 +
      '          "items": {' + #10 + '            "type": "object",' + #10 +
      '            "additionalProperties": false,' + #10 + '            "required": [' + #10 + '              "name",' +
      #10 + '              "text"' + #10 + '            ],' + #10 + '            "properties": {' + #10 +
      '              "name": {' + #10 + '                "type": "string",' + #10 +
      '                "pattern": "^[A-Za-z][A-Za-z0-9_-]*$",' + #10,
    '                "description": "Name des Prompts; in Claude Code /mcp__delphi__<name>. Ein' +
      'gebaute Namen (unit_review, explain_form, write_tests, fix_finding, prepare_commit) gehen ' + 'vor.",' + #10 +
      '                "x-description-en": "Name of the prompt; in Claude Code /mcp__delphi__<nam' +
      'e>. Built-in names (unit_review, explain_form, write_tests, fix_finding, prepare_commit) t' +
      'ake precedence."' + #10 + '              },' + #10 + '              "description": {' + #10 +
      '                "type": "string",' + #10 +
      '                "description": "Kurzbeschreibung in der Liste der Befehle.",' + #10 +
      '                "x-description-en": "Short description in the list of commands."' + #10 + '              },' +
      #10 + '              "arguments": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "object",' + #10 +
      '                  "additionalProperties": false,' + #10,
    '                  "required": [' + #10 + '                    "name"' + #10 + '                  ],' + #10 +
      '                  "properties": {' + #10 + '                    "name": {' + #10 +
      '                      "type": "string",' + #10 + '                      "pattern": "^[A-Za-z][A-Za-z0-9_-]*$",' +
      #10 + '                      "description": "Name des Arguments, im Text als {name}. file, unit u' +
      'nd name nutzen auch die Inhalte aus include.",' + #10 +
      '                      "x-description-en": "Name of the argument, in the text as {name}. fi' +
      'le, unit and name also use the contents from include."' + #10 + '                    },' + #10 +
      '                    "description": {' + #10 + '                      "type": "string",' + #10 +
      '                      "description": "Beschreibung des Arguments.",' + #10 +
      '                      "x-description-en": "Description of the argument."' + #10 + '                    },' +
      #10,
    '                    "required": {' + #10 + '                      "type": "boolean",' + #10 +
      '                      "default": false,' + #10 + '                      "description": "Pflichtargument.",' +
      #10 + '                      "x-description-en": "Required argument."' + #10 + '                    }' + #10 +
      '                  }' + #10 + '                }' + #10 + '              },' + #10 + '              "text": {' +
      #10 + '                "type": "string",' + #10 +
      '                "description": "Anleitung mit Platzhaltern {argument}.",' + #10 +
      '                "x-description-en": "Instructions with placeholders {argument}."' + #10 + '              },' +
      #10 + '              "include": {' + #10 + '                "type": "array",' + #10 +
      '                "items": {' + #10 + '                  "type": "string",' + #10 + '                  "enum": [' +
      #10 + '                    "outline",' + #10 + '                    "diagnostics",' + #10,
    '                    "metrics",' + #10 + '                    "unused",' + #10 + '                    "todos",' +
      #10 + '                    "form",' + #10 + '                    "impact",' + #10 +
      '                    "dependencies",' + #10 + '                    "conventions",' + #10 +
      '                    "lastBuild"' + #10 + '                  ]' + #10 + '                },' + #10 +
      '                "description": "Eingebettete Inhalte: Ergebnisse der Werkzeuge für die Arg' +
      'umente file, unit oder name.",' + #10 +
      '                "x-description-en": "Embedded contents: results of the tools for the argum' +
      'ents file, unit or name."' + #10 + '              }' + #10 + '            }' + #10 + '          },' + #10 +
      '          "default": [],' + #10 +
      '          "description": "Eigene Prompts des Projekts mit Platzhaltern {argument} im Text ' +
      'und eingebetteten Inhalten aus include (z. B. diagnostics, metrics).",' + #10,
    '          "x-description-en": "Own prompts of the project with placeholders {argument} in ' +
      'the text and embedded contents from include (e.g. diagnostics, metrics).",' + #10 +
      '          "x-scope": "project",' + #10 + '          "x-page": "MCP",' + #10 +
      '          "x-control": "JSON in atlas.json (Liste der Prompts)",' + #10 + '          "x-issue": "#1357"' + #10 +
      '        }' + #10 + '      },' + #10 + '      "examples": [' + #10 + '        {' + #10 +
      '          "disabledTools": [' + #10 + '            "rename_symbol",' + #10 + '            "apply_code_action"' +
      #10 + '          ]' + #10 + '        },' + #10 + '        {' + #10 + '          "globalSettings": false' + #10 +
      '        },' + #10 + '        {' + #10 + '          "prompts": true,' + #10 + '          "promptLanguage": "en"' +
      #10 + '        }' + #10 + '      ],' + #10 + '      "x-scope": "global",' + #10 + '      "x-area": "build",' +
      #10 + '      "x-page": "MCP",' + #10,
    '      "x-control": "Liste mit Hinzufügen/Entfernen; globalSettings, prompts: Kontrollkästc' +
      'hen; promptLanguage: Auswahl; customPrompts: JSON",' + #10 + '      "x-issue": "#99, #1357"' + #10 + '    },' +
      #10 + '    "format": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Formatierung (Dokument und Auswahl formatieren). Gesetzte Werte habe' +
      'n Vorrang vor .editorconfig.",' + #10 +
      '      "x-description-en": "Formatting (format document and selection). Values set here tak' +
      'e precedence over .editorconfig.",' + #10 + '      "additionalProperties": false,' + #10 +
      '      "properties": {' + #10 + '        "indentSize": {' + #10 + '          "type": "integer",' + #10 +
      '          "minimum": 1,' + #10 + '          "maximum": 16,' + #10 + '          "default": 2,' + #10 +
      '          "description": "Breite einer Einrückungsebene.",' + #10 +
      '          "x-description-en": "Width of one indentation level."' + #10 + '        },' + #10,
    '        "useTabs": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Mit Tabs statt Leerzeichen einrücken.",' + #10 +
      '          "x-description-en": "Indent with tabs instead of spaces."' + #10 + '        },' + #10 +
      '        "keywordCase": {' + #10 + '          "type": "string",' + #10 + '          "enum": [' + #10 +
      '            "preserve",' + #10 + '            "lower",' + #10 + '            "upper"' + #10 + '          ],' +
      #10 + '          "default": "preserve",' + #10 + '          "description": "Schreibweise reservierter Wörter.",' +
      #10 + '          "x-description-en": "Case of reserved words."' + #10 + '        },' + #10 +
      '        "trimTrailingWhitespace": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": true,' + #10 + '          "description": "Leerzeichen am Zeilenende entfernen.",' + #10 +
      '          "x-description-en": "Remove spaces at the end of lines."' + #10,
    '        },' + #10 + '        "insertFinalNewline": {' + #10 + '          "type": "boolean",' + #10 +
      '          "default": false,' + #10 + '          "description": "Datei mit einem Zeilenende abschließen.",' +
      #10 + '          "x-description-en": "End the file with a line break."' + #10 + '        },' + #10 +
      '        "spaceAroundAssignment": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' +
      #10 + '          "description": "Genau ein Leerzeichen vor und nach :=.",' + #10 +
      '          "x-description-en": "Exactly one space before and after :=."' + #10 + '        },' + #10 +
      '        "spaceAfterComma": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Genau ein Leerzeichen nach Kommas.",' + #10 +
      '          "x-description-en": "Exactly one space after commas."' + #10 + '        },' + #10 +
      '        "endOfLine": {' + #10 + '          "type": "string",' + #10,
    '          "enum": [' + #10 + '            "lf",' + #10 + '            "crlf"' + #10 + '          ],' + #10 +
      '          "description": "Zeilenenden vereinheitlichen; ohne Angabe bleiben sie.",' + #10 +
      '          "x-description-en": "Unify line endings; without a value they stay."' + #10 + '        },' + #10 +
      '        "reindent": {' + #10 + '          "type": "boolean",' + #10 + '          "default": true,' + #10 +
      '          "description": "Zeilen nach der Blockstruktur einrücken (begin/end, try, case, r' +
      'epeat, Abschnitte). Ausgeschaltet bleibt die vorhandene Einrückung und nur Tabs und Leerze' +
      'ichen werden umgerechnet.",' + #10 +
      '          "x-description-en": "Indent lines according to the block structure (begin/end, t' +
      'ry, case, repeat, sections). When off, the existing indentation stays and only tabs and sp' +
      'aces are converted."' + #10 + '        },' + #10 + '        "beginPlacement": {' + #10 +
      '          "type": "string",' + #10,
    '          "enum": [' + #10 + '            "preserve",' + #10 + '            "newLine",' + #10 +
      '            "sameLine"' + #10 + '          ],' + #10 + '          "default": "preserve",' + #10 +
      '          "description": "begin nach then, else und do: wie vorhanden, in einer eigenen Ze' +
      'ile oder in derselben Zeile.",' + #10 +
      '          "x-description-en": "begin after then, else and do: as existing, on its own line' +
      ' or on the same line."' + #10 + '        },' + #10 + '        "elsePlacement": {' + #10 +
      '          "type": "string",' + #10 + '          "enum": [' + #10 + '            "preserve",' + #10 +
      '            "newLine",' + #10 + '            "sameLine"' + #10 + '          ],' + #10 +
      '          "default": "preserve",' + #10 +
      '          "description": "else nach end: wie vorhanden, in einer eigenen Zeile oder in der' +
      'selben Zeile (end else).",' + #10,
    '          "x-description-en": "else after end: as existing, on its own line or on the same' +
      ' line (end else)."' + #10 + '        },' + #10 + '        "maxLineLength": {' + #10 +
      '          "type": "integer",' + #10 + '          "minimum": 0,' + #10 + '          "maximum": 1000,' + #10 +
      '          "default": 0,' + #10 +
      '          "description": "Längere Zeilen nach einem Komma oder vor einem Operator umbreche' +
      'n; 0 = nie. Gesetzt hat es Vorrang vor max_line_length aus .editorconfig.",' + #10 +
      '          "x-description-en": "Wrap longer lines after a comma or before an operator; 0 = ' +
      'never. When set it takes precedence over max_line_length from .editorconfig."' + #10 + '        },' + #10 +
      '        "alignAssignments": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' +
      #10 + '          "description": ":= untereinander stehender Zuweisungen ausrichten.",' + #10,
    '          "x-description-en": "Align := of assignments on consecutive lines."' + #10 + '        },' + #10 +
      '        "alignDeclarations": {' + #10 + '          "type": "boolean",' + #10 + '          "default": false,' +
      #10 + '          "description": "Doppelpunkte bzw. = untereinander stehender Deklarationen (var, ' +
      'const, Felder, Parameter) ausrichten.",' + #10 +
      '          "x-description-en": "Align colons or = of declarations on consecutive lines (var' +
      ', const, fields, parameters)."' + #10 + '        },' + #10 + '        "alignComments": {' + #10 +
      '          "type": "boolean",' + #10 + '          "default": false,' + #10 +
      '          "description": "Kommentare am Zeilenende untereinander stehender Zeilen ausricht' + 'en.",' + #10 +
      '          "x-description-en": "Align end-of-line comments of consecutive lines."' + #10 + '        }' + #10 +
      '      },' + #10 + '      "x-scope": "project",' + #10 + '      "x-page": "Formatierung",' + #10,
    '      "x-control": "Zahlenfeld, Kontrollkästchen, Auswahl",' + #10 + '      "x-issue": "#43"' + #10 + '    },' +
      #10 + '    "tasks": {' + #10 + '      "type": "array",' + #10 +
      '      "description": "Projektaufgaben (#900): Befehle des Projekts, die das Plugin per Bef' +
      'ehlspalette, Menü Atlas › Aufgaben, Taste, Statusfeld oder Schnellaktion startet; die Ausg' +
      'abe steht im Register „Atlas-Aufgaben“, erkannte Fundstellen als Befunde in Problemliste u' +
      'nd Editor. Projekt vor global bei gleichem Namen. Variablen in command, args, cwd und env:' +
      ' ${projectDir}, ${groupDir}, ${file}, ${fileDir}, ${config}, ${platform}, ${BDS}.",' + #10,
    '      "x-description-en": "Project tasks (#900): commands of the project that the plugin s' +
      'tarts via command palette, menu Atlas › Tasks, key, status field or quick action; the outp' +
      'ut goes to the tab \"Atlas Tasks\", detected locations as findings in the problem list and' +
      ' editor. Project before global for the same name. Variables in command, args, cwd and env:' +
      ' ${projectDir}, ${groupDir}, ${file}, ${fileDir}, ${config}, ${platform}, ${BDS}.",' + #10 + '      "items": {' +
      #10 + '        "type": "object",' + #10 + '        "additionalProperties": false,' + #10 +
      '        "required": ["name", "command"],' + #10 + '        "properties": {' + #10 + '          "name": {' + #10 +
      '            "type": "string",' + #10 + '            "minLength": 1,' + #10 +
      '            "description": "Name in Palette, Menü, Statusfeld und als Quelle der Befunde."' + ',' + #10,
    '            "x-description-en": "Name in palette, menu, status field and as source of the ' + 'findings."' + #10 +
      '          },' + #10 + '          "command": {' + #10 + '            "type": "string",' + #10 +
      '            "minLength": 1,' + #10 +
      '            "description": "Programm (gesucht im Arbeitsordner und in PATH), etwa \"pwsh\"' + '.",' + #10 +
      '            "x-description-en": "Program (searched in the working folder and in PATH), for' +
      ' example \"pwsh\"."' + #10 + '          },' + #10 + '          "args": {' + #10 +
      '            "type": "array",' + #10 + '            "items": { "type": ["string", "number"] },' + #10 +
      '            "description": "Parameter des Programms.",' + #10 +
      '            "x-description-en": "Parameters of the program."' + #10 + '          },' + #10 +
      '          "cwd": {' + #10 + '            "type": "string",' + #10 + '            "default": "${projectDir}",' +
      #10,
    '            "description": "Arbeitsordner; relative Pfade der Ausgabe gelten zuerst gegen ' + 'ihn.",' + #10 +
      '            "x-description-en": "Working folder; relative paths of the output are resolved' +
      ' against it first."' + #10 + '          },' + #10 + '          "env": {' + #10 +
      '            "type": "object",' + #10 + '            "additionalProperties": { "type": "string" },' + #10 +
      '            "description": "Zusätzliche Umgebungsvariablen Name → Wert.",' + #10 +
      '            "x-description-en": "Additional environment variables name → value."' + #10 + '          },' + #10 +
      '          "group": {' + #10 + '            "type": "string",' + #10 +
      '            "enum": ["check", "build", "test", "other"],' + #10 + '            "default": "other",' + #10 +
      '            "description": "Gruppe; „Alle Prüfungen ausführen“ und tasks.beforeBuild nehme' +
      'n die Gruppe check.",' + #10,
    '            "x-description-en": "Group; \"Run all checks\" and tasks.beforeBuild take the ' + 'group check."' +
      #10 + '          },' + #10 + '          "matcher": {' + #10 +
      '            "description": "Muster für Fundstellen: eingebaut (dcc, pwsh, msbuild, generic' +
      ', none) oder eigenes mit regex und benannten Gruppen file, line, column, severity, code, m' + 'essage.",' + #10 +
      '            "x-description-en": "Pattern for locations: built-in (dcc, pwsh, msbuild, gene' +
      'ric, none) or your own with regex and named groups file, line, column, severity, code, mes' + 'sage.",' + #10 +
      '            "oneOf": [' + #10 +
      '              { "type": "string", "enum": ["dcc", "pwsh", "msbuild", "generic", "none"] },' + #10 +
      '              {' + #10 + '                "type": "object",' + #10 +
      '                "additionalProperties": false,' + #10 + '                "required": ["regex"],' + #10 +
      '                "properties": {' + #10,
    '                  "regex": { "type": "string", "minLength": 1 },' + #10 +
      '                  "severity": { "type": "string", "enum": ["error", "warning", "info"], "d' +
      'efault": "error" },' + #10 + '                  "severityMap": {' + #10 +
      '                    "type": "object",' + #10 +
      '                    "additionalProperties": { "type": "string", "enum": ["error", "warning' + '", "info"] },' +
      #10 + '                    "description": "Eigene Wörter der Gruppe severity → error, warning ode' + 'r info.",' +
      #10 + '                    "x-description-en": "Own words of the group severity → error, warning ' + 'or info."' +
      #10 + '                  }' + #10 + '                }' + #10 + '              }' + #10 + '            ]' + #10 +
      '          },' + #10 + '          "key": {' + #10 + '            "type": "string",' + #10 +
      '            "description": "Taste, etwa \"Ctrl+Alt+1\"; Konflikte zeigt die Seite „Tastenk' + 'onflikte“.",' +
      #10,
    '            "x-description-en": "Key, for example \"Ctrl+Alt+1\"; conflicts are shown on t' +
      'he page \"Key conflicts\"."' + #10 + '          },' + #10 + '          "timeoutSec": {' + #10 +
      '            "type": "integer",' + #10 + '            "minimum": 0,' + #10 + '            "maximum": 86400,' +
      #10 + '            "default": 600,' + #10 +
      '            "description": "Zeitlimit in Sekunden; danach beendet Atlas den Prozess mit Me' +
      'ldung. 0 = ohne.",' + #10 +
      '            "x-description-en": "Time limit in seconds; after it Atlas ends the process wi' +
      'th a message. 0 = none."' + #10 + '          },' + #10 + '          "beforeBuild": {' + #10 +
      '            "type": "string",' + #10 + '            "enum": ["off", "warn", "block"],' + #10 +
      '            "description": "Überschreibt tasks.beforeBuild der IDE für diese Aufgabe.",' + #10 +
      '            "x-description-en": "Overrides tasks.beforeBuild of the IDE for this task."' + #10 + '          }' +
      #10,
    '        }' + #10 + '      },' + #10 + '      "x-scope": "both",' + #10 + '      "x-area": "build",' + #10 +
      '      "x-page": "Projekt",' + #10 +
      '      "x-control": "JSON in atlas.json bzw. settings.json (Liste der Aufgaben)",' + #10 +
      '      "x-issue": "#900"' + #10 + '    },' + #10 + '    "issues": {' + #10 + '      "type": "object",' + #10 +
      '      "description": "Issue-Tracker im Plugin (Tools › Optionen › Atlas › Issue-Tracker, B' +
      'ereich „Meine Issues“). Persönlich, daher nur in settings.json; der Abschnitt tracker der ' +
      'Projektdatei .atlas gilt daneben für das Team.",' + #10 +
      '      "x-description-en": "Issue tracker in the plugin (Tools › Options › Atlas › Issue tr' +
      'acker, area \"My issues\"). Personal, therefore only in settings.json; the section tracker' +
      ' of the project file .atlas applies alongside for the team.",' + #10 + '      "additionalProperties": false,' +
      #10 + '      "properties": {' + #10 + '        "connections": {' + #10,
    '          "type": "array",' + #10 + '          "default": [],' + #10 +
      '          "description": "Persönliche Tracker-Verbindungen (#1260), z. B. das Firmen-YouTr' +
      'ack und GitHub nebeneinander. Das Token steht nie hier, sondern im Anmeldespeicher von Win' +
      'dows (Atlas:tracker:<Server>, „Token hinterlegen …“).",' + #10 +
      '          "x-description-en": "Personal tracker connections (#1260), e.g. the company YouT' +
      'rack and GitHub side by side. The token is never stored here but in the Windows credential' +
      ' store (Atlas:tracker:<server>, \"Store token …\").",' + #10 + '          "items": {' + #10 +
      '            "type": "object",' + #10 + '            "additionalProperties": false,' + #10 +
      '            "required": ["name", "provider", "url"],' + #10 + '            "properties": {' + #10 +
      '              "name": {' + #10 + '                "type": "string",' + #10 + '                "minLength": 1,' +
      #10,
    '                "description": "Eindeutiger, frei wählbarer Name, z. B. \"Firma\".",' + #10 +
      '                "x-description-en": "Unique name of your choice, e.g. \"Company\"."' + #10 + '              },' +
      #10 + '              "provider": {' + #10 + '                "type": "string",' + #10 +
      '                "minLength": 1,' + #10 + '                "examples": ["youtrack", "github"],' + #10 +
      '                "description": "Anbieter; das Plugin kennt youtrack und github.",' + #10 +
      '                "x-description-en": "Provider; the plugin knows youtrack and github."' + #10 +
      '              },' + #10 + '              "url": {' + #10 + '                "type": "string",' + #10 +
      '                "pattern": "^https://[^@/\\s]+(/.*)?$",' + #10 +
      '                "examples": ["https://youtrack.firma.de", "https://github.com"],' + #10 +
      '                "description": "Adresse des Trackers, nur https und ohne Benutzer oder Tok' +
      'en in der Adresse.",' + #10,
    '                "x-description-en": "Address of the tracker, https only and without user o' +
      'r token in the address."' + #10 + '              },' + #10 + '              "language": {' + #10 +
      '                "type": "string",' + #10 + '                "enum": ["de", "en"],' + #10 +
      '                "description": "Sprache der Oberfläche des Trackers (#1263), erkannt bei „' +
      'Prüfen“. YouTrack übersetzt die Suchbegriffe; die Vorgabe „Mir zugewiesen“ ist dann assign' +
      'ee: meine #Ungelöst bzw. assignee: me #Unresolved. Fehlt sie, gilt die Vorgabe des Anbiete' + 'rs.",' + #10 +
      '                "x-description-en": "Language of the tracker''s user interface (#1263), det' +
      'ected on \"Check\". YouTrack translates the search terms; the default \"Assigned to me\" i' +
      's then assignee: meine #Ungelöst or assignee: me #Unresolved. If missing, the provider def' + 'ault applies."' +
      #10 + '              }' + #10 + '            }' + #10 + '          }' + #10,
    '        },' + #10 + '        "projects": {' + #10 + '          "type": "array",' + #10 +
      '          "default": [],' + #10 +
      '          "description": "Persönliche Zuordnung Delphi-Projekt → Tracker-Projekt (#1261) f' +
      'ür Projekte ohne tracker in der .atlas. Es gilt die Zeile für genau diese .dproj, sonst di' +
      'e für die geöffnete .groupproj, sonst der längste passende Ordner; eine .atlas mit tracker' + ' hat Vorrang.",' +
      #10 + '          "x-description-en": "Personal mapping Delphi project → tracker project (#1261) f' +
      'or projects without tracker in the .atlas. The line for exactly this .dproj applies, other' +
      'wise the one for the open .groupproj, otherwise the longest matching folder; an .atlas wit' +
      'h tracker takes precedence.",' + #10 + '          "items": {' + #10 + '            "type": "object",' + #10 +
      '            "additionalProperties": false,' + #10 + '            "required": ["match", "connection"],' + #10 +
      '            "properties": {' + #10,
    '              "match": {' + #10 + '                "type": "string",' + #10 + '                "minLength": 1,' +
      #10 + '                "examples": ["C:\\Projekte\\Kasse\\Kasse.groupproj", "C:\\Projekte\\Kasse"' + '],' + #10 +
      '                "description": "Gilt für: Pfad einer .dproj, einer .groupproj oder eines O' +
      'rdners (ohne Groß-/Kleinschreibung, auch UNC).",' + #10 +
      '                "x-description-en": "Applies to: path of a .dproj, a .groupproj or a folde' +
      'r (case-insensitive, also UNC)."' + #10 + '              },' + #10 + '              "connection": {' + #10 +
      '                "type": "string",' + #10 + '                "minLength": 1,' + #10 +
      '                "description": "Name einer Verbindung aus issues.connections.",' + #10 +
      '                "x-description-en": "Name of a connection from issues.connections."' + #10 + '              },' +
      #10 + '              "project": {' + #10 + '                "type": "string",' + #10,
    '                "default": "",' + #10 + '                "examples": ["KASSE", "owner/repo"],' + #10 +
      '                "description": "Tracker-Projekt: YouTrack-Projekt-ID, bei GitHub owner/rep' + 'o.",' + #10 +
      '                "x-description-en": "Tracker project: YouTrack project id, for GitHub owne' + 'r/repo."' + #10 +
      '              }' + #10 + '            }' + #10 + '          }' + #10 + '        },' + #10 +
      '        "queries": {' + #10 + '          "type": "array",' + #10 + '          "default": [],' + #10 +
      '          "description": "Benannte Abfragen für „Meine Issues“ (#1262), wählbar in der Kla' +
      'ppliste neben dem Titel. Ohne eigene Abfragen gilt je Anbieter „Mir zugewiesen“ (GitHub as' +
      'signee:@me state:open, YouTrack for: me #Unresolved). Ein früheres issues.query wird einma' +
      'l zur Abfrage „Standard“.",' + #10,
    '          "x-description-en": "Named queries for \"My issues\" (#1262), selectable in the ' +
      'drop-down next to the title. Without own queries \"Assigned to me\" applies per provider (' +
      'GitHub assignee:@me state:open, YouTrack for: me #Unresolved). An earlier issues.query bec' +
      'omes the query \"Default\" once.",' + #10 + '          "items": {' + #10 + '            "type": "object",' +
      #10 + '            "additionalProperties": false,' + #10 + '            "required": [' + #10 +
      '              "name",' + #10 + '              "query"' + #10 + '            ],' + #10 +
      '            "properties": {' + #10 + '              "name": {' + #10 + '                "type": "string",' +
      #10 + '                "minLength": 1,' + #10 + '                "examples": [' + #10 +
      '                  "Mir zugewiesen",' + #10 + '                  "Aktueller Sprint"' + #10 +
      '                ],' + #10,
    '                "description": "Name in der Klappliste; eindeutig (ohne Groß-/Kleinschreib' + 'ung).",' + #10 +
      '                "x-description-en": "Name in the drop-down; unique (case-insensitive)."' + #10 +
      '              },' + #10 + '              "query": {' + #10 + '                "type": "string",' + #10 +
      '                "minLength": 1,' + #10 + '                "examples": [' + #10 +
      '                  "assignee: meine #Ungelöst",' + #10 + '                  "assignee:@me state:open"' + #10 +
      '                ],' + #10 +
      '                "description": "Abfrage in der Syntax des Trackers, ohne project: …; das T' +
      'racker-Projekt setzt Atlas davor.",' + #10 +
      '                "x-description-en": "Query in the syntax of the tracker, without project: ' +
      '…; Atlas puts the tracker project in front."' + #10 + '              },' + #10 +
      '              "connection": {' + #10 + '                "type": "string",' + #10 +
      '                "default": "",' + #10,
    '                "description": "Name einer Verbindung aus issues.connections; leer = gilt ' +
      'für jeden Tracker.",' + #10 +
      '                "x-description-en": "Name of a connection from issues.connections; empty =' +
      ' applies to every tracker."' + #10 + '              },' + #10 + '              "project": {' + #10 +
      '                "type": "string",' + #10 + '                "default": "",' + #10 +
      '                "description": "Tracker-Projekt; leer = gilt für jedes Projekt.",' + #10 +
      '                "x-description-en": "Tracker project; empty = applies to every project."' + #10 +
      '              },' + #10 + '              "stateField": {' + #10 + '                "type": "string",' + #10 +
      '                "description": "Name des Zustandsfeldes im YouTrack-Projekt (#1266, deutsc' +
      'h oft \"Status\"); fehlt er, gilt issues.stateField.",' + #10,
    '                "x-description-en": "Name of the state field in the YouTrack project (#126' +
      '6, in German often \"Status\"); if missing, issues.stateField applies."' + #10 + '              },' + #10 +
      '              "assigneeField": {' + #10 + '                "type": "string",' + #10 +
      '                "description": "Name des Benutzerfeldes für die Zuständigkeit im YouTrack-' +
      'Projekt (#1266); fehlt er, gilt issues.assigneeField.",' + #10 +
      '                "x-description-en": "Name of the user field for the assignee in the YouTra' +
      'ck project (#1266); if missing, issues.assigneeField applies."' + #10 + '              },' + #10 +
      '              "startState": {' + #10 + '                "type": "string",' + #10 +
      '                "description": "Zustand beim Beginnen für diesen Tracker (#1266, GitHub: L' +
      'abel); fehlt er, gilt issues.startState.",' + #10,
    '                "x-description-en": "State when starting for this tracker (#1266, GitHub: ' +
      'label); if missing, issues.startState applies."' + #10 + '              },' + #10 +
      '              "endStates": {' + #10 + '                "type": "array",' + #10 + '                "items": {' +
      #10 + '                  "type": "string"' + #10 + '                },' + #10 +
      '                "description": "Angebotene Zielzustände beim Beenden für diesen Tracker (#' +
      '1266); fehlen sie, gilt issues.endStates.",' + #10 +
      '                "x-description-en": "Offered target states when finishing for this tracker' +
      ' (#1266); if missing, issues.endStates applies."' + #10 + '              }' + #10 + '            }' + #10 +
      '          }' + #10 + '        }' + #10 + '      },' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "issues",' + #10 + '      "x-page": "Issue-Tracker",' + #10 +
      '      "x-control": "Tabellen Verbindungen, Projekte und Abfragen",' + #10,
    '      "x-issue": "#1260, #1261, #1262"' + #10 + '    },' + #10 + '    "logLevel": {' + #10 +
      '      "type": "string",' + #10 + '      "enum": [' + #10 + '        "debug",' + #10 + '        "info",' + #10 +
      '        "warning",' + #10 + '        "error"' + #10 + '      ],' + #10 + '      "default": "info",' + #10 +
      '      "description": "Mindeststufe der Meldungen im Ausgabefenster und in der Logdatei. Gi' +
      'lt ab dem nächsten Start; die Kommandozeilenoption --log-level hat Vorrang.",' + #10 +
      '      "x-description-en": "Minimum level of the messages in the output window and in the l' +
      'og file. Applies from the next start; the command line option --log-level takes precedence' + '.",' + #10 +
      '      "x-scope": "global",' + #10 + '      "x-area": "general",' + #10 + '      "x-page": "Protokoll",' + #10 +
      '      "x-control": "Auswahl",' + #10 + '      "x-issue": "#76, #96",' + #10 +
      '      "x-commandLine": "--log-level",' + #10 + '      "x-restart": true' + #10,
    '    },' + #10 + '    "logFile": {' + #10 + '      "type": "string",' + #10 + '      "default": "",' + #10 +
      '      "description": "Optionale Logdatei des Servers (Rotation bei 10 MB). Gilt ab dem näc' +
      'hsten Start; --log hat Vorrang.",' + #10 +
      '      "x-description-en": "Optional log file of the server (rotation at 10 MB). Applies fr' +
      'om the next start; --log takes precedence.",' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-path": true,' + #10 + '      "x-page": "Protokoll",' + #10 +
      '      "x-control": "Datei wählen",' + #10 + '      "x-issue": "#76, #96",' + #10 +
      '      "x-commandLine": "--log",' + #10 + '      "x-restart": true' + #10 + '    },' + #10 +
      '    "traceFile": {' + #10 + '      "type": "string",' + #10 + '      "default": "",' + #10 +
      '      "description": "Optionaler Mitschnitt aller JSON-Nachrichten zur Fehlersuche. Gilt a' +
      'b dem nächsten Start; --trace hat Vorrang.",' + #10,
    '      "x-description-en": "Optional recording of all JSON messages for troubleshooting. Ap' +
      'plies from the next start; --trace takes precedence.",' + #10 + '      "x-scope": "global",' + #10 +
      '      "x-area": "general",' + #10 + '      "x-path": true,' + #10 + '      "x-page": "Protokoll",' + #10 +
      '      "x-control": "Datei wählen",' + #10 + '      "x-issue": "#76, #96",' + #10 +
      '      "x-commandLine": "--trace",' + #10 + '      "x-restart": true' + #10 + '    }' + #10 + '  },' + #10 +
      '  "additionalProperties": false' + #10 + '}' + #10);

function AtlasSchemaJson: string;
var
  mChunk: string;
begin
  Result := '';
  for mChunk in cChunks do
  begin
    Result := Result + mChunk;
  end;
end;

end.
