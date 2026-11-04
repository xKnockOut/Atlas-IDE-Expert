unit Atlas.IDE.Search.Commands;

// Atlas-Suche im Editor (#877, #878):
// - Show: Suchleiste (Atlas.UI.Search.Bar) am unteren Rand des obersten
//   Editorfensters (alBottom im Eltern-Steuerelement des Editors „Editor“, wie
//   die Brotkrumenleiste oben). Jedes Editorfenster bekommt beim ersten Öffnen
//   seine eigene Leiste. Vorschlag ist die einzeilige Markierung, sonst der
//   Bezeichner am Cursor, sonst die letzte Suche. Bereich ist immer die Unit
//   (mehrzeilige Markierung: Auswahl); ShowInMethod („In Methode suchen“,
//   #877) stellt ihn auf Methode und die Stufe auf die innerste Routine.
//   Sonst gilt Methode nur, wenn der Anwender sie in der Leiste wählt.
// - Jede Änderung in der Leiste sucht neu: Treffer im Editor gerahmt, Sprung
//   zum nächsten Treffer ab der Stelle, an der die Leiste geöffnet wurde,
//   Zähler „n von m“. Bei Bereich Auswahl und Methode gelten Auswahl und
//   Cursor beim Öffnen; die Auswahl wandert nicht mit den Treffern.
// - Enter bzw. „In Meldungen“ listet alle Treffer im Reiter „Atlas-Suche“ des
//   Fensters Meldungen (Atlas.IDE.Search.MessageList, search.resultsInMessages);
//   dieselbe Suche wird nicht erneut aufgebaut. Der Fokus bleibt in der Leiste.
// - TryNext (F3/Umschalt+F3, in der Leiste auch Enter/Umschalt+Enter):
//   nächster bzw. voriger Treffer der letzten Suche mit Umlauf (Meldung in
//   der Meldungsansicht), auch bei geschlossener Leiste. Ohne letzte Suche
//   False: die Taste geht weiter (Markierung suchen bzw. „Erneut suchen“ der
//   IDE). Ist ein anderer Text einzeilig markiert als zuletzt gesucht, sucht
//   F3 nach der Markierung. Bei Bereich Methode und Cursor außerhalb jeder
//   Routine sucht F3 in der ganzen Unit (Meldung).
// - Esc bzw. × schließt die Leiste, gibt den Fokus an den Editor zurück und
//   beendet die Hervorhebung; F3 sucht weiter mit der letzten Suche.
// - Solange die Leiste offen ist, prüft ein Takt (Probe): Holt die IDE den
//   Fokus kurz nach dem Klick in die Leiste wieder in den Editor, kommt er
//   einmal zurück; liegt über der Leiste ein anderes Fenster, wird sie nach
//   vorn geholt. Beides steht mit Fensterklasse im Diagnoseprotokoll, ebenso
//   beim ersten Öffnen je Fenster die Lage von Editor und Leiste.
// Ersetzen, Regex, Verlauf und Bereiche über Dateien (#893):
// - ShowReplace (Strg+H, search.replace) öffnet die Leiste mit Ersetzen-Zeile,
//   Show ohne. „Ersetzen“ ersetzt den markierten Treffer und springt weiter;
//   steht keiner markiert, springt es nur. „Alle ersetzen“ ersetzt im Bereich:
//   in einer Datei als ein Rückgängig-Schritt (Schreiber der IDE), über Dateien
//   über TAtlasIdeWorkspaceEdit mit dem Änderungsprotokoll (#721). Danach
//   steht „n Ersetzungen in m Dateien“ in der Leiste.
// - Regex (search.regex): ungültiger Ausdruck färbt das Suchfeld rot und zeigt
//   den Fehlertext; dann wird nichts markiert, gezählt oder ersetzt. Bei
//   offener Ersetzen-Zeile zeigt die Leiste die Vorschau des aktuellen
//   Treffers.
// - Bereiche „Offene Dateien“, „Projekt“, „Projektgruppe“ (search.multiFile):
//   Der Editor hebt nur die aktive Datei hervor; nach einer kurzen Pause im
//   Tippen sucht TAtlasIdeFileSearch im Hintergrund (Puffer vor Platte), der
//   Zähler zeigt „n Treffer in m Dateien“. Enter bzw. „In Meldungen“ listet
//   die Dateien nach und nach im Reiter „Atlas-Suche“; „Abbrechen“ beendet
//   die Suche. F3 springt über Dateien (aktive Datei mit ihrem aktuellen
//   Text). „Auswählen …“ zeigt die Treffer mit Häkchen im Fenster
//   „Atlas-Suche: Ersetzen“; „Ausgewählte ersetzen“ ändert nur angehakte,
//   schreibgeschützte und seit der Suche geänderte Dateien werden gemeldet und
//   übersprungen. „Alle ersetzen“ sucht vorher neu.
// - Verlauf (search.history): Such- und Ersetzen-Verlauf in
//   %APPDATA%\Atlas\search-history.json über Neustarts (TAtlasDataFile).
// Tasten: Strg+F/F3/Umschalt+F3 nur mit search.replaceIdeSearch, Strg+H
// zusätzlich nur mit search.replace (Atlas.IDE.Commands.Bindings), „In
// Methode suchen“ immer. Nur im Hauptthread.
// - Anlegen je Editorfenster (auf Abruf, EnsureFor), Wächter, Freigabe nach
//   der Sperre durch die IDE und Abbau übernimmt TAtlasEditorBarHost (#1248).
//   Die Leisten sind verborgen, bis Show sie öffnet; deshalb kein Guard.
// Tasten: Strg+F/F3/Umschalt+F3 nur mit search.replaceIdeSearch
// (Atlas.IDE.Commands.Bindings), „In Methode suchen“ immer. Nur im
// Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Files,
  Atlas.Core.Search.History,
  Atlas.Core.Search.ReplaceList,
  Atlas.UI.Search.Bar,
  Atlas.IDE.Foundation.EditorBarHost;

