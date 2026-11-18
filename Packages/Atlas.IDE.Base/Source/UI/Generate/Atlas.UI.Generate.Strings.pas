unit Atlas.UI.Generate.Strings;

// Oberflächentexte des Features Codeerzeugung auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasGenerateTextId = (
    GenerateTitle, GenerateGroupRecent, GenerateGroupGenerate, GenerateGroupSurround, GenerateGroupTemplates,
    GenerateHint, GenerateFilter, GenerateEmpty, GenerateNoMatch, GenerateStepHint, GenerateStepMultiHint,
    GenerateFreeText, GenerateExample, GenerateArgumentPrompt, GenerateNoChoices, GenerateMenuOff, GenerateFailed,
    GenerateHiddenSaved, WelcomeSetupNewFailed, GalleryFileExists, GalleryChoiceSearch, GalleryChoiceOk,
    GalleryChoiceCancel, GenerateCmdCtor, GenerateCmdDtor, GenerateCmdProp, GenerateCmdOverride, GenerateCmdImplement,
    GenerateCmdEquals, GenerateCmdImpl, GenerateCmdField, GenerateCmdEncapsulate, GenerateCmdClone, GenerateCmdAssign,
    GenerateCmdJson, GenerateCmdMsg, GenerateCmdNotify, GenerateCmdChanged, GenerateCmdLoaded, GenerateCmdNotification,
    GenerateCmdSingleton, GenerateCmdList, GenerateCmdDict, GenerateCmdDictBang, GenerateCmdOperator, GenerateCmdGuid,
    GenerateCmdVar, GenerateCmdConst, GenerateCmdConstBang, GenerateCmdGuard, GenerateCmdRaise, GenerateCmdLog,
    GenerateCmdSql, GenerateCmdParams, GenerateCmdRecord, GenerateCmdEnum, GenerateCmdEnumBang, GenerateCmdHelper,
    GenerateCmdException, GenerateCmdThread, GenerateCmdExternal, GenerateCmdExports, GenerateCmdTodo, GenerateCmdTry,
    GenerateCmdExcept, GenerateCmdLock, GenerateCmdSync, GenerateCmdSyncBang, GenerateCmdIfdef, GenerateCmdRegion,
    GenerateCmdMeasure, GenerateCmdTask, GenerateCmdFuture, GenerateCmdLoop, GenerateCmdTransaction);

  TAtlasGenerateStrings = class
  public
    class function Text(AId: TAtlasGenerateTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasGenerateTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasGenerateTextId] of string = (
    ('Erzeugen',
     'Zuletzt gewählt',
     'Erzeugen',
     'Umschließen',
     'Vorlagen',
     '1–9 wählen · Tippen filtert · Entf blendet aus',
     'Filter: %s',
     'Hier gibt es nichts zu erzeugen',
     'Kein Eintrag passt',
     'Enter übernimmt · Esc zurück',
     'Leertaste wählt · Enter übernimmt · Esc zurück',
     '„%s“ verwenden',
     'Beispiel: %s',
     'Argument eingeben',
     'Keine Auswahl; Argument eingeben',
     'Das Erzeugen-Menü ist abgeschaltet (keys.generateMenu).',
     'Erzeugen: %s',
     '„%s“ ausgeblendet; wieder einblenden unter Einstellungen › Befehle.',
     'Neu mit Atlas: Die Datei ließ sich nicht anlegen (%s).',
     'Die Datei %s gibt es schon.',
     'Suchen',
     'OK',
     'Abbrechen',
     'Konstruktor aus Feldern',
     'Destruktor mit Freigabe',
     'Property mit Feld',
     'Methoden überschreiben…',
     'Interface implementieren…',
     'Equals / GetHashCode',
     'Fehlende Methodenrümpfe',
     'Feld…',
     'Feld kapseln…',
     'Clone mit Freigabe',
     'Assign für alle Felder',
     'ToJson und FromJson',
     'Botschaftsmethode…',
     'Ereignis mit Feld und Property…',
     'Setter mit Benachrichtigung…',
     'Loaded überschreiben',
     'Notification für Komponentenfelder',
     'Singleton',
     'Liste…',
     'Dictionary…',
     'Dictionary ohne Groß-/Kleinschreibung…',
     'Operatoren…',
     'GUID einfügen',
     'Lokale Variable…',
     'Lokale Konstante…',
     'Konstante in der implementation…',
     'nil-Prüfungen für Parameter',
     'Ausnahme auslösen…',
     'Protokollzeile',
     'SQL-Text und Parameter…',
     'ParamByName-Zeilen ergänzen…',
     'Record mit Konstruktor…',
     'Aufzählungstyp…',
     'Aufzählungstyp ohne Präfix…',
     'Helper…',
     'Ausnahmeklasse…',
     'TThread-Nachfahre…',
     'Funktion aus einer DLL…',
     'Routinen exportieren',
     'TODO-Kommentar…',
     'try … finally Free',
     'try … except mit Protokoll',
     'Sperren',
     'Im Hauptthread (Queue)',
     'Im Hauptthread (Synchronize)',
     '{$IFDEF}…',
     '{$REGION}…',
     'Laufzeit messen',
     'In TTask.Run',
     'Als TTask.Future…',
     'Datensätze durchlaufen…',
     'In einer Transaktion…'),
    ('Generate',
     'Recently used',
     'Generate',
     'Surround',
     'Templates',
     '1–9 choose · type to filter · Del hides',
     'Filter: %s',
     'Nothing to generate here',
     'No entry matches',
     'Enter applies · Esc goes back',
     'Space toggles · Enter applies · Esc goes back',
     'Use “%s”',
     'Example: %s',
     'Type an argument',
     'No choices; type an argument',
     'The generate menu is switched off (keys.generateMenu).',
     'Generate: %s',
     '“%s” hidden; show it again under Settings › Commands.',
     'New with Atlas: the file could not be created (%s).',
     'The file %s already exists.',
     'Search',
     'OK',
     'Cancel',
     'Constructor from fields',
     'Destructor with cleanup',
     'Property with field',
     'Override methods…',
     'Implement interface…',
     'Equals / GetHashCode',
     'Missing method bodies',
     'Field…',
     'Encapsulate field…',
     'Clone with cleanup',
     'Assign for all fields',
     'ToJson and FromJson',
     'Message method…',
     'Event with field and property…',
     'Setter with notification…',
     'Override Loaded',
     'Notification for component fields',
     'Singleton',
     'List…',
     'Dictionary…',
     'Case-insensitive dictionary…',
     'Operators…',
     'Insert GUID',
     'Local variable…',
     'Local constant…',
     'Constant in the implementation…',
     'nil checks for parameters',
     'Raise exception…',
     'Log line',
     'SQL text and parameters…',
     'Add ParamByName lines…',
     'Record with constructor…',
     'Enumeration…',
     'Enumeration without prefix…',
     'Helper…',
     'Exception class…',
     'TThread descendant…',
     'Function from a DLL…',
     'Export routines',
     'TODO comment…',
     'try … finally Free',
     'try … except with logging',
     'Lock',
     'On the main thread (Queue)',
     'On the main thread (Synchronize)',
     '{$IFDEF}…',
     '{$REGION}…',
     'Measure duration',
     'In TTask.Run',
     'As TTask.Future…',
     'Loop over records…',
     'In a transaction…'));

{ TAtlasGenerateStrings }

class function TAtlasGenerateStrings.Text(AId: TAtlasGenerateTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasGenerateStrings.Fmt(AId: TAtlasGenerateTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
