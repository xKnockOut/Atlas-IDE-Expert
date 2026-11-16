unit Atlas.UI.Debug.Values.Strings;

// Texte zu Werten: Visualisierer, Ansichtsfenster, eigene Wertdarstellung, Hover-Baum, angeheftete Werte und Werte
// ändern, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest
// sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasValuesTextId = (
    DebugVisualizerName, DebugVisualizerDescription, DebugViewerMenu, DebugViewerTitle, DebugViewerColumnIndex,
    DebugViewerColumnValue, DebugViewerColumnKey, DebugViewerColumnField, DebugViewerColumnFieldType,
    DebugViewerColumnOldValue, DebugViewerRunning, DebugViewerOutOfScope, DebugViewerNeedsMore, DebugViewerEmpty,
    DebugViewerCopy, DebugDisplayName, DebugDisplayDescription, DebugViewerAllFields, DebugVisualizerEvaluationFields,
    DebugVisualizerEvaluationProperties, DebugVisualizerEvaluationCalls, EditValueAction, EditValueToggle,
    EditValueUndo, EditValueTitle, EditValueCurrent, EditValueType, EditValueApply, EditValueCancel,
    EditValueChooseColor, EditValueSetter, EditValueConfirmSetter, EditValueEmpty, EditValueNotInteger,
    EditValueOutOfRange, EditValueNotFloat, EditValueNotBoolean, EditValueNotChar, EditValueUnknown, EditValueReadOnly,
    EditValueFailed, EditValueNoValue, EditValueMark, EditValueNoChange, PinAction, PinLimit, HoverTreeEvaluate,
    HoverTreePending, HoverTreeMore, HoverTreeCopy, HoverTreeWatch,
    DebugVisualizerKindLists, DebugVisualizerKindDictionaries, DebugVisualizerKindDataSets, DebugVisualizerKindBytes,
    DebugVisualizerKindJson, DebugVisualizerKindColors, DebugVisualizerKindGuid, DebugVisualizerKindGeometry,
    DebugVisualizerKindGraphics);

  TAtlasValuesStrings = class
  public
    class function Text(AId: TAtlasValuesTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasValuesTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasValuesTextId] of string = (
    ('Atlas: %s',
     'Zeigt %s einzeilig und im Atlas-Ansichtsfenster (#835).',
     'Mit Atlas anzeigen …',
     'Atlas-Visualisierer: %s',
     'Nr.',
     'Wert',
     'Schlüssel',
     'Feld',
     'Typ',
     'Alter Wert',
     'Nicht verfügbar: Das Programm läuft.',
     'Nicht verfügbar: Der Ausdruck ist hier nicht gültig.',
     'Mehr zeigt Atlas mit „Auswertung im Programm: auch Funktionsaufrufe“ (debug.visualizers.evaluation).',
     'Nichts zu zeigen.',
     'Kopieren',
     'Atlas: eigene Wertdarstellung',
     'Zeigt Typen mit Regel (// atlas-debug:, [AtlasDebugDisplay], .atlas) nach ihrer Vorlage (#854).',
     'Alle Felder',
     'nur Felder (ohne Nebenwirkungen)',
     'auch Getter von Eigenschaften',
     'auch Funktionsaufrufe (ToString, ToJSON)',
     'Ändern …',
     'Auf %s setzen',
     'Rückgängig (vorher %s)',
     'Wert ändern: %s',
     'Jetzt: %s',
     'Typ: %s',
     'Ändern',
     'Abbrechen',
     'Farbe wählen …',
     'Setter %s wird aufgerufen.',
     'Ändern ruft den Setter %s im Programm auf; er kann Nebenwirkungen haben. Ändern?',
     'Kein Wert eingegeben.',
     '„%s“ ist keine ganze Zahl.',
     'Außerhalb des Bereichs %s.',
     '„%s“ ist keine Zahl.',
     'Nur True oder False.',
     '„%s“ ist kein einzelnes Zeichen.',
     '„%s“ ist kein Wert dieses Typs.',
     '%s ist nur lesbar.',
     '%s ließ sich nicht ändern: %s',
     'Kein Wert unter der Schreibmarke.',
     '%s (vorher %s)',
     'Kein geänderter Wert unter der Schreibmarke.',
     'Anheften',
     'Höchstens %d angeheftete Werte je Projekt.',
     'auswerten',
     'wird ausgewertet …',
     'weitere %d …',
     'Kopieren',
     'Beobachten',
     'Listen (TList<T>, TObjectList<T>, TStack<T>, TQueue<T>)',
     'Dictionaries (TDictionary<K,V>)',
     'Datenmengen (TDataSet und Nachfahren)',
     'Bytes und Streams (TBytes, TStream)',
     'JSON (TJSONValue)',
     'Farben (TColor, TAlphaColor)',
     'GUIDs (TGUID)',
     'Geometrie (TPoint, TRect, TSize)',
     'Grafiken (TBitmap, TPicture)'),
    ('Atlas: %s',
     'Shows %s on one line and in the Atlas viewer (#835).',
     'Show with Atlas …',
     'Atlas visualizer: %s',
     'No.',
     'Value',
     'Key',
     'Field',
     'Type',
     'Old value',
     'Not available: the program is running.',
     'Not available: the expression is not valid here.',
     'Atlas shows more with “Evaluation in the program: also function calls” (debug.visualizers.evaluation).',
     'Nothing to show.',
     'Copy',
     'Atlas: custom value display',
     'Shows types with a rule (// atlas-debug:, [AtlasDebugDisplay], .atlas) by their template (#854).',
     'All fields',
     'fields only (no side effects)',
     'also property getters',
     'also function calls (ToString, ToJSON)',
     'Change …',
     'Set to %s',
     'Undo (was %s)',
     'Change value: %s',
     'Now: %s',
     'Type: %s',
     'Change',
     'Cancel',
     'Choose colour …',
     'Setter %s will be called.',
     'Changing calls the setter %s in the program; it may have side effects. Change?',
     'No value entered.',
     '“%s” is not a whole number.',
     'Outside the range %s.',
     '“%s” is not a number.',
     'Only True or False.',
     '“%s” is not a single character.',
     '“%s” is not a value of this type.',
     '%s is read-only.',
     '%s could not be changed: %s',
     'No value at the cursor.',
     '%s (was %s)',
     'No changed value at the cursor.',
     'Pin',
     'At most %d pinned values per project.',
     'evaluate',
     'evaluating …',
     '%d more …',
     'Copy',
     'Watch',
     'Lists (TList<T>, TObjectList<T>, TStack<T>, TQueue<T>)',
     'Dictionaries (TDictionary<K,V>)',
     'Datasets (TDataSet and descendants)',
     'Bytes and streams (TBytes, TStream)',
     'JSON (TJSONValue)',
     'Colors (TColor, TAlphaColor)',
     'GUIDs (TGUID)',
     'Geometry (TPoint, TRect, TSize)',
     'Graphics (TBitmap, TPicture)'));

{ TAtlasValuesStrings }

class function TAtlasValuesStrings.Text(AId: TAtlasValuesTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasValuesStrings.Fmt(AId: TAtlasValuesTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