type
  TAtlasIdeSearch = class
  private type
    TPainter = class
    private type
      TEvents = class(TNTACodeEditorNotifier)
      protected
        function AllowedEvents: TCodeEditorEvents; override;
        function AllowedLineStages: TPaintLineStages; override;
      end;
    private
      FEvents: TEvents;
      FEventsRef: INTACodeEditorEvents;
      FIndex: Integer;
      FCheck: Boolean;
      FKey: string;
      FLines: TArray<string>;
      FTabWidth: Integer;
      // Je 0-basierter Zeile die Treffer.
      FHits: TArray<TArray<TAtlasSearchHit>>;
      procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
      procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
        var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
      procedure Refresh(const Context: INTACodeEditorPaintContext);
    public
      constructor Create;
      destructor Destroy; override;
    end;

    /// <summary>Besitzer des Takts bei offener Leiste.</summary>
    TProbeOwner = class(TComponent)
    public
      procedure Tick(Sender: TObject);
      procedure FilesTick(Sender: TObject);
    end;
  private class var
    FLast: TAtlasSearchQuery;
    FVersion: Integer;
    FPainter: TPainter;
    FMessage: TProc<string>;
    FHost: TAtlasEditorBarHost;
    FProbeOwner: TProbeOwner;
    // Leiste der laufenden Suche und Stand beim Öffnen.
    FBar: TAtlasSearchBar;
    FOrigin: TAtlasSearchPos;
    FSelection: TAtlasSearchArea;
    FFileName: string;
    FHighlight: Boolean;
    FListedKey: string;
    // Takt bei offener Leiste: Fokus und Fenster unter der Maus (Probe).
    FProbe: TTimer;
    FProbed: HWND;
    FEntered: TWinControl;
    FEnteredAt: UInt64;
    // Such- und Ersetzen-Verlauf (#893); Kept: Datei nicht lesbar, nicht überschreiben.
    FSearchHistory: TAtlasSearchHistory;
    FReplaceHistory: TAtlasSearchHistory;
    FHistoryKept: Boolean;
    // Suche über Dateien (#893): Ergebnisse, Schlüssel der Suche, Stand und was danach kommt.
    FFiles: TAtlasReplaceList;
    FFilesKey: string;
    FFilesDone: Boolean;
    FFilesListed: Boolean;
    FAfterFiles: TProc;
    FFilesTimer: TTimer;
  private
    class procedure Say(const AText: string); static;
    class function TopView(out AView: IOTAEditView): Boolean; static;
    class function CursorOf(const AView: IOTAEditView; const ALines: TArray<string>): TAtlasSearchPos; static;
    class function SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
      out AArea: TAtlasSearchArea): Boolean; static;
    /// <summary>Bereich der Suche im Text: Auswahl wie gemerkt, Methode an ACursor, sonst ganzer Text.</summary>
    class function AreaOf(const AText: string; const AQuery: TAtlasSearchQuery; const ACursor: TAtlasSearchPos;
      out AArea: TAtlasSearchArea): Boolean; static;
    class procedure SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
      const AHit: TAtlasSearchHit); static;
    class procedure Repaint; static;
    class procedure Open(AInMethod, AReplace: Boolean); static;
    class function Features: TAtlasSearchBarFeatures; static;
    class function TabWidth: Integer; static;
    // Verlauf.
    class function HistoryFile: string; static;
    class procedure LoadHistories; static;
    class procedure SaveHistories; static;
    // Suche über Dateien.
    class function FilesKey(const AQuery: TAtlasSearchQuery): string; static;
    class function FilesCurrent: Boolean; static;
    class procedure ScheduleFiles; static;
    class procedure StartFiles(AListed: Boolean; const AThen: TProc); static;
    class procedure FileFound(const AHits: TAtlasFileHits); static;
    class procedure FilesDone(const ASummary: TAtlasFileSearchSummary); static;
    class procedure ListFiles; static;
    class procedure DropFiles; static;
    class procedure RefreshReplaceWindow(const ANotice: string); static;
    class function NextAcrossFiles(ABackward: Boolean): Boolean; static;
    class procedure OpenHit(const AFileName: string; ALine, ACharacter: Integer); static;
    // Ersetzen.
    class function ReplaceText: string; static;
    class function MarkedHit(const AView: IOTAEditView; const ALines: TArray<string>;
      const AHits: TArray<TAtlasSearchHit>): Integer; static;
    class procedure UpdatePreview; static;
    class procedure Notice(const AText: string); static;
    class procedure BarReplace; static;
    class procedure BarReplaceAll; static;
    class procedure BarChoose; static;
    class procedure BarCancel; static;
    class procedure ReplaceChosen; static;
    // Leisten.
    class function BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar; static;
    class function CreateBar: TAtlasSearchBar; static;
    class procedure Place(ABar: TAtlasSearchBar; AParent: TWinControl); static;
    class procedure Removed(ABar: TControl); static;
    class procedure ThemeBar(ABar: TAtlasSearchBar); static;
    /// <summary>Suche der Leiste übernehmen; AJump: zum nächsten Treffer ab dem Ursprung springen.</summary>
    class procedure Sync(AJump: Boolean); static;
    class procedure UpdateCounter; static;
    class procedure BarStep(ABackward: Boolean); static;
    class procedure BarList; static;
    class procedure CloseBar; static;
    class procedure Probe; static;
    /// <summary>Von der IDE gesperrte Leisten wieder freigeben (Projektwechsel).</summary>
    class procedure EnableBars; static;
    class procedure LogLayout(ABar: TAtlasSearchBar); static;
    class procedure StopProbe; static;
  public
    /// <summary>Zeichner anmelden; AMessage schreibt eine Zeile in die Meldungsansicht.</summary>
    class procedure Install(const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>search.resultsInMessages aus: Reiter entfernen und Schaltfläche ausblenden.</summary>
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    /// <summary>Suchleiste (Strg+F, Befehl Atlas.Search).</summary>
    class procedure Show; static;
    /// <summary>Suchleiste mit Bereich Methode (#877, Befehl Atlas.SearchInMethod).</summary>
    class procedure ShowInMethod; static;
    /// <summary>Suchleiste mit Ersetzen-Zeile (#893, Strg+H, Befehl Atlas.SearchReplace); mit search.replace aus
    /// wie Show.</summary>
    class procedure ShowReplace; static;
    /// <summary>F3/Umschalt+F3: False ohne letzte Atlas-Suche oder ohne Editor.</summary>
    class function TryNext(ABackward: Boolean): Boolean; static;
    /// <summary>Für Palette und Menü: wie TryNext, ohne letzte Suche öffnet sich die Leiste.</summary>
    class procedure FindNext; static;
    class procedure FindPrevious; static;
    class procedure ClearHighlights; static;
  end;

implementation

uses
  System.IOUtils,
  Vcl.Graphics,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Search.Replace,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Search.MessageList,
  Atlas.IDE.Search.FileSearch,
  Atlas.IDE.Search.ReplaceWindow,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Navigation,
  Atlas.UI.Search.ReplaceFrame,
  Atlas.IDE.Foundation.DockWindow;

const
  // Takt bei offener Leiste und Frist, in der ein Fokusverlust nach dem Klick als zurückgeholt gilt.
  ProbeMs = 100;
  FocusGraceMs = 400;
  // Pause im Tippen, nach der die Suche über Dateien beginnt (#893).
  FilesDelayMs = 400;
  HistoryKind = 'Suchverlauf';

/// <summary>„1 Datei“, „3 Dateien“.</summary>
function Plural(ACount: Integer; AOne, AMany: TAtlasSearchTextId): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasSearchStrings.Text(AOne);
  end
  else
  begin
    Result := TAtlasSearchStrings.Text(AMany);
  end;
end;

/// <summary>„12 Ersetzungen in 3 Dateien“.</summary>
function ReplacedText(AReplacements, AFiles: Integer): string;
begin
  Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaced, [AReplacements,
    Plural(AReplacements, TAtlasSearchTextId.SearchReplacementOne, TAtlasSearchTextId.SearchReplacementMany), AFiles,
    Plural(AFiles, TAtlasSearchTextId.SearchFileOne, TAtlasSearchTextId.SearchFileMany)]);
end;

/// <summary>Schreibgeschützt: offener Puffer der IDE, sonst die Datei auf der Platte.</summary>
function IsReadOnlyFile(const AFileName: string): Boolean;
var
  Buffer: IOTAEditBuffer;
  Attributes: DWORD;
begin
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
  begin
    Exit(Buffer.IsReadOnly);
  end;
  Attributes := GetFileAttributes(PChar(AFileName));
  Result := (Attributes <> INVALID_FILE_ATTRIBUTES) and ((Attributes and FILE_ATTRIBUTE_READONLY) <> 0);
end;

/// <summary>Änderungen in die Puffer bzw. Dateien (#397, #721); '' oder der Fehler.</summary>
function ApplyEdit(const AEdit: TLspWorkspaceEdit; const AAction: string): string;
var
  Outcome: TAtlasWorkspaceEditResult;
begin
  Outcome := TAtlasIdeWorkspaceEdit.Apply(AEdit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), AAction);
  Result := Outcome.Error;
end;

{ TAtlasIdeSearch.TPainter.TEvents }

function TAtlasIdeSearch.TPainter.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintLineEvents];
end;

function TAtlasIdeSearch.TPainter.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeSearch.TPainter }

constructor TAtlasIdeSearch.TPainter.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeSearch.TPainter.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeSearch.TPainter.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  FCheck := True;
end;

procedure TAtlasIdeSearch.TPainter.Refresh(const Context: INTACodeEditorPaintContext);
var
  View: IOTAEditView;
  Text, Key: string;
  Area: TAtlasSearchArea;
  Hit: TAtlasSearchHit;
begin
  FCheck := False;
  View := Context.EditView;
  if (View = nil) or (View.Buffer = nil) or TAtlasIdeSearch.FLast.IsEmpty then
  begin
    FHits := nil;
    FKey := '';
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  FLines := TTextLines.SplitLines(Text);
  // Bei Bereich Methode hängt die Hervorhebung am Cursor; der wandert, also gehört er zum Schlüssel. Sonst nicht:
  // Jede Cursorzeile suchte die ganze Unit neu (#1227).
  Key := Context.FileName + #0 + IntToStr(TAtlasIdeSearch.FVersion) + #0 + Text;
  if TAtlasIdeSearch.FLast.Scope = TAtlasSearchScope.Method then
  begin
    Key := IntToStr(View.CursorPos.Line) + #0 + Key;
  end;
  if Key = FKey then
  begin
    Exit;
  end;
  FKey := Key;
  FHits := nil;
  SetLength(FHits, Length(FLines));
  FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  if not TAtlasIdeSearch.AreaOf(Text, TAtlasIdeSearch.FLast, TAtlasIdeSearch.CursorOf(View, FLines), Area) then
  begin
    Exit;
  end;
  for Hit in TAtlasTextSearch.FindAll(FLines, TAtlasIdeSearch.FLast.Text, TAtlasIdeSearch.FLast.Options, Area) do
  begin
    if Hit.Line <= High(FHits) then
    begin
      FHits[Hit.Line] := FHits[Hit.Line] + [Hit];
    end;
  end;
end;

