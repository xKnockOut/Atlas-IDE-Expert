unit Atlas.Common.Rules.Catalog.Data.De.Robustness;

// Erzeugt von Tools/Update-RuleCatalog.ps1 aus Katalog\regelkatalog.de.json.
// Nicht von Hand ändern.

interface

const
  CatalogLinesDeRobustness: array[0..99] of string = (
    '{',
    '      "id": "random-without-randomize",',
    '      "name": "Random ohne Randomize",',
    '      "description": "Random wird verwendet, aber die Unit ruft nie Randomize auf; jeder Start liefert dieselbe Folge. Randomize steht oft in der .dpr, deshalb ist die Regel standardmäßig aus und hat ' +
    'niedrige Konfidenz."',
    '    },',
    '{',
    '      "id": "format-without-settings",',
    '      "name": "Formatierung abhängig vom Gebietsschema",',
    '      "description": "Format mit %f, %n, %m, %g oder %e und Funktionen wie FloatToStr, StrToFloat oder DateToStr ohne TFormatSettings-Parameter verwenden das Gebietsschema des Benutzers (Dezimaltrenne' +
    'r, Datumsformat). Für Dateien, Protokolle und Logs feste TFormatSettings übergeben. Format(''%d'', …) wird nicht gemeldet, ebenso wenig FormatDateTime und FormatFloat mit festem Bild ohne Trennzeichen (' +
    ': / . ,) wie ''yyyy\"-\"mm\"-\"dd'' oder ''ddddd t''."',
    '    },',
    '{',
    '      "id": "debug-display-placeholder",',
    '      "name": "Wertdarstellung nennt unbekanntes Mitglied",',
    '      "description": "Eine Regel für die Wertdarstellung beim Debuggen über einem Typ (// atlas-debug: ''{Name}, {Ort}'', [AtlasDebugDisplay(''…'')], // atlas-debug-children: Name, Ort oder [AtlasDebugChi' +
    'ldren(''…'')]) nennt einen Platzhalter oder ein Unterelement, das weder Feld noch Eigenschaft noch Methode des Typs oder eines Vorfahren ist, oder die Vorlage ist ungültig (offene oder leere Klammer). I' +
    'm Debugger bliebe ein solcher Platzhalter leer ({?Name}). Vorfahren kommen aus der Unit und dem Index; ist ein Vorfahr unbekannt, schweigt die Regel für den Typ. Mitglieder von TObject (ClassName, ToS' +
    'tring, …) gelten immer als bekannt."',
    '    },',
    '{',
    '      "id": "null-compare",',
    '      "name": "Vergleich mit Null statt VarIsNull oder IsNull",',
    '      "description": "X = Null bzw. X <> Null vergleicht einen Variant mit Null. Das Ergebnis hängt von der globalen Einstellung System.Variants.NullEqualityRule ab: Mit der Vorgabe ncrLoose vergleich' +
    't er wie erwartet, mit ncrStrict ist er nie wahr, mit ncrError löst er eine Exception aus. Eine Bibliothek, ein Testrahmen oder ein anderer Teil des Projekts kann die Einstellung ändern. VarIsNull(X) ' +
    'und Feld.IsNull prüfen unabhängig davon. Gemeldet wird nur, wo der Vergleich für sich steht (Bedingung, Argument, Zuweisung); not X = Null bindet als (not X) = Null und bekommt keine Korrektur. Sicher' +
    'heit hoch. Korrektur: Feld.IsNull bei X.Value auf FieldByName, FindField, Fields[…], ParamByName, Params[…] oder einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not davor."',
    '    },',
    '{',
    '      "id": "path-concat-without-delimiter",',
    '      "name": "Pfad ohne Trennzeichen zusammengesetzt",',
    '      "description": "Ein Ordner ohne abschließendes Trennzeichen wird mit + an einen Datei- oder Ordnernamen gehängt: Ergebnisse von ExtractFileDir, ExcludeTrailingPathDelimiter, GetCurrentDir, GetHo' +
    'mePath, TPath.GetDocumentsPath und den übrigen TPath.Get…Path-Ordnern, TPath.GetDirectoryName, TDirectory.GetCurrentDirectory und TDirectory.GetParent, direkt aufgerufen oder in einer lokalen Variable' +
    'n, der die Routine nur solche Werte zuweist. Das Ergebnis ist C:\\Datendatei.txt statt C:\\Daten\\datei.txt. ExtractFilePath, IncludeTrailingPathDelimiter und TPath.GetTempPath enden mit einem Trennze' +
    'ichen und bleiben still, ebenso Trennzeichen, Endungen (ExtractFileExt, ''.bak'') und Texte, die mit Leerzeichen oder Satzzeichen beginnen. Ein Literal als Name meldet mit hoher, ein Bezeichner mit mitt' +
    'lerer Konfidenz. Geht eine lokale Variable an eine Prozedur außer ForceDirectories, FileExists und ähnlichen lesenden Aufrufen, kann sie dort geändert werden und bleibt still. Schnellkorrektur: TPath.' +
    'Combine(Ordner, Name), System.IOUtils wird in die uses eingetragen."',
    '    },',
    '{',
    '      "id": "hardcoded-path",',
    '      "name": "Fester Dateipfad im Code",',
    '      "description": "Ein String-Literal mit Laufwerksbuchstaben (C:\\…, auch mit /) oder UNC-Pfad (\\\\server\\freigabe\\…); Pfade unter C:\\Users bzw. C:\\Documents and Settings bekommen eine eigene' +
    ' Meldung. Auf anderen Rechnern fehlt der Pfad. Laufwerkswurzeln wie ''C:\\'' allein und die Präfixe \\\\?\\ und \\\\.\\ bleiben still, ebenso Kommentare, Test-Units und Units aus allowUnits (z. B. eine ' +
    'Unit mit den Standardpfaden einer Installation). Konfidenz hoch, keine Korrektur: den Pfad aus TPath (GetDocumentsPath, GetHomePath, GetSharedDocumentsPath), den Einstellungen oder einer Umgebungsvari' +
    'ablen holen.",',
    '      "options": [',
    '        {',
    '          "name": "allowUnits",',
    '          "description": "Units, in denen feste Pfade erlaubt sind, nach Unit-Namen; * am Ende passt auf ein Präfix (App.Config*)."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "filename-compare-case",',
    '      "name": "Dateinamen mit = verglichen",',
    '      "description": "Ein Vergleich mit = oder <>, bei dem eine Seite ein Datei- oder Pfadname ist: das Ergebnis von ExtractFileName, ExtractFilePath, ExtractFileDir, ExtractFileExt, ExpandFileName, C' +
    'hangeFileExt und verwandten Funktionen aus System.SysUtils, von TPath.GetFileName, GetExtension, GetDirectoryName, GetFullPath, Combine und verwandten Methoden oder eine Variable bzw. Eigenschaft, der' +
    'en Name auf FileName endet, oder Application.ExeName. Unter Windows sind Kunde.pas und kunde.PAS dieselbe Datei. Vergleiche mit Leertext, nil oder einem Literal ohne Buchstaben bleiben still, ebenso E' +
    'xtractFileDir(X) = X (beide Seiten stammen aus demselben Text). Still bleibt sie auch, wenn dieselbe Anweisung dieselben beiden Seiten ohne Groß-/Kleinschreibung vergleicht (SameText, AnsiSameText, Co' +
    'mpareText, AnsiCompareText, SameFileName, AnsiCompareFileName), etwa plattformabhängig mit PathDelim = ''\\'', und in Test-Units (Testdoubles vergleichen mit Namen, die der Test selbst vergibt). Konfide' +
    'nz mittel. Korrektur: SameFileName(A, B), bei <> not SameFileName(A, B); ergänzt System.SysUtils in der uses-Klausel, falls nötig."',
    '    },',
    '{',
    '      "id": "initialization-not-finalized",',
    '      "name": "Beim Start erzeugtes Objekt wird nicht freigegeben",',
    '      "description": "Ein Objekt wird in initialization mit TKlasse.Create erzeugt und einer Unit-Variablen zugewiesen oder in einem class constructor erzeugt und einer class var zugewiesen, aber die ' +
    'Unit gibt es nirgends frei (kein Free, Destroy, DisposeOf, Release oder FreeAndNil in der ganzen Unit). FastMM meldet beim Beenden ein Leck; in Packages bleibt das Objekt bei jedem Entladen liegen. In' +
    'terface- und Record-Typen, Komponenten mit Owner (Application, Self, Owner) und Objekte, die die Unit weitergibt, bleiben still: Jede Erwähnung der Variablen muss harmlos sein (Zugriff auf ein Mitglie' +
    'd, Vergleich mit nil, Assigned, erneutes Create oder Zuweisung von nil); als Argument übergeben, anderswo zugewiesen, with, eine Property, die sie liest, oder FreeOnTerminate lassen die Regel schweige' +
    'n. Bei Variablen aus dem interface-Abschnitt und öffentlichen class vars schweigt sie auch, wenn eine andere Unit im Index den Namen verwendet. Konfidenz hoch. Korrektur: FreeAndNil am Ende von finali' +
    'zation bzw. im class destructor; fehlt der finalization-Abschnitt oder der class destructor (Deklaration und Rumpf), wird er angelegt, System.SysUtils kommt bei Bedarf in die uses-Klausel."',
    '    },',
    '{',
    '      "id": "compiler-warnings-disabled",',
    '      "name": "Compiler-Warnungen oder Prüfungen bis zum Ende der Unit abgeschaltet",',
    '      "description": "{$WARNINGS OFF}, {$HINTS OFF}, {$WARN X OFF}, {$R-}, {$Q-} (auch zusammen als {$R-,Q-}) oder die langen Formen {$RANGECHECKS OFF} und {$OVERFLOWCHECKS OFF} ohne spätere Wiederher' +
    'stellung bis zum Ende der Unit. Meldungen und Prüfungen verschwinden weit über die gemeinte Stelle hinaus, die 0/0/0-Regel wird unterlaufen. Jedes spätere ON, +, DEFAULT oder ERROR für denselben Schal' +
    'ter zählt als Wiederherstellung, auch in Mustern mit {$IFOPT}/{$IFDEF}, ebenso ein späteres {$POPOPT}. Ein Schalter, dessen Gegenstück in einem anderen Zweig desselben {$IF} steht ({$IFDEF DEBUG}{$R+}' +
    '{$ELSE}{$R-}{$ENDIF}), ist eine gewollte Einstellung je Konfiguration und bleibt still, ebenso eine Direktive ohne Code dahinter; {$R *.dfm} ist eine Ressource, keine Bereichsprüfung. Die Option allow' +
    ' nennt Schalter, die aus bleiben dürfen (Warnungsnamen wie SYMBOL_PLATFORM, WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS). Konfidenz hoch. Korrektur: die Wiederherstellung ({$WARNINGS ON' +
    '}, {$WARN X DEFAULT}, {$R+} …) hinter dem nächsten Block einfügen; bei Bereichs- und Überlaufprüfung nur einzeln, weil {$R+} eine Prüfung einschalten kann, die das Projekt aus hat.",',
    '      "options": [',
    '        {',
    '          "name": "allow",',
    '          "description": "Schalter, die bis zum Ende der Unit aus bleiben dürfen: Warnungsnamen für {$WARN} (SYMBOL_PLATFORM), WARNINGS, HINTS, R bzw. RANGECHECKS, Q bzw. OVERFLOWCHECKS; ohne Groß-/Kl' +
    'einschreibung."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "dll-export-unsafe",',
    '      "name": "Exportierte Routine nicht sicher über DLL-Grenzen aufrufbar",',
    '      "description": "Eine in exports aufgeführte Routine dieser Datei hat keine Aufrufkonvention (stdcall, cdecl, safecall, winapi oder pascal; register ist die Delphi-Konvention) oder erwartet bzw. ' +
    'liefert einen String (string, UnicodeString, AnsiString, UTF8String, RawByteString), ein dynamisches Array (TBytes, TArray<T>, …DynArray, array of T aus der Datei), ein Objekt oder ein Interface ohne ' +
    'GUID. Aufrufer aus anderen Sprachen oder Delphi-Versionen stürzen ab; Strings und dynamische Arrays liegen im Speichermanager der DLL. WideString, ShortString, PChar, offene Array-Parameter und Record' +
    's sind in Ordnung. Objekte erkennt die Regel nur sicher: Klassen der Datei, des Index und häufige RTL-Klassen; Interfaces nur aus der Datei. Routinen aus anderen Units und Überladungen, die der export' +
    's-Eintrag nicht festlegt, bleiben still. Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays erlaubt (Option allowShareMem). Die Meldung steht am Eintrag in exports' +
    '; bei Strings empfiehlt sie PChar mit Puffer und Länge. Konfidenz hoch. Korrektur: stdcall in jedem Kopf der Routine ergänzen (nur einzeln, weil das die Schnittstelle für vorhandene Aufrufer ändert)."' +
    ',',
    '      "options": [',
    '        {',
    '          "name": "allowShareMem",',
    '          "description": "Mit ShareMem oder SimpleShareMem in der uses-Klausel sind Strings und dynamische Arrays in exportierten Routinen erlaubt."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "global-formatsettings-modified",',
    '      "name": "Globale FormatSettings wird verändert",',
    '      "description": "Zuweisung an die globale FormatSettings oder eines ihrer Felder (auch an die veralteten globalen Variablen DecimalSeparator, ShortDateFormat, ThousandSeparator … älterer Delphi-V' +
    'ersionen). Das ändert die Formatierung für die ganze Anwendung, für alle Packages im selben Prozess (im IDE-Plugin die IDE selbst) und für alle Threads und ist nicht threadsicher; häufig eine Notlösun' +
    'g, um einen Punkt als Dezimaltrenner zu erzwingen. Gemeldet wird nur, wenn der Name sicher die Variable aus System.SysUtils ist: keine lokale Deklaration, kein Mitglied der Klasse oder ihrer Vorfahren' +
    ' (still, wenn die Kette der Vorfahren an einer unbekannten Klasse endet), nicht in with. Ergänzt format-without-settings, das Formatierungsaufrufe ohne Settings meldet. Konfidenz hoch. Schnellkorrektu' +
    'r, wenn die Routine die globalen Settings nur einmal ändert und danach etwas formatiert: lokale TFormatSettings anlegen (TFormatSettings.Invariant bei DecimalSeparator := ''.'', sonst eine Kopie von For' +
    'matSettings mit dem geänderten Feld) und an die folgenden Formatierungsaufrufe übergeben. Mit allowInProgram sind die Zuweisungen in der .dpr erlaubt.",',
    '      "options": [',
    '        {',
    '          "name": "allowInProgram",',
    '          "description": "Zuweisungen in der .dpr erlauben, etwa einmal beim Programmstart."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "ui-call-in-console-or-service",',
    '      "name": "Dialog in Konsolenprogramm oder Dienst",',
    '      "description": "ShowMessage, ShowMessageFmt, MessageDlg, TaskMessageDlg, InputBox, InputQuery, Application.MessageBox oder TDialogService in einem Programm mit {$APPTYPE CONSOLE} (oder DCC_Conso' +
    'leTarget in der .dproj), in einem Windows-Dienst oder in einer DLL ohne Formulare. Im Dienst blockiert der Dialog unsichtbar; ein Konsolenprogramm wartet auf einen Klick, den niemand sieht, wenn es un' +
    'beaufsichtigt läuft. Als Dienst gilt eine Unit mit einer Klasse, die von TService erbt, oder jede Unit eines Projekts, dessen .dpr Vcl.SvcMgr ohne Vcl.Forms einbindet. Eine DLL ohne Formulare ist eine' +
    ' library, deren .dpr kein Formular aufführt und Vcl.Forms nicht einbindet; dort meldet die Regel mit mittlerer Konfidenz, weil erst der Host entscheidet, ob es eine Oberfläche gibt. Units mit Formular' +
    'datei, Aufrufe unter if IsConsole und gleichnamige Routinen der Unit bleiben still. Gegenstück zu writeln-in-gui-app. Konfidenz hoch. Keine Schnellkorrektur: die Meldung protokollieren statt anzeigen.' +
    '"',
    '    },',
    '{',
    '      "id": "load-without-encoding",',
    '      "name": "Text laden oder speichern ohne Kodierung",',
    '      "description": "LoadFromFile, SaveToFile, LoadFromStream oder SaveToStream einer TStrings (TStringList, Memo.Lines, ListBox.Items, Query.SQL) sowie TFile.ReadAllText und TFile.ReadAllLines ohne ' +
    'Kodierung: Eine Datei ohne BOM wird mit der ANSI-Codepage des Rechners gelesen, SaveToFile schreibt ANSI, und Umlaute gehen zwischen Rechnern verloren. Der Empfänger muss eine deklarierte Stringliste ' +
    'oder eine Property Lines, Items, SQL oder Strings sein; Bilder, Streams und Datenmengen bleiben still. Ebenso still, wenn die Liste irgendwo in der Unit DefaultEncoding setzt oder in derselben Routine' +
    ' vorher mit Kodierung geladen wurde (SaveToFile behält diese Kodierung). TFile.WriteAllText, TStreamReader und TStreamWriter nehmen ohne Angabe schon UTF-8 und werden nicht gemeldet. Konfidenz mittel.' +
    ' Schnellkorrektur: TEncoding.UTF8 (Option defaultEncoding) als letztes Argument und System.SysUtils im uses ergänzen.",',
    '      "options": [',
    '        {',
    '          "name": "defaultEncoding",',
    '          "description": "Property von TEncoding, die die Schnellkorrektur einsetzt: UTF8, Unicode, BigEndianUnicode, ANSI, ASCII, UTF7 oder Default."',
    '        }',
    '      ]',
    '    },',
    '{',
    '      "id": "registry-hklm-write",',
    '      "name": "Schreiben nach HKEY_LOCAL_MACHINE",',
    '      "description": "RootKey := HKEY_LOCAL_MACHINE auf einer TRegistry, danach in derselben Routine ein schreibender Zugriff auf dasselbe Objekt: OpenKey(…, True), CreateKey, Write…, DeleteKey, Delet' +
    'eValue, RenameValue, MoveKey, SaveKey oder RestoreKey. Ohne Administratorrechte schlägt das fehl oder landet still in der Virtualisierung der Registry. Für Benutzereinstellungen HKEY_CURRENT_USER verw' +
    'enden; Installer-Code über exclude ausnehmen. Lesen (OpenKeyReadOnly, Read…, OpenKey(…, False)), ein anderer RootKey vor dem Schreiben und Schreiben im anderen Zweig von {$IFDEF} bleiben still. Konfid' +
    'enz hoch. Schnellkorrektur: RootKey := HKEY_CURRENT_USER."',
    '    }');

implementation

end.
