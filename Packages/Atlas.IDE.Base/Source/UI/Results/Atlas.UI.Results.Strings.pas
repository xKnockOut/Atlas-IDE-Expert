unit Atlas.UI.Results.Strings;

// Oberflächentexte des Features Ergebnisfenster auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasResultsTextId = (
    ResultsReferences, ResultsImplementations, ResultsFailed, RenamePreviewApply, RenamePreviewCancel,
    UndoActionUndo, UndoActionRedo, UndoActionDiff, PeekTitleDefinition, PeekTitleReferences, PeekNoDefinition,
    PeekNoReferences, ResultsOnlySure, RenameChangedGroup, RenameUnchangedGroup, ReferenceReasonInterface,
    ReferenceReasonVirtual, ReferenceReasonAmbiguous, ReferenceReasonUnresolved, ReferenceReasonInactiveBranch,
    ReferenceReasonText, CallDiagramToggle, CallDiagramOutgoing, CallDiagramIncoming, CallDiagramProjectOnly,
    CallDiagramSaveHtml, CallDiagramSaveFilter, CallDiagramImplementations, CallDiagramImplementation,
    CallDiagramMore, CallDiagramHint, CallDiagramSaved, CallDiagramFit, SymbolPathShowMap, ImpactTitle,
    ImpactDirect, ImpactIndirect, ImpactTests, ImpactNoTests, ImpactRunTests, ImpactDepth, ImpactEdgeReference,
    ImpactEdgeOverride, ImpactEdgeBase, ImpactEdgeInterface, ImpactEdgeImplementation, ImpactForm, ImpactUnitLevel,
    ImpactLimitDepth, ImpactLimitCount, ImpactLimitTime, ImpactOff, ImpactNothing, ImpactRunning,
    ResultsDataFlowOff, DataFlowOnlyProject, DataFlowExcludeTests, DataFlowVia, DataFlowUnsafe,
    DataFlowUnsafePointer, DataFlowUnsafeAddress, DataFlowOriginLiteral, DataFlowOriginOutside,
    DataFlowOriginAddress, DataFlowOriginOpen, DataFlowLeafConstant, DataFlowLeafOutside, DataFlowLeafCycle,
    DataFlowLeafDepth);

  TAtlasResultsStrings = class
  public
    class function Text(AId: TAtlasResultsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasResultsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasResultsTextId] of string = (
    ('Referenzen auf %s: %d in %d Dateien',
     'Implementierungen von %s: %d in %d Dateien',
     'Atlas: Suche fehlgeschlagen: %s',
     'Umbenennen',
     'Abbrechen',
     'Zurücknehmen',
     'Wiederherstellen',
     'Unterschied anzeigen',
     'Definition: %s',
     'Referenzen auf %s (%d)',
     'Keine Definition für „%s“ gefunden.',
     'Keine Referenzen auf „%s“ gefunden.',
     'Nur sichere',
     'Wird geändert (%d)',
     'Nicht geändert, bitte prüfen (%d)',
     'über Interface',
     'überschrieben',
     'Überladung unklar',
     'Typ unbekannt',
     'inaktiver Zweig',
     'im Text',
     'Diagramm',
     'Ausgehend: Aufgerufene',
     'Eingehend: Aufrufer',
     'Nur Projekt-Units',
     'Als HTML speichern …',
     'HTML-Datei (*.html)|*.html',
     '%d Umsetzungen',
     '1 Umsetzung',
     '+ %d …',
     'Klick klappt auf und zu · Doppelklick springt in den Code · Ziehen verschiebt · Mausrad zoomt · 0 passt ein',
     'Aufrufdiagramm gespeichert: %s',
     'Einpassen',
     'In Architekturkarte zeigen',
     'Auswirkungen von %s · Tiefe %d · %d Stellen',
     'Direkt (%d)',
     'Indirekt (%d)',
     'Betroffene Tests (%d)',
     'Keine betroffenen Tests',
     'Betroffene Tests ausführen',
     'Tiefe:',
     'Verweis',
     'Override',
     'überschriebene Basismethode',
     'Interface-Methode',
     'Umsetzung',
     'Formular: %s  (%s:%d)',
     'Unit-Ebene',
     'Tiefe %d erreicht: %d Stellen nicht weiter verfolgt',
     'Höchstzahl von %d Stellen erreicht, Ergebnis unvollständig',
     'Zeitlimit von %d ms erreicht, Ergebnis unvollständig',
     'Auswirkungen anzeigen ist ausgeschaltet (navigation.impact).',
     'Keine Auswirkungen gefunden: Am Cursor steht kein Symbol, oder nichts verwendet es.',
     'Ermittle Auswirkungen von %s (Tiefe %d) …',
     'Datenfluss ist ausgeschaltet (Tools › Optionen › Atlas › Befehle).',
     'Nur Projektcode',
     'Tests ausblenden',
     'über %s',
     'unsicher: %s',
     'Zeiger',
     'Adresse',
     'Literal',
     'außerhalb des Projekts',
     'Wert kann sich über die Adresse ändern',
     'ohne bekannte Quelle',
     'Konstante',
     'außerhalb des Projekts',
     'Zyklus',
     'Tiefe erreicht'),
    ('References to %s: %d in %d files',
     'Implementations of %s: %d in %d files',
     'Atlas: Search failed: %s',
     'Rename',
     'Cancel',
     'Undo',
     'Redo',
     'Show difference',
     'Definition: %s',
     'References to %s (%d)',
     'No definition found for "%s".',
     'No references to "%s" found.',
     'Sure only',
     'Will change (%d)',
     'Not changed, please check (%d)',
     'via interface',
     'overridden',
     'ambiguous overload',
     'unknown type',
     'inactive branch',
     'in a string',
     'Diagram',
     'Outgoing: callees',
     'Incoming: callers',
     'Project units only',
     'Save as HTML …',
     'HTML file (*.html)|*.html',
     '%d implementations',
     '1 implementation',
     '+ %d …',
     'Click expands and collapses · double-click jumps to the code · drag pans · mouse wheel zooms · 0 fits',
     'Call diagram saved: %s',
     'Fit',
     'Show on architecture map',
     'Impact of %s · depth %d · %d places',
     'Direct (%d)',
     'Indirect (%d)',
     'Affected tests (%d)',
     'No affected tests',
     'Run affected tests',
     'Depth:',
     'reference',
     'override',
     'overridden base method',
     'interface method',
     'implementation',
     'Form: %s  (%s:%d)',
     'unit level',
     'Depth %d reached: %d places not followed further',
     'Limit of %d places reached, result incomplete',
     'Time limit of %d ms reached, result incomplete',
     'Show impact is switched off (navigation.impact).',
     'No impact found: there is no symbol at the cursor, or nothing uses it.',
     'Determining impact of %s (depth %d) …',
     'Data flow is turned off (Tools › Options › Atlas › Commands).',
     'Project code only',
     'Hide tests',
     'via %s',
     'unsafe: %s',
     'pointer',
     'address',
     'literal',
     'outside the project',
     'value may change through the address',
     'no known source',
     'constant',
     'outside the project',
     'cycle',
     'depth reached'));

{ TAtlasResultsStrings }

class function TAtlasResultsStrings.Text(AId: TAtlasResultsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasResultsStrings.Fmt(AId: TAtlasResultsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