procedure TAtlasIdeSearch.TPainter.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Line, First, Last: Integer;
  Hit: TAtlasSearchHit;
  LineState: INTACodeEditorLineState;
  Cell, LastCell, Frame: TRect;
  DC: HDC;
  Saved: Integer;
  Pen, Old: HGDIOBJ;
  Brush: HGDIOBJ;
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Search) then
  begin
    Exit;
  end;
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not TAtlasIdeSearch.FHighlight or
    TAtlasIdeSearch.FLast.IsEmpty then
  begin
    Exit;
  end;
  try
    if FCheck then
    begin
      Refresh(Context);
    end;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line > High(FHits)) or (Length(FHits[Line]) = 0) then
    begin
      Exit;
    end;
    // Nur, wenn die gezeichnete Zeile zum berechneten Text passt.
    LineState := Context.LineState;
    if (LineState = nil) or (TrimRight(LineState.Text) <> TrimRight(FLines[Line])) then
    begin
      Exit;
    end;
    DC := Context.Canvas.Handle;
    Saved := SaveDC(DC);
    try
      Pen := CreatePen(PS_SOLID, 1, ColorToRGB(TColor(TAtlasIdeStyle.Colors.Warn)));
      Old := SelectObject(DC, Pen);
      Brush := SelectObject(DC, GetStockObject(NULL_BRUSH));
      try
        for Hit in FHits[Line] do
        begin
          First := TAtlasPairs.ColumnOf(FLines[Line], Hit.Character, FTabWidth);
          Last := TAtlasPairs.ColumnOf(FLines[Line], Hit.Character + Hit.Length - 1, FTabWidth);
          Cell := Context.EditorState.GetCharacterPosPx(First, Context.EditorLineNum);
          LastCell := Context.EditorState.GetCharacterPosPx(Last, Context.EditorLineNum);
          Frame := TRect.Create(Cell.Left, Rect.Top, LastCell.Right, Rect.Bottom);
          Winapi.Windows.Rectangle(DC, Frame.Left, Frame.Top, Frame.Right, Frame.Bottom);
        end;
      finally
        SelectObject(DC, Brush);
        SelectObject(DC, Old);
        DeleteObject(Pen);
      end;
    finally
      RestoreDC(DC, Saved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FHits := nil;
      TAtlasGuard.Report(TAtlasFeature.Search, E);
    end;
  end;
end;

{ TAtlasIdeSearch.TProbeOwner }

procedure TAtlasIdeSearch.TProbeOwner.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Search, TAtlasIdeSearch.Probe);
end;

procedure TAtlasIdeSearch.TProbeOwner.FilesTick(Sender: TObject);
begin
  TAtlasIdeSearch.FFilesTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.Search,
    procedure
    begin
      // Nur, wenn die Leiste noch offen ist und der Bereich noch über Dateien geht.
      if (TAtlasIdeSearch.FBar <> nil) and TAtlasIdeSearch.FBar.Visible and
        TAtlasSearchScopes.SpansFiles(TAtlasIdeSearch.FLast.Scope) and not TAtlasIdeSearch.FilesCurrent then
      begin
        TAtlasIdeSearch.StartFiles(False, nil);
      end;
    end);
end;

{ TAtlasIdeSearch }

class procedure TAtlasIdeSearch.Install(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FPainter = nil then
  begin
    FPainter := TPainter.Create;
  end;
  if FHost = nil then
  begin
    FHost := TAtlasEditorBarHost.Create('Suchleiste', TAtlasFeature.Search,
      function(AEditorParent: TWinControl): TControl
      begin
        Result := CreateBar;
      end,
      procedure(ABar: TControl; AEditorParent: TWinControl)
      begin
        Place(TAtlasSearchBar(ABar), AEditorParent);
      end);
    FHost.OnRemoved :=
      procedure(ABar: TControl)
      begin
        Removed(ABar);
      end;
  end;
  if FProbeOwner = nil then
  begin
    FProbeOwner := TProbeOwner.Create(nil);
  end;
  if FProbe = nil then
  begin
    FProbe := TTimer.Create(FProbeOwner);
    FProbe.Enabled := False;
    FProbe.Interval := ProbeMs;
    FProbe.OnTimer := FProbeOwner.Tick;
  end;
  if FFilesTimer = nil then
  begin
    FFilesTimer := TTimer.Create(FProbeOwner);
    FFilesTimer.Enabled := False;
    FFilesTimer.Interval := FilesDelayMs;
    FFilesTimer.OnTimer := FProbeOwner.FilesTick;
  end;
  if FSearchHistory = nil then
  begin
    FSearchHistory := TAtlasSearchHistory.Create(TAtlasIdeSettings.Current.SearchHistory);
  end;
  if FReplaceHistory = nil then
  begin
    FReplaceHistory := TAtlasSearchHistory.Create(TAtlasIdeSettings.Current.SearchHistory);
  end;
  LoadHistories;
end;

class procedure TAtlasIdeSearch.Uninstall;
begin
  FreeAndNil(FPainter);
  // Erst die Suche über Dateien beenden (wartet auf den Thread), dann das Fenster und die Leisten.
  DropFiles;
  TAtlasIdeSearchReplaceWindow.Release;
  FreeAndNil(FHost);
  // Die Takte gehören ihrem Besitzer.
  FProbe := nil;
  FFilesTimer := nil;
  FEntered := nil;
  FreeAndNil(FProbeOwner);
  FBar := nil;
  FMessage := nil;
  FHighlight := False;
  FListedKey := '';
  FLast := Default(TAtlasSearchQuery);
  SaveHistories;
  FreeAndNil(FSearchHistory);
  FreeAndNil(FReplaceHistory);
  FHistoryKept := False;
end;

class procedure TAtlasIdeSearch.ApplySettings;
var
  Listed: Boolean;
begin
  Listed := TAtlasIdeSettings.Current.SearchResultsInMessages;
  if not Listed then
  begin
    TAtlasIdeSearchMessages.Clear;
    FListedKey := '';
  end;
  // Verlauf kürzen; 0 = aus (#893).
  if FSearchHistory <> nil then
  begin
    FSearchHistory.Capacity := TAtlasIdeSettings.Current.SearchHistory;
  end;
  if FReplaceHistory <> nil then
  begin
    FReplaceHistory.Capacity := TAtlasIdeSettings.Current.SearchHistory;
  end;
  SaveHistories;
  // Ohne Bereiche über Dateien bzw. ohne Ersetzen: laufende Suche und Fenster weg.
  if not TAtlasIdeSettings.Current.SearchMultiFile or not TAtlasIdeSettings.Current.SearchReplace then
  begin
    TAtlasIdeSearchReplaceWindow.Hide;
  end;
  if not TAtlasIdeSettings.Current.SearchMultiFile then
  begin
    DropFiles;
  end;
  if FHost <> nil then
  begin
    FHost.ForEach(
      procedure(ABar: TControl)
      begin
        TAtlasSearchBar(ABar).ListVisible := Listed;
        TAtlasSearchBar(ABar).Features := Features;
      end);
  end;
end;

class procedure TAtlasIdeSearch.ThemeChanged;
begin
  if FHost <> nil then
  begin
    FHost.ForEach(
      procedure(ABar: TControl)
      begin
        ThemeBar(TAtlasSearchBar(ABar));
      end);
  end;
  TAtlasIdeSearchReplaceWindow.ApplyTheme;
end;

class function TAtlasIdeSearch.Features: TAtlasSearchBarFeatures;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasSearchBarFeatures.Create(Settings.SearchReplace, Settings.SearchRegex, Settings.SearchMultiFile);
end;

class function TAtlasIdeSearch.TabWidth: Integer;
var
  View: IOTAEditView;
begin
  Result := 8;
  if TopView(View) then
  begin
    Result := TAtlasEditorBuffer.TabWidth(View.Buffer);
  end;
end;

{ Verlauf (#893) }

class function TAtlasIdeSearch.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'search-history.json');
end;

class procedure TAtlasIdeSearch.LoadHistories;
begin
  if (FSearchHistory = nil) or (FReplaceHistory = nil) then
  begin
    Exit;
  end;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert das ohne Pfad.
  FHistoryKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, HistoryKind,
    function(const AText: string): Boolean
    begin
      Result := TAtlasSearchHistories.FromText(AText, FSearchHistory, FReplaceHistory);
    end));
  if FHistoryKept then
  begin
    FSearchHistory.Clear;
    FReplaceHistory.Clear;
  end;
end;

class procedure TAtlasIdeSearch.SaveHistories;
begin
  if (FSearchHistory = nil) or (FReplaceHistory = nil) or FHistoryKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(HistoryFile, TAtlasSearchHistories.ToText(FSearchHistory, FReplaceHistory));
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(HistoryKind, E);
  end;
end;

class procedure TAtlasIdeSearch.ThemeBar(ABar: TAtlasSearchBar);
begin
  TAtlasIdeDockWindow.ApplyIdeTheme(ABar);
end;

class procedure TAtlasIdeSearch.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeSearch.TopView(out AView: IOTAEditView): Boolean;
var
  Editors: IOTAEditorServices;
begin
  AView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
  begin
    AView := Editors.TopView;
  end;
  Result := (AView <> nil) and (AView.Buffer <> nil);
end;

class function TAtlasIdeSearch.CursorOf(const AView: IOTAEditView; const ALines: TArray<string>): TAtlasSearchPos;
var
  Cursor: TOTAEditPos;
  Row: Integer;
  LineText: string;
begin
  Cursor := AView.CursorPos;
  Row := Cursor.Line - 1;
  LineText := '';
  if (Row >= 0) and (Row <= High(ALines)) then
  begin
    LineText := ALines[Row];
  end;
  Result := TAtlasSearchPos.Create(Row, TLspSession.ColumnToIndex(LineText, Cursor.Col,
    TAtlasEditorBuffer.TabWidth(AView.Buffer)));
end;

class function TAtlasIdeSearch.SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>;
  out AArea: TAtlasSearchArea): Boolean;
var
  Block: IOTAEditBlock;
  TabWidth: Integer;

  function Index(ARow, AColumn: Integer): Integer;
  var
    LineText: string;
  begin
    LineText := '';
    if (ARow >= 1) and (ARow <= Length(ALines)) then
    begin
      LineText := ALines[ARow - 1];
    end;
    Result := TLspSession.ColumnToIndex(LineText, AColumn, TabWidth);
  end;

begin
  AArea := TAtlasSearchArea.Create(0, 0, 0, 0);
  Block := AView.Block;
  Result := (Block <> nil) and Block.IsValid and (Block.Size > 0);
  if not Result then
  begin
    Exit;
  end;
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  AArea := TAtlasSearchArea.Create(Block.StartingRow - 1, Index(Block.StartingRow, Block.StartingColumn),
    Block.EndingRow - 1, Index(Block.EndingRow, Block.EndingColumn));
end;

class function TAtlasIdeSearch.AreaOf(const AText: string; const AQuery: TAtlasSearchQuery;
  const ACursor: TAtlasSearchPos; out AArea: TAtlasSearchArea): Boolean;
begin
  Result := TAtlasSearchScopes.AreaFor(AText, AQuery.Scope, ACursor, AQuery.Area, AQuery.Level, AArea);
  // Methode: Steht der Cursor (etwa nach einem Sprung) außerhalb jeder Routine, gilt die Routine beim Suchen.
  if not Result and (AQuery.Scope = TAtlasSearchScope.Method) and not AQuery.Area.IsEmpty then
  begin
    AArea := AQuery.Area;
    Result := True;
  end;
end;

class procedure TAtlasIdeSearch.SelectHit(const AView: IOTAEditView; const ALines: TArray<string>;
  const AHit: TAtlasSearchHit);
var
  TabWidth: Integer;
  LineText: string;
  Target: TOTAEditPos;
begin
  TabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  LineText := '';
  if (AHit.Line >= 0) and (AHit.Line <= High(ALines)) then
  begin
    LineText := ALines[AHit.Line];
  end;
  AView.Block.Style := btNonInclusive;
  Target.Line := AHit.Line + 1;
  Target.Col := TLspSession.IndexToColumn(LineText, AHit.Character, TabWidth);
  AView.CursorPos := Target;
  // Anfang markieren, Cursor ans Ende, Ende markieren: Der Cursor steht danach hinter dem Treffer.
  AView.Block.BeginBlock;
  Target.Col := TLspSession.IndexToColumn(LineText, AHit.Character + AHit.Length, TabWidth);
  AView.CursorPos := Target;
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class procedure TAtlasIdeSearch.Repaint;
var
  View: IOTAEditView;
begin
  Inc(FVersion);
  if TopView(View) then
  begin
    View.Paint;
  end;
end;

class function TAtlasIdeSearch.BarFor(const AWindow: INTAEditWindow): TAtlasSearchBar;
begin
  Result := nil;
  if FHost <> nil then
  begin
    Result := TAtlasSearchBar(FHost.EnsureFor(AWindow));
  end;
end;

/// <summary>Eigene Methode: Jede Leiste braucht ihre eigene gefangene Variable.</summary>
class function TAtlasIdeSearch.CreateBar: TAtlasSearchBar;
var
  Bar: TAtlasSearchBar;
begin
  Bar := TAtlasSearchBar.Create(nil);
  Result := Bar;
  Bar.Visible := False;
  Bar.OnQueryChanged :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search,
          procedure
          begin
            Sync(True);
          end);
      end;
    end;
  Bar.OnStep :=
    procedure(ABackward: Boolean)
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search,
          procedure
          begin
            BarStep(ABackward);
          end);
      end;
    end;
  Bar.OnList :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, BarList);
      end;
    end;
  Bar.OnClose :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, CloseBar);
      end;
    end;
  Bar.OnReplace :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, BarReplace);
      end;
    end;
  Bar.OnReplaceAll :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, BarReplaceAll);
      end;
    end;
  Bar.OnChoose :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, BarChoose);
      end;
    end;
  Bar.OnCancel :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, BarCancel);
      end;
    end;
  Bar.OnReplaceShown :=
    procedure
    begin
      if Bar = FBar then
      begin
        TAtlasGuard.Run(TAtlasFeature.Search, UpdatePreview);
      end;
    end;
  Bar.OnControlEnter :=
    procedure(AControl: TWinControl)
    begin
      if Bar = FBar then
      begin
        FEntered := AControl;
        FEnteredAt := TThread.GetTickCount64;
      end;
    end;
  // Verlauf und Teile nach den Einstellungen (#893); Platz und Farben setzt Place über den Host (#1248).
  Bar.SetHistories(FSearchHistory, FReplaceHistory);
  Bar.Features := Features;
end;

class procedure TAtlasIdeSearch.Place(ABar: TAtlasSearchBar; AParent: TWinControl);
begin
  if ABar.Parent = AParent then
  begin
    Exit;
  end;
  // Unter dem Editor: zuerst ganz unten einhängen, dann unten ausrichten.
  ABar.Top := AParent.ClientHeight;
  ABar.Align := alBottom;
  ABar.Parent := AParent;
  ThemeBar(ABar);
end;

class procedure TAtlasIdeSearch.Removed(ABar: TControl);
begin
  if FBar = ABar then
  begin
    FBar := nil;
    StopProbe;
  end;
end;

class procedure TAtlasIdeSearch.Open(AInMethod, AReplace: Boolean);
var
  View: IOTAEditView;
  Editors: INTAEditorServices;
  Bar: TAtlasSearchBar;
  Text, Proposal: string;
  Lines, Levels: TArray<string>;
  Cursor: TAtlasSearchPos;
  Selection: TAtlasSearchArea;
  HasSelection: Boolean;
  Query: TAtlasSearchQuery;
  Routine: TAtlasSearchRoutine;
begin
  if not TopView(View) or not Supports(BorlandIDEServices, INTAEditorServices, Editors) then
  begin
    Exit;
  end;
  Bar := BarFor(Editors.TopEditWindow);
  if Bar = nil then
  begin
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  Cursor := CursorOf(View, Lines);
  HasSelection := SelectionOf(View, Lines, Selection);
  // Vorschlag: einzeilige Markierung, sonst Bezeichner am Cursor, sonst die letzte Suche.
  Proposal := '';
  if HasSelection and (Selection.Start.Line = Selection.Stop.Line) and (Selection.Start.Line <= High(Lines)) then
  begin
    Proposal := Copy(Lines[Selection.Start.Line], Selection.Start.Character + 1,
      Selection.Stop.Character - Selection.Start.Character);
  end;
  if (Proposal = '') and (Cursor.Line >= 0) and (Cursor.Line <= High(Lines)) then
  begin
    Proposal := TAtlasTextSearch.WordAt(Lines[Cursor.Line], Cursor.Character);
  end;
  if Proposal = '' then
  begin
    Proposal := FLast.Text;
  end;
  // Bereich Unit; Methode nur mit „In Methode suchen“, mehrzeilige Markierung als Auswahl.
  Query := TAtlasSearchResults.StartQuery(FLast, Proposal,
    HasSelection and (Selection.Start.Line <> Selection.Stop.Line), AInMethod);
  Levels := nil;
  for Routine in TAtlasSearchScopes.RoutinesAt(Text, Cursor) do
  begin
    Levels := Levels + [Routine.Caption];
  end;
  // Ursprung der Suche: Anfang einer Markierung, sonst der Cursor.
  FOrigin := Cursor;
  if HasSelection then
  begin
    FOrigin := Selection.Start;
  end;
  FSelection := Selection;
  FFileName := View.Buffer.FileName;
  // Eine andere Leiste (anderes Editorfenster) beenden.
  if (FBar <> nil) and (FBar <> Bar) then
  begin
    FBar.Visible := False;
  end;
  FBar := Bar;
  Bar.ListVisible := TAtlasIdeSettings.Current.SearchResultsInMessages;
  Bar.Features := Features;
  // Strg+H mit, Strg+F ohne Ersetzen-Zeile.
  Bar.ReplaceShown := AReplace;
  Bar.Prepare(Query, Levels, HasSelection);
  Bar.Visible := True;
  // Vor alle Geschwister: Kein Fenster der IDE soll über der Leiste liegen.
  Bar.BringToFront;
  LogLayout(Bar);
  Bar.FocusText;
  FProbed := 0;
  FEntered := nil;
  if FProbe <> nil then
  begin
    FProbe.Enabled := True;
  end;
  // Hervorheben und zählen, ohne zu springen: Der Vorschlag steht meist schon am Cursor.
  Sync(False);
end;

class procedure TAtlasIdeSearch.Sync(AJump: Boolean);
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Query: TAtlasSearchQuery;
  Area: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Index: Integer;
  Wrapped: Boolean;
  Error: string;
begin
  if (FBar = nil) or not TopView(View) then
  begin
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  // Anderes Dokument im selben Fenster: neuer Ursprung am Cursor, Auswahl gilt nicht mehr.
  if not SameText(FFileName, View.Buffer.FileName) then
  begin
    FFileName := View.Buffer.FileName;
    FOrigin := CursorOf(View, Lines);
    FSelection := TAtlasSearchArea.Create(0, 0, 0, 0);
  end;
  Query := FBar.Query;
  Query.FileName := FFileName;
  // Ungültiger Ausdruck (#893): Feld rot, Fehlertext der Engine, nichts markiert, gezählt oder gesucht.
  if Query.Options.Regex and not TAtlasSearchRegex.Check(Query.Text, Error) then
  begin
    FLast := Query;
    FHighlight := False;
    DropFiles;
    Repaint;
    FBar.SetError(Error);
    FBar.SetCounter('');
    FBar.ClearPreview;
    Exit;
  end;
  FBar.SetError('');
  // Eine Meldung wie „12 Ersetzungen in 3 Dateien“ gilt bis zur nächsten Suche.
  FBar.SetNotice('');
  if not TAtlasSearchScopes.AreaFor(Text, Query.Scope, FOrigin, FSelection, Query.Level, Area) then
  begin
    Query.Area := TAtlasSearchArea.Create(0, 0, 0, 0);
    FLast := Query;
    FHighlight := False;
    Repaint;
    if Query.Scope = TAtlasSearchScope.Method then
    begin
      FBar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoMethod));
    end
    else
    begin
      FBar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoSelection));
    end;
    Exit;
  end;
  // Gemerkt wird der Bereich beim Suchen (Auswahl; Methode als Rückfall außerhalb jeder Routine).
  Query.Area := Area;
  FLast := Query;
  FHighlight := True;
  Repaint;
  Hits := TAtlasTextSearch.FindAll(Lines, Query.Text, Query.Options, Area);
  if AJump and (Length(Hits) > 0) then
  begin
    // Erster Treffer oder nächster ab der Stelle beim Öffnen (#1242, search.fromFirstHit).
    if TAtlasIdeSettings.Current.SearchFromFirstHit then
    begin
      Index := 0;
    end
    else
    begin
      Index := TAtlasTextSearch.Next(Hits, FOrigin, False, Wrapped);
    end;
    SelectHit(View, Lines, Hits[Index]);
  end;
  // Über Dateien: nach einer Pause im Tippen im Hintergrund; sonst gilt eine frühere Suche nicht mehr.
  if TAtlasSearchScopes.SpansFiles(Query.Scope) then
  begin
    ScheduleFiles;
  end
  else
  begin
    DropFiles;
  end;
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.UpdateCounter;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Area, Selection: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Index, Count, Files: Integer;
  At: TAtlasSearchPos;
begin
  if (FBar = nil) or not FBar.Visible or not TopView(View) then
  begin
    Exit;
  end;
  if FLast.Text = '' then
  begin
    FBar.SetCounter('');
    FBar.ClearPreview;
    Exit;
  end;
  UpdatePreview;
  // Über Dateien (#893): Treffer und Dateien der Suche im Hintergrund.
  if FilesCurrent then
  begin
    Count := FFiles.HitCount;
    Files := Length(FFiles.Results);
    if FFilesDone then
    begin
      FBar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCounter,
        [Count, Files, Plural(Files, TAtlasSearchTextId.SearchFileOne, TAtlasSearchTextId.SearchFileMany)]));
    end
    else
    begin
      FBar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesRunning,
        [Count, Files, Plural(Files, TAtlasSearchTextId.SearchFileOne, TAtlasSearchTextId.SearchFileMany)]));
    end;
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  At := CursorOf(View, Lines);
  if SelectionOf(View, Lines, Selection) then
  begin
    At := Selection.Start;
  end;
  Hits := nil;
  if AreaOf(Text, FLast, At, Area) then
  begin
    Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  end;
  if Length(Hits) = 0 then
  begin
    FBar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoHits));
    Exit;
  end;
  Index := TAtlasSearchResults.IndexAt(Hits, At);
  if Index >= 0 then
  begin
    FBar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchHitPosition, [Index + 1, Length(Hits)]));
  end
  else
  begin
    FBar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchHitCount, [Length(Hits)]));
  end;
end;

class procedure TAtlasIdeSearch.BarStep(ABackward: Boolean);
begin
  SaveHistories;
  Sync(False);
  TryNext(ABackward);
end;

class procedure TAtlasIdeSearch.BarList;
var
  View: IOTAEditView;
  Text, Key, Mode, Place: string;
  Lines: TArray<string>;
  Area: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Routines: TArray<TAtlasSearchRoutine>;
begin
  if (FBar = nil) or not TAtlasIdeSettings.Current.SearchResultsInMessages or not TopView(View) then
  begin
    Exit;
  end;
  SaveHistories;
  Sync(False);
  if FLast.IsEmpty or FLast.Area.IsEmpty or FBar.HasError then
  begin
    Exit;
  end;
  // Über Dateien (#893): die laufende bzw. fertige Suche auflisten, sonst eine neue beginnen.
  if TAtlasSearchScopes.SpansFiles(FLast.Scope) then
  begin
    if FilesCurrent then
    begin
      ListFiles;
    end
    else
    begin
      StartFiles(True, nil);
    end;
    if FBar <> nil then
    begin
      FBar.FocusText;
    end;
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  // Dieselbe Suche im selben Text nicht erneut aufbauen (Enter springt auch nur weiter).
  Key := FFileName + #0 + FLast.Text + #0 + BoolToStr(FLast.Options.CaseSensitive) +
    BoolToStr(FLast.Options.WholeWord) + BoolToStr(FLast.Options.Identifier) + BoolToStr(FLast.Options.Regex) + #0 +
    IntToStr(Ord(FLast.Scope)) + #0 +
    IntToStr(FLast.Area.Start.Line) + ':' + IntToStr(FLast.Area.Start.Character) + '-' +
    IntToStr(FLast.Area.Stop.Line) + ':' + IntToStr(FLast.Area.Stop.Character) + #0 + Text;
  if Key = FListedKey then
  begin
    Exit;
  end;
  FListedKey := Key;
  Lines := TTextLines.SplitLines(Text);
  Area := FLast.Area;
  Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  Mode := '';
  if FLast.Options.Identifier then
  begin
    Mode := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListIdentifier);
  end;
  Place := '';
  case FLast.Scope of
    TAtlasSearchScope.Method:
      begin
        Routines := TAtlasSearchScopes.RoutinesAt(Text, Area.Start);
        if Length(Routines) > 0 then
        begin
          Place := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchListScopeMethod,
            [TAtlasSearchResults.RoutineName(Routines[0].Caption)]);
        end;
      end;
    TAtlasSearchScope.Selection:
      Place := ', ' + TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeSelection);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
  TAtlasIdeSearchMessages.Show(FFileName, TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchListTitle,
    [FLast.Text, Mode, ExtractFileName(FFileName), Place, Length(Hits)]),
    TAtlasSearchResults.Entries(Lines, Hits, TAtlasEditorBuffer.TabWidth(View.Buffer)), Length(Hits));
  // Das Meldungsfenster nimmt beim Zeigen den Fokus; zurück in die Leiste.
  if FBar <> nil then
  begin
    FBar.FocusText;
  end;
end;

class procedure TAtlasIdeSearch.CloseBar;
var
  Bar: TAtlasSearchBar;
begin
  if FBar = nil then
  begin
    Exit;
  end;
  Bar := FBar;
  StopProbe;
  SaveHistories;
  if FFilesTimer <> nil then
  begin
    FFilesTimer.Enabled := False;
  end;
  // Eine laufende Suche über Dateien endet mit der Leiste; fertige Ergebnisse bleiben für F3.
  if TAtlasIdeFileSearch.Running then
  begin
    DropFiles;
  end;
  FBar.Visible := False;
  FHighlight := False;
  Repaint;
  TAtlasEditorBarHost.FocusEditor(Bar);
end;

class procedure TAtlasIdeSearch.StopProbe;
begin
  if FProbe <> nil then
  begin
    FProbe.Enabled := False;
  end;
  FEntered := nil;
  FProbed := 0;
end;

function WindowName(AWindow: HWND): string;
var
  WindowClass: array[0..255] of Char;
  Control: TWinControl;
begin
  if AWindow = 0 then
  begin
    Exit('kein Fenster');
  end;
  WindowClass[0] := #0;
  GetClassName(AWindow, WindowClass, Length(WindowClass));
  Result := string(WindowClass);
  Control := FindControl(AWindow);
  if Control <> nil then
  begin
    Result := Result + ', ' + Control.ClassName + ' ' + Control.Name;
  end;
end;

/// <summary>Einmal je Leiste: Lage von Editor und Leiste im gemeinsamen Eltern-Steuerelement (Diagnose).</summary>
class procedure TAtlasIdeSearch.LogLayout(ABar: TAtlasSearchBar);
var
  Parent: TWinControl;
  Index: Integer;
  Child: TControl;
  Parts: string;
begin
  if ABar.Tag <> 0 then
  begin
    Exit;
  end;
  ABar.Tag := 1;
  Parent := ABar.Parent;
  if Parent = nil then
  begin
    Exit;
  end;
  Parts := '';
  for Index := 0 to Parent.ControlCount - 1 do
  begin
    Child := Parent.Controls[Index];
    Parts := Parts + Format(' [%s %s Align %d, %d,%d %dx%d, sichtbar %s]', [Child.ClassName, Child.Name,
      Ord(Child.Align), Child.Left, Child.Top, Child.Width, Child.Height, BoolToStr(Child.Visible, True)]);
  end;
  TAtlasGuard.Log(Format('Suchleiste: in %s %s (%dx%d):%s', [Parent.ClassName, Parent.Name, Parent.ClientWidth,
    Parent.ClientHeight, Parts]));
end;

class procedure TAtlasIdeSearch.EnableBars;
begin
  // Beim Schließen aller Editoren (Projektwechsel) sperrt die IDE jedes Steuerelement im Editor-Panel und gibt danach
  // nur ihre eigenen wieder frei; die Suchleiste flackerte dann beim Klick nur kurz und blieb taub.
  if FHost <> nil then
  begin
    FHost.Enable;
  end;
end;

class procedure TAtlasIdeSearch.Probe;
var
  Bar: TAtlasSearchBar;
  Cursor: TPoint;
  Window: HWND;
begin
  EnableBars;
  Bar := FBar;
  if (Bar = nil) or not Bar.HandleAllocated or not Bar.Showing then
  begin
    Exit;
  end;
  // Kurz nach dem Klick in die Leiste wieder im Editor: Die IDE hat den Fokus zurückgeholt; einmal zurück.
  if (FEntered <> nil) and not Bar.HasFocus then
  begin
    if TThread.GetTickCount64 - FEnteredAt <= FocusGraceMs then
    begin
      TAtlasGuard.Log(Format('Suchleiste: Fokus nach dem Klick an %s %s verloren (an %s); hole ihn zurück',
        [FEntered.ClassName, FEntered.Name, WindowName(Winapi.Windows.GetFocus)]));
      if FEntered.CanFocus then
      begin
        FEntered.SetFocus;
      end;
    end;
    FEntered := nil;
  end;
  // Liegt über der Leiste ein anderes Fenster, bekommt sie keine Klicks: protokollieren, nach vorn holen.
  if not GetCursorPos(Cursor) or not PtInRect(Bar.ClientRect, Bar.ScreenToClient(Cursor)) then
  begin
    Exit;
  end;
  Window := WindowFromPoint(Cursor);
  if Window = FProbed then
  begin
    Exit;
  end;
  FProbed := Window;
  if (Window = Bar.Handle) or IsChild(Bar.Handle, Window) then
  begin
    Exit;
  end;
  TAtlasGuard.Log(Format('Suchleiste: Über der Leiste liegt ein anderes Fenster (%s); hole die Leiste nach vorn',
    [WindowName(Window)]));
  Bar.BringToFront;
end;

{ Suche über Dateien (#893) }

class function TAtlasIdeSearch.FilesKey(const AQuery: TAtlasSearchQuery): string;
begin
  Result := AQuery.Text + #0 + BoolToStr(AQuery.Options.CaseSensitive) + BoolToStr(AQuery.Options.WholeWord) +
    BoolToStr(AQuery.Options.Identifier) + BoolToStr(AQuery.Options.Regex) + #0 + IntToStr(Ord(AQuery.Scope));
end;

/// <summary>Gehört die Suche über Dateien (laufend oder fertig) zur letzten Suche?</summary>
class function TAtlasIdeSearch.FilesCurrent: Boolean;
begin
  Result := (FFiles <> nil) and TAtlasSearchScopes.SpansFiles(FLast.Scope) and (FFilesKey = FilesKey(FLast));
end;

class procedure TAtlasIdeSearch.ScheduleFiles;
begin
  if FilesCurrent or (FFilesTimer = nil) then
  begin
    Exit;
  end;
  // Andere Suche: Die alte gilt nicht mehr; die neue beginnt nach einer Pause im Tippen.
  DropFiles;
  FFilesTimer.Enabled := False;
  if FLast.Text <> '' then
  begin
    FFilesTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeSearch.StartFiles(AListed: Boolean; const AThen: TProc);
var
  Files: TArray<string>;
  Mode: string;
  After: TProc;
begin
  DropFiles;
  if FFilesTimer <> nil then
  begin
    FFilesTimer.Enabled := False;
  end;
  if FLast.Text = '' then
  begin
    Exit;
  end;
  FFilesKey := FilesKey(FLast);
  FFiles := TAtlasReplaceList.Create(FLast, ReplaceText);
  FFilesListed := AListed and TAtlasIdeSettings.Current.SearchResultsInMessages;
  FAfterFiles := AThen;
  if FFilesListed then
  begin
    Mode := '';
    if FLast.Options.Identifier then
    begin
      Mode := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListIdentifier);
    end;
    TAtlasIdeSearchMessages.Start(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesTitle,
      [FLast.Text, Mode, TAtlasSearchBar.ScopeCaption(FLast.Scope)]));
  end;
  Files := TAtlasIdeFileSearch.FilesOf(FLast.Scope);
  if not TAtlasIdeFileSearch.Start(Files, FFileName, FLast,
    procedure(AHits: TAtlasFileHits)
    begin
      FileFound(AHits);
    end,
    procedure(ASummary: TAtlasFileSearchSummary)
    begin
      FilesDone(ASummary);
    end) then
  begin
    // Keine Datei im Bereich (kein Projekt geöffnet): fertig mit nichts.
    FFilesDone := True;
    if FFilesListed then
    begin
      TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoFiles));
    end;
    After := FAfterFiles;
    FAfterFiles := nil;
    if FBar <> nil then
    begin
      FBar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoFiles));
    end;
    if Assigned(After) then
    begin
      After();
    end;
    Exit;
  end;
  if FBar <> nil then
  begin
    FBar.SetSearching(True);
  end;
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.FileFound(const AHits: TAtlasFileHits);
begin
  if FFiles = nil then
  begin
    Exit;
  end;
  FFiles.Add(AHits);
  if FFilesListed then
  begin
    TAtlasIdeSearchMessages.AddFile(AHits.FileName, TAtlasSearchResults.Entries(AHits.Lines, AHits.Hits, TabWidth));
  end;
  UpdateCounter;
  RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearch.FilesDone(const ASummary: TAtlasFileSearchSummary);
var
  After: TProc;
begin
  if FFiles = nil then
  begin
    Exit;
  end;
  FFilesDone := True;
  if FBar <> nil then
  begin
    FBar.SetSearching(False);
  end;
  if FFilesListed then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesDone,
      [ASummary.Hits, ASummary.FilesWithHits, ASummary.Files]));
    if ASummary.Skipped > 0 then
    begin
      TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesSkipped,
        [ASummary.Skipped]));
    end;
    if ASummary.Cancelled then
    begin
      TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCancelled,
        [ASummary.Files]));
    end;
  end;
  UpdateCounter;
  if ASummary.Cancelled and (FBar <> nil) then
  begin
    FBar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCancelled, [ASummary.Files]));
  end;
  RefreshReplaceWindow('');
  // Was auf die fertige Suche gewartet hat (Alle ersetzen, F3); nicht nach einem Abbruch.
  After := FAfterFiles;
  FAfterFiles := nil;
  if Assigned(After) and not ASummary.Cancelled then
  begin
    After();
  end;
end;

/// <summary>Ergebnisse der aktuellen Suche über Dateien in den Reiter „Atlas-Suche“ (Enter nach der Suche).</summary>
class procedure TAtlasIdeSearch.ListFiles;
var
  Item: TAtlasFileHits;
  Mode: string;
  Width: Integer;
begin
  if (FFiles = nil) or FFilesListed or not TAtlasIdeSettings.Current.SearchResultsInMessages then
  begin
    Exit;
  end;
  FFilesListed := True;
  Mode := '';
  if FLast.Options.Identifier then
  begin
    Mode := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListIdentifier);
  end;
  TAtlasIdeSearchMessages.Start(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesTitle,
    [FLast.Text, Mode, TAtlasSearchBar.ScopeCaption(FLast.Scope)]));
  Width := TabWidth;
  for Item in FFiles.Results do
  begin
    TAtlasIdeSearchMessages.AddFile(Item.FileName, TAtlasSearchResults.Entries(Item.Lines, Item.Hits, Width));
  end;
  if FFilesDone then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCounter, [FFiles.HitCount,
      Length(FFiles.Results), Plural(Length(FFiles.Results), TAtlasSearchTextId.SearchFileOne,
      TAtlasSearchTextId.SearchFileMany)]));
  end;
end;

/// <summary>Suche über Dateien beenden und vergessen (Thread beendet, Fenster leer).</summary>
class procedure TAtlasIdeSearch.DropFiles;
begin
  if FFilesTimer <> nil then
  begin
    FFilesTimer.Enabled := False;
  end;
  TAtlasIdeFileSearch.Stop;
  FAfterFiles := nil;
  FFilesKey := '';
  FFilesDone := False;
  FFilesListed := False;
  if FBar <> nil then
  begin
    FBar.SetSearching(False);
  end;
  if FFiles = nil then
  begin
    Exit;
  end;
  FreeAndNil(FFiles);
  RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearch.RefreshReplaceWindow(const ANotice: string);
var
  Frame: TAtlasSearchReplaceFrame;
begin
  Frame := TAtlasIdeSearchReplaceWindow.ExistingFrame;
  if Frame = nil then
  begin
    Exit;
  end;
  if FFiles <> nil then
  begin
    FFiles.Replace := ReplaceText;
  end;
  Frame.SetModel(FFiles);
  if ANotice <> '' then
  begin
    Frame.SetNotice(ANotice);
  end;
end;

class procedure TAtlasIdeSearch.OpenHit(const AFileName: string; ALine, ACharacter: Integer);
var
  View: IOTAEditView;
  Lines: TArray<string>;
  Hits: TArray<TAtlasSearchHit>;
  Area: TAtlasSearchArea;
  Index: Integer;
  Wrapped: Boolean;
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine, 0);
  if not TopView(View) or not SameText(View.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Mit dem aktuellen Text: Der Treffer kann sich seit der Suche verschoben haben.
  Lines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(View.Buffer));
  Area := TAtlasSearchArea.Whole(Lines);
  Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  if Length(Hits) = 0 then
  begin
    Exit;
  end;
  Index := TAtlasTextSearch.Next(Hits, TAtlasSearchPos.Create(ALine, ACharacter), False, Wrapped);
  SelectHit(View, Lines, Hits[Index]);
  Repaint;
end;

class function TAtlasIdeSearch.NextAcrossFiles(ABackward: Boolean): Boolean;
var
  View: IOTAEditView;
  Lines: TArray<string>;
  Results: TArray<TAtlasFileHits>;
  Active: TAtlasFileHits;
  Selection: TAtlasSearchArea;
  From: TAtlasSearchPos;
  FileIndex, HitIndex, Index: Integer;
  Wrapped: Boolean;
begin
  Result := True;
  if not TopView(View) then
  begin
    Exit(False);
  end;
  if not FilesCurrent then
  begin
    // Noch keine Suche über Dateien (Leiste zu): suchen, dann springen.
    StartFiles(False,
      procedure
      begin
        if FilesCurrent then
        begin
          NextAcrossFiles(ABackward);
        end;
      end);
    Exit;
  end;
  if not FFilesDone and (Length(FFiles.Results) = 0) then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchFilesWait));
    Exit;
  end;
  // Die aktive Datei mit ihrem aktuellen Text, die übrigen wie gefunden.
  Lines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(View.Buffer));
  Active := TAtlasFileSearch.SearchText(View.Buffer.FileName, TAtlasEditorBuffer.Text(View.Buffer), FLast);
  Results := Copy(FFiles.Results);
  Index := TAtlasFileSearch.IndexOfFile(Results, View.Buffer.FileName);
  if Index >= 0 then
  begin
    Results[Index] := Active;
  end
  else if Length(Active.Hits) > 0 then
  begin
    Results := TArray<TAtlasFileHits>.Create(Active) + Results;
  end;
  From := CursorOf(View, Lines);
  if ABackward and SelectionOf(View, Lines, Selection) then
  begin
    From := Selection.Start;
  end;
  if not TAtlasFileSearch.NextLocation(Results, View.Buffer.FileName, From, ABackward, FileIndex, HitIndex,
    Wrapped) then
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchNothing, [FLast.Text]));
    Exit;
  end;
  if Wrapped then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWrapped));
  end;
  if SameText(Results[FileIndex].FileName, View.Buffer.FileName) then
  begin
    SelectHit(View, Lines, Results[FileIndex].Hits[HitIndex]);
    UpdateCounter;
  end
  else
  begin
    OpenHit(Results[FileIndex].FileName, Results[FileIndex].Hits[HitIndex].Line,
      Results[FileIndex].Hits[HitIndex].Character);
  end;
end;

{ Ersetzen (#893) }

class function TAtlasIdeSearch.ReplaceText: string;
begin
  Result := '';
  if FBar <> nil then
  begin
    Result := FBar.ReplaceText;
  end;
end;

/// <summary>Index des Treffers, der genau markiert ist; -1 ohne.</summary>
class function TAtlasIdeSearch.MarkedHit(const AView: IOTAEditView; const ALines: TArray<string>;
  const AHits: TArray<TAtlasSearchHit>): Integer;
var
  Selection: TAtlasSearchArea;
  Index: Integer;
begin
  Result := -1;
  if not SelectionOf(AView, ALines, Selection) then
  begin
    Exit;
  end;
  for Index := 0 to High(AHits) do
  begin
    if (TAtlasSearchPos.Compare(AHits[Index].StartPos, Selection.Start) = 0) and
      (TAtlasSearchPos.Compare(AHits[Index].StopPos, Selection.Stop) = 0) then
    begin
      Exit(Index);
    end;
  end;
end;

class procedure TAtlasIdeSearch.UpdatePreview;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Area, Selection: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  At: TAtlasSearchPos;
  Index: Integer;
  Preview: TAtlasReplacePreview;
begin
  if FBar = nil then
  begin
    Exit;
  end;
  // Vorschau nur mit Regex und offener Ersetzen-Zeile; ohne Regex ist der neue Text das Feld selbst.
  if not FBar.ReplaceShown or not FLast.Options.Regex or FBar.HasError or (FLast.Text = '') or
    not TopView(View) then
  begin
    FBar.ClearPreview;
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  At := CursorOf(View, Lines);
  if SelectionOf(View, Lines, Selection) then
  begin
    At := Selection.Start;
  end;
  Hits := nil;
  if AreaOf(Text, FLast, At, Area) then
  begin
    Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  end;
  Index := TAtlasSearchResults.IndexAt(Hits, At);
  if Index < 0 then
  begin
    FBar.ClearPreview;
    Exit;
  end;
  Preview := TAtlasSearchReplace.Preview(Lines, Hits[Index], FLast, ReplaceText);
  FBar.SetPreview(Preview.Before, Preview.After);
end;

class procedure TAtlasIdeSearch.Notice(const AText: string);
begin
  if FBar <> nil then
  begin
    FBar.SetNotice(AText);
  end;
end;

class procedure TAtlasIdeSearch.BarReplace;
var
  View: IOTAEditView;
  Text, NewText, Error: string;
  Lines: TArray<string>;
  Area: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  Index: Integer;
  Edit: TLspWorkspaceEdit;
  Changes: TLspFileEdits;
  Hit: TAtlasSearchHit;
  Target: TOTAEditPos;
  LineText: string;
begin
  SaveHistories;
  if (FBar = nil) or not TopView(View) then
  begin
    Exit;
  end;
  Sync(False);
  if FBar.HasError or FLast.IsEmpty then
  begin
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  Hits := nil;
  if AreaOf(Text, FLast, CursorOf(View, Lines), Area) then
  begin
    Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  end;
  Index := MarkedHit(View, Lines, Hits);
  // Kein Treffer markiert: erst hinspringen, der nächste Klick ersetzt.
  if Index < 0 then
  begin
    TryNext(False);
    Exit;
  end;
  if View.Buffer.IsReadOnly then
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceReadOnly, [ExtractFileName(View.Buffer.FileName)]));
    Exit;
  end;
  Hit := Hits[Index];
  Changes.FileName := View.Buffer.FileName;
  Changes.Edits := TAtlasSearchReplace.Edits(Lines, [Hit], FLast, ReplaceText);
  NewText := Changes.Edits[0].NewText;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Changes];
  Error := ApplyEdit(Edit, TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceAction, [FLast.Text, ReplaceText]));
  if Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Error]));
    Exit;
  end;
  // Weiter hinter dem neuen Text: Enthält er den Suchtext, wird er nicht gleich wieder gefunden.
  Lines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(View.Buffer));
  LineText := '';
  if Hit.Line <= High(Lines) then
  begin
    LineText := Lines[Hit.Line];
  end;
  Target.Line := Hit.Line + 1;
  Target.Col := TLspSession.IndexToColumn(LineText, Hit.Character + Length(NewText),
    TAtlasEditorBuffer.TabWidth(View.Buffer));
  View.Block.Reset;
  View.CursorPos := Target;
  Repaint;
  TryNext(False);
end;

class procedure TAtlasIdeSearch.BarReplaceAll;
var
  View: IOTAEditView;
  Lines: TArray<string>;
  Hits: TArray<TAtlasSearchHit>;
  Edit: TLspWorkspaceEdit;
  Changes: TLspFileEdits;
  Error: string;
begin
  SaveHistories;
  if (FBar = nil) or not TopView(View) then
  begin
    Exit;
  end;
  Sync(False);
  if FBar.HasError or FLast.IsEmpty then
  begin
    Exit;
  end;
  // Über Dateien: frisch suchen (Ergebnisse von vorhin können veraltet sein), dann alle Treffer ersetzen.
  if TAtlasSearchScopes.SpansFiles(FLast.Scope) then
  begin
    StartFiles(FFilesListed,
      procedure
      var
        Index: Integer;
      begin
        if FFiles = nil then
        begin
          Exit;
        end;
        for Index := 0 to High(FFiles.Results) do
        begin
          FFiles.SetFileChecked(Index, True);
        end;
        ReplaceChosen;
      end);
    Exit;
  end;
  // Eine Datei: alle Treffer im Bereich als ein Rückgängig-Schritt (ein Schreiber der IDE).
  Lines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(View.Buffer));
  Hits := nil;
  if not FLast.Area.IsEmpty then
  begin
    Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, FLast.Area);
  end;
  if Length(Hits) = 0 then
  begin
    Notice(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceNone));
    Exit;
  end;
  if View.Buffer.IsReadOnly then
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceReadOnly, [ExtractFileName(View.Buffer.FileName)]));
    Exit;
  end;
  Changes.FileName := View.Buffer.FileName;
  Changes.Edits := TAtlasSearchReplace.Edits(Lines, Hits, FLast, ReplaceText);
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Changes];
  Error := ApplyEdit(Edit, TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceAction, [FLast.Text, ReplaceText]));
  if Error <> '' then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Error]));
    Notice(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Error]));
    Exit;
  end;
  Notice(ReplacedText(Length(Hits), 1));
  Repaint;
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.BarChoose;
var
  View: IOTAEditView;
  Frame: TAtlasSearchReplaceFrame;
  Item: TAtlasFileHits;
begin
  SaveHistories;
  if (FBar = nil) or not TopView(View) then
  begin
    Exit;
  end;
  Sync(False);
  if FBar.HasError or FLast.IsEmpty then
  begin
    Exit;
  end;
  Frame := TAtlasIdeSearchReplaceWindow.Show;
  if Frame = nil then
  begin
    Exit;
  end;
  Frame.OnReplace :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Search, ReplaceChosen);
    end;
  Frame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Search,
        procedure
        begin
          OpenHit(AFileName, ALine, ACharacter);
        end);
    end;
  Frame.SetNotice('');
  if TAtlasSearchScopes.SpansFiles(FLast.Scope) then
  begin
    if not FilesCurrent then
    begin
      StartFiles(FFilesListed, nil);
    end;
  end
  else
  begin
    // Eine Datei: ihre Treffer im Bereich als Liste.
    DropFiles;
    Item := TAtlasFileSearch.SearchText(View.Buffer.FileName, TAtlasEditorBuffer.Text(View.Buffer), FLast);
    Item.Hits := nil;
    if not FLast.Area.IsEmpty then
    begin
      Item.Hits := TAtlasTextSearch.FindAll(Item.Lines, FLast.Text, FLast.Options, FLast.Area);
    end;
    FFiles := TAtlasReplaceList.Create(FLast, ReplaceText);
    FFiles.Add(Item);
    FFilesDone := True;
  end;
  RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearch.BarCancel;
begin
  TAtlasIdeFileSearch.Cancel;
end;

class procedure TAtlasIdeSearch.ReplaceChosen;
var
  Plan: TAtlasReplacePlan;
  FileName, Error, Report: string;
begin
  if FFiles = nil then
  begin
    Exit;
  end;
  FFiles.Replace := ReplaceText;
  Plan := FFiles.Plan(
    function(const AFileName: string): Boolean
    begin
      Result := IsReadOnlyFile(AFileName);
    end,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  // Vorab melden, was übersprungen wird.
  for FileName in Plan.ReadOnly do
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceReadOnly, [FileName]));
  end;
  for FileName in Plan.Changed do
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceChanged, [FileName]));
  end;
  if Plan.Replacements = 0 then
  begin
    Report := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceNone);
  end
  else
  begin
    Error := ApplyEdit(Plan.Edit, TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceAction, [FFiles.Query.Text,
      FFiles.Replace]));
    if Error <> '' then
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Error]));
      Report := TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Error]);
    end
    else
    begin
      Report := ReplacedText(Plan.Replacements, Plan.Files);
    end;
  end;
  if Length(Plan.ReadOnly) + Length(Plan.Changed) > 0 then
  begin
    Report := Report + ' · ' + TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceSkipped,
      [Length(Plan.ReadOnly) + Length(Plan.Changed)]);
  end;
  Say(Report);
  Notice(Report);
  // Die Ergebnisse stimmen nicht mehr: vergessen, das Fenster zeigt die Meldung.
  DropFiles;
  RefreshReplaceWindow(Report);
  Repaint;
  if (FBar <> nil) and FBar.Visible and TAtlasSearchScopes.SpansFiles(FLast.Scope) then
  begin
    ScheduleFiles;
  end;
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.Show;
begin
  EnableBars;
  Open(False, False);
end;

class procedure TAtlasIdeSearch.ShowInMethod;
begin
  EnableBars;
  Open(True, False);
end;

class procedure TAtlasIdeSearch.ShowReplace;
begin
  EnableBars;
  Open(False, TAtlasIdeSettings.Current.SearchReplace);
end;

class function TAtlasIdeSearch.TryNext(ABackward: Boolean): Boolean;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Area, Selection: TAtlasSearchArea;
  Hits: TArray<TAtlasSearchHit>;
  From: TAtlasSearchPos;
  Index: Integer;
  Wrapped, HasSelection, Changed: Boolean;
begin
  Result := False;
  if FLast.IsEmpty or not TopView(View) then
  begin
    Exit;
  end;
  // Über Dateien (#893): mit den Ergebnissen der Suche im Hintergrund.
  if TAtlasSearchScopes.SpansFiles(FLast.Scope) and TAtlasIdeSettings.Current.SearchMultiFile then
  begin
    Exit(NextAcrossFiles(ABackward));
  end;
  // Auswahl gilt nur in der Datei, in der gesucht wurde; in anderen Dateien die ganze Unit.
  if (FLast.Scope = TAtlasSearchScope.Selection) and not SameText(FLast.FileName, View.Buffer.FileName) then
  begin
    FLast.Scope := TAtlasSearchScope.UnitFile;
  end;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  From := CursorOf(View, Lines);
  HasSelection := SelectionOf(View, Lines, Selection);
  // Anderer Text markiert als zuletzt gesucht: nach der Markierung suchen.
  if HasSelection and (Selection.Start.Line = Selection.Stop.Line) and (Selection.Start.Line <= High(Lines)) then
  begin
    FLast := TAtlasSearchResults.FollowSelection(FLast, Copy(Lines[Selection.Start.Line],
      Selection.Start.Character + 1, Selection.Stop.Character - Selection.Start.Character), Changed);
    if Changed then
    begin
      FLast.FileName := View.Buffer.FileName;
      Repaint;
    end;
  end;
  // Vorwärts ab dem Ende der Markierung (dem Cursor), rückwärts ab ihrem Anfang.
  if ABackward and HasSelection then
  begin
    From := Selection.Start;
  end;
  if not AreaOf(Text, FLast, From, Area) then
  begin
    if FLast.Scope <> TAtlasSearchScope.Method then
    begin
      Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoSelection));
      Exit(True);
    end;
    // Außerhalb jeder Routine: die ganze Unit statt gar nichts.
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchOutsideMethod));
    Area := TAtlasSearchArea.Whole(Lines);
  end;
  Hits := TAtlasTextSearch.FindAll(Lines, FLast.Text, FLast.Options, Area);
  Result := True;
  if Length(Hits) = 0 then
  begin
    Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchNothing, [FLast.Text]));
    Exit;
  end;
  Index := TAtlasTextSearch.Next(Hits, From, ABackward, Wrapped);
  if Wrapped then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWrapped));
  end;
  SelectHit(View, Lines, Hits[Index]);
  UpdateCounter;
end;

class procedure TAtlasIdeSearch.FindNext;
begin
  if not TryNext(False) then
  begin
    Show;
  end;
end;

class procedure TAtlasIdeSearch.FindPrevious;
begin
  if not TryNext(True) then
  begin
    Show;
  end;
end;

class procedure TAtlasIdeSearch.ClearHighlights;
begin
  if (FBar <> nil) and FBar.Visible then
  begin
    CloseBar;
  end
  else
  begin
    FHighlight := False;
    Repaint;
  end;
end;

end.
