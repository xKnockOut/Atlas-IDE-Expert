unit Atlas.IDE.Results.Commands;

// Befehle des Ergebnisfensters (#400) im Menü Atlas und in der
// Befehlspalette: Referenzen (samt Fundstellen in .dfm) und
// Implementierungen des Symbols am Cursor, Aufrufer und Aufrufe, Vorfahren und
// Nachfahren als Baum, dessen Ebenen beim Aufklappen nachgeladen werden, und
// die projektweite Symbolsuche in einem Fenster wie die Befehlspalette. Das
// Aufrufdiagramm (#1122) zeigt die Aufrufhierarchie gleich als Diagramm,
// ausgehend; nur solange callHierarchy.diagram an ist.
// Vor jeder Anfrage bekommt der Server den aktuellen Text der offenen Dateien.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.
// Alle Anfragen an den Server laufen im Hintergrund (TAtlasBackgroundQueue), die Suchen gehen über das ganze
// Projekt und dürfen die IDE nicht anhalten: Referenzen (Befehl, Brotkrumen, „Verwendungen“ im Tooltip),
// Implementierungen, Hierarchien, Datenfluss und das Aufklappen ihrer Bäume. Ein Befehl während eines laufenden
// ersetzt ihn (nur der jüngste zeigt sein Ergebnis); Aufklappen reiht sich ein. Einträge und Ergebnisfenster
// entstehen im Hauptthread.
// Datenfluss (#690): „Woher kommt der Wert?“ und „Wohin geht der Wert?“ als Baum; jede aufgeklappte Quelle
// fragt mit dem Pfad ihrer Vorfahren und den Filtern der ersten Anfrage nach (navigation.dataFlow).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Plugin.Lsp.DataFlow,
  Atlas.Plugin.Lsp.BackgroundRequest,
  Atlas.Core.Results.Model,
  Atlas.UI.Results.CallDiagram,
  Atlas.UI.Results.DataFlow;

type
  /// <summary>Referenzen sind gezeigt: Anzahl der Fundstellen, -1, wenn die Suche scheiterte.</summary>
  TAtlasReferencesDone = TProc<Integer>;

  TAtlasIdeResults = class
  private
    class var FSessionOf: TFunc<TLspSession>;
    class var FMessage: TProc<string>;
    /// <summary>Erste Anfrage des zuletzt gezeigten Datenflusses; Filter und Folgeanfragen bauen darauf.</summary>
    class var FFlowRequest: TAtlasDataFlowRequest;
    /// <summary>Wort am Cursor zur ersten Anfrage, für den Titel eines leeren Baums.</summary>
    class var FFlowName: string;
    class var FQueue: TAtlasBackgroundQueue;
    /// <summary>Anfragen an den Server, angelegt beim ersten Gebrauch.</summary>
    class function Queue: TAtlasBackgroundQueue; static;
    /// <summary>Befehl: AWork im Hintergrund, danach AShow im Hauptthread; ersetzt einen laufenden Befehl. Scheitert
    /// die Anfrage, nur eine Zeile in der Meldungsansicht und AFailed (darf nil sein).</summary>
    class procedure RunCommand(const AWork, AShow, AFailed: TProc); static;
    class procedure ShowReferenceList(const AName: string; const ALocations: TArray<TLspLocation>;
      const ADone: TAtlasReferencesDone); static;
    class procedure ShowImplementationList(const AName: string; const ALocations: TArray<TLspLocation>); static;
    class procedure ShowHierarchyRoots(ADirection: TAtlasHierarchyDirection; const ARoots: TArray<TAtlasHierarchyItem>;
      AAsDiagram: Boolean); static;
    class procedure ShowFlow(const AFound: TAtlasDataFlowResult; AFromFilter: Boolean); static;
    /// <summary>Nächste Ebene einer Hierarchie im Hintergrund; ADone bekommt sie, leer bei Fehler.</summary>
    class procedure ExpandHierarchy(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem;
      const ADone: TAtlasCallLoaded); static;
    class function Entries(const ALocations: TArray<TLspLocation>): TArray<TAtlasResultEntry>; static;
    /// <summary>Erste Ebene holen und zeigen; AFromFilter: kein „nichts gefunden“, der Baum leert sich nur.</summary>
    class procedure RunDataFlow(AFromFilter: Boolean); static;
    class procedure ExpandDataFlow(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
      const APath: TArray<string>; const ADone: TAtlasDataFlowLoaded); static;
  public
    /// <summary>ASessionOf: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Laufende Sitzung oder nil; startet keinen Server (auch für das Suchfeld der Willkommensseite,
    /// #760).</summary>
    class function Session: TLspSession; static;
    /// <summary>Zeile für die Meldungsansicht (auch für Definition einblenden, #505).</summary>
    class procedure Say(const AText: string); static;
    /// <summary>Symbol am Cursor: Datei, Position und Name; False (mit Meldung) ohne Server oder Editor. Gleicht
    /// vorher alle offenen Puffer mit dem Server ab.</summary>
    class function AtCursor(out AFileName: string; out ALine, ACharacter: Integer; out AName: string): Boolean; static;
    class procedure FindReferences; static;
    class procedure FindImplementations; static;
    class procedure ShowHierarchy(ADirection: TAtlasHierarchyDirection); overload; static;
    /// <summary>Wie oben; AAsDiagram: gleich als Aufrufdiagramm (#1122).</summary>
    class procedure ShowHierarchy(ADirection: TAtlasHierarchyDirection; AAsDiagram: Boolean); overload; static;
    /// <summary>Befehl „Aufrufdiagramm“ (#1122): ausgehende Aufrufe des Symbols am Cursor als Diagramm.</summary>
    class procedure ShowCallDiagram; static;
    /// <summary>callHierarchy.diagram an?</summary>
    class function CallDiagramAllowed: Boolean; static;
    /// <summary>Datenfluss des Symbols am Cursor (#690); nur mit navigation.dataFlow.</summary>
    class procedure ShowDataFlow(ADirection: TAtlasDataFlowDirection); overload; static;
    /// <summary>Datenfluss des Symbols an AFileName/ALine/ACharacter (0-basiert), etwa „Wo wird Kunde
    /// zugewiesen?“ aus der Exception-Leiste (#865).</summary>
    class procedure ShowDataFlow(ADirection: TAtlasDataFlowDirection; const AFileName: string; ALine,
      ACharacter: Integer; const AName: string); overload; static;
    class procedure SearchSymbol; static;
    /// <summary>Referenzen auf ein Symbol an einem Fundort (z. B. aus dem Tooltip) im Ergebnisfenster; die Suche
    /// läuft im Hintergrund, danach ADone (darf nil sein) mit der Anzahl der Fundstellen.</summary>
    class procedure ShowReferences(const AFileName: string; ALine, ACharacter: Integer; const AName: string;
      const ADone: TAtlasReferencesDone); static;
    /// <summary>Ergebnisfenster zeigen.</summary>
    class procedure ShowWindow; static;
    class procedure Open(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  System.Types,
  Atlas.Plugin.Diagnostics.Guard,
  ToolsAPI,
  Atlas.Plugin.Lsp.Client,
  Atlas.Core.Results.Plan,
  Atlas.Core.Commands.Palette,
  Atlas.Plugin.Localization.Strings,
  Atlas.UI.Results.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.ToolsApi.Theme.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.ToolsApi.Files.Service,
  Atlas.IDE.Foundation.Host,
  Atlas.Plugin.Notifications.MessageSink;

const
  // Beim Tippen: lieber leer als die IDE aufhalten.
  cSymbolTimeoutMs = 1500;

function ReadText(const AFileName: string): string;
begin
  Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
end;

/// <summary>Symbole zum Muster; leer ohne Server, ohne Muster oder bei Fehler.</summary>
function QuerySymbols(const APattern: string): TArray<TAtlasSymbol>;
var
  mCurrent: TLspSession;
begin
  Result := nil;
  mCurrent := TAtlasIdeResults.Session;
  if (mCurrent = nil) or (Trim(APattern) = '') then
  begin
    Exit;
  end;
  try
    Result := mCurrent.WorkspaceSymbols(Trim(APattern), cSymbolTimeoutMs);
  except
    on ELspClientError do
      Result := nil;
  end;
end;

{ TAtlasIdeResults }

class function TAtlasIdeResults.Entries(const ALocations: TArray<TLspLocation>): TArray<TAtlasResultEntry>;
var
  mLocation: TLspLocation;
  mEntry: TAtlasResultEntry;
begin
  Result := nil;
  for mLocation in ALocations do
  begin
    mEntry := TAtlasResultEntry.Create(mLocation.FileName, mLocation.Line, mLocation.Character);
    mEntry.Confidence := mLocation.Confidence;
    Result := Result + [mEntry];
  end;
  TAtlasResults.FillText(Result,
    function(const AFileName: string): string
    begin
      Result := ReadText(AFileName);
    end);
end;

class function TAtlasIdeResults.Queue: TAtlasBackgroundQueue;
begin
  if FQueue = nil then
  begin
    FQueue := TAtlasBackgroundQueue.Create(TAtlasFeature.Results);
  end;
  Result := FQueue;
end;

/// <summary>Abschluss eines Befehls: AShow bzw. Meldung und AFailed, unter der Sicherung.</summary>
function CommandDone(const AShow, AFailed: TProc): TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      try
        if AOk then
        begin
          AShow();
        end
        else
        begin
          TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [AError]));
          if Assigned(AFailed) then
          begin
            AFailed();
          end;
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Results, E);
      end;
    end;
end;

class procedure TAtlasIdeResults.RunCommand(const AWork, AShow, AFailed: TProc);
begin
  Queue.AddLatest(AWork, CommandDone(AShow, AFailed));
end;

class procedure TAtlasIdeResults.RunDataFlow(AFromFilter: Boolean);
var
  mCurrent: TLspSession;
  mRequest: TAtlasDataFlowRequest;
  mFound: TAtlasDataFlowResult;
begin
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mRequest := FFlowRequest;
  mFound := Default(TAtlasDataFlowResult);
  RunCommand(
    procedure
    begin
      mFound := mCurrent.DataFlow(mRequest);
    end,
    procedure
    begin
      ShowFlow(mFound, AFromFilter);
    end,
    nil);
end;

class procedure TAtlasIdeResults.ShowFlow(const AFound: TAtlasDataFlowResult; AFromFilter: Boolean);
const
  cTitles: array[TAtlasDataFlowDirection] of TAtlasResultsTextId = (TAtlasResultsTextId.ResultsDataFlowSources,
    TAtlasResultsTextId.ResultsDataFlowTargets);
var
  mFound: TAtlasDataFlowResult;
begin
  mFound := AFound;
  // Nach einem Filterwechsel bleibt der Baum stehen, auch wenn er leer wird: Die Filter lassen sich zurücknehmen.
  if (not mFound.Found) and (not AFromFilter) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  if not mFound.Found then
  begin
    mFound.Symbol.Name := FFlowName;
  end;
  TAtlasIdeResultsWindow.ShowDataFlow(TAtlasResultsStrings.Fmt(cTitles[FFlowRequest.Direction],
    [mFound.Symbol.Name, Length(mFound.Nodes)]), FFlowRequest.Direction, mFound,
    TAtlasIdeSettings.Current.DataFlowMaxDepth, FFlowRequest.OnlyProject, FFlowRequest.ExcludeTests);
end;

/// <summary>Abschluss einer Ebene: ADone mit dem Ergebnis, bei Fehler leer und eine Zeile.</summary>
function FlowLevelDone(const AFound: TFunc<TAtlasDataFlowResult>; const ADone: TAtlasDataFlowLoaded):
  TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      try
        if AOk then
        begin
          ADone(AFound());
        end
        else
        begin
          TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [AError]));
          ADone(Default(TAtlasDataFlowResult));
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Results, E);
      end;
    end;
end;

class procedure TAtlasIdeResults.ExpandDataFlow(ADirection: TAtlasDataFlowDirection;
  const ASource: TAtlasDataFlowSymbol; const APath: TArray<string>; const ADone: TAtlasDataFlowLoaded);
var
  mCurrent: TLspSession;
  mRequest: TAtlasDataFlowRequest;
  mFound: TAtlasDataFlowResult;
begin
  mCurrent := Session;
  if mCurrent = nil then
  begin
    ADone(Default(TAtlasDataFlowResult));
    Exit;
  end;
  // Gefragt wird an der Deklaration der Quelle; der Pfad lässt den Server Zyklen erkennen.
  mRequest := TAtlasDataFlowRequest.Create(ADirection, ASource.FileName, ASource.Line, ASource.Character);
  mRequest.Path := Copy(APath);
  mRequest.OnlyProject := FFlowRequest.OnlyProject;
  mRequest.ExcludeTests := FFlowRequest.ExcludeTests;
  mFound := Default(TAtlasDataFlowResult);
  Queue.Add(
    procedure
    begin
      mFound := mCurrent.DataFlow(mRequest);
    end,
    FlowLevelDone(
      function: TAtlasDataFlowResult
      begin
        Result := mFound;
      end,
      ADone));
end;

/// <summary>Abschluss einer Ebene der Hierarchie: ADone mit den Kindern, bei Fehler leer und eine Zeile.</summary>
function HierarchyLevelDone(const AChildren: TFunc<TArray<TAtlasHierarchyItem>>; const ADone: TAtlasCallLoaded):
  TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      try
        if AOk then
        begin
          ADone(AChildren());
        end
        else
        begin
          TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [AError]));
          ADone(nil);
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Results, E);
      end;
    end;
end;

class procedure TAtlasIdeResults.ExpandHierarchy(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem; const ADone: TAtlasCallLoaded);
var
  mCurrent: TLspSession;
  mItem: TAtlasHierarchyItem;
  mChildren: TArray<TAtlasHierarchyItem>;
begin
  mCurrent := Session;
  if mCurrent = nil then
  begin
    ADone(nil);
    Exit;
  end;
  mItem := AItem;
  mChildren := nil;
  Queue.Add(
    procedure
    begin
      mChildren := mCurrent.HierarchyChildren(ADirection, mItem);
    end,
    HierarchyLevelDone(
      function: TArray<TAtlasHierarchyItem>
      begin
        Result := mChildren;
      end,
      ADone));
end;

class procedure TAtlasIdeResults.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  TAtlasIdeResultsWindow.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        begin
          Open(AFileName, ALine, ACharacter);
        end);
    end;
  TAtlasIdeResultsWindow.OnExpand :=
    procedure(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem; const ADone: TAtlasCallLoaded)
    begin
      ExpandHierarchy(ADirection, AItem, ADone);
    end;
  // Aufrufdiagramm (#1122): nach callHierarchy.diagram; „Nur Projekt-Units“ über die Projektgruppe.
  TAtlasIdeResultsWindow.DiagramAllowed :=
    function: Boolean
    begin
      Result := CallDiagramAllowed;
    end;
  TAtlasIdeResultsWindow.IsProjectFile :=
    function(AFileName: string): Boolean
    begin
      Result := TAtlasIdeFiles.ProjectOfFile(AFileName) <> '';
    end;
  TAtlasIdeResultsWindow.OnFlowExpand :=
    procedure(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol; const APath: TArray<string>;
      const ADone: TAtlasDataFlowLoaded)
    begin
      ExpandDataFlow(ADirection, ASource, APath, ADone);
    end;
  TAtlasIdeResultsWindow.OnFlowFilter :=
    procedure(AOnlyProject, AExcludeTests: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        begin
          FFlowRequest.OnlyProject := AOnlyProject;
          FFlowRequest.ExcludeTests := AExcludeTests;
          RunDataFlow(True);
        end);
    end;
  // Früh anmelden: Die IDE speichert das Fenster im Desktop und legt es beim Laden selbst an (#879).
  TAtlasIdeResultsWindow.Prepare;
end;

class procedure TAtlasIdeResults.Uninstall;
begin
  FSessionOf := nil;
  FMessage := nil;
  TAtlasIdeResultsWindow.DiagramAllowed := nil;
  TAtlasIdeResultsWindow.IsProjectFile := nil;
  FFlowRequest := Default(TAtlasDataFlowRequest);
  FFlowName := '';
  // Wartet eine laufende Anfrage ab (Zeitlimit oder Abbruchsignal des Entladens) und verwirft ihr Ergebnis und die
  // wartenden, bevor das Fenster geht.
  FreeAndNil(FQueue);
  TAtlasIdeResultsWindow.Release;
end;

class function TAtlasIdeResults.Session: TLspSession;
begin
  Result := TLspSession.From(FSessionOf);
end;

class procedure TAtlasIdeResults.Say(const AText: string);
begin
  TAtlasMessageSink.Create(FMessage).Say(AText);
end;

class function TAtlasIdeResults.AtCursor(out AFileName: string; out ALine, ACharacter: Integer;
  out AName: string): Boolean;
var
  mCurrent: TLspSession;
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mText: string;
  mSpot: TAtlasResultsSpot;
begin
  Result := False;
  AFileName := '';
  ALine := 0;
  ACharacter := 0;
  AName := '';
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  AFileName := mView.Buffer.FileName;
  // Projektweite Anfragen: Der Server soll den Stand aller offenen Puffer kennen.
  TAtlasIdeRename.SyncOpenBuffers(mCurrent);
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mCurrent.Sync(AFileName, mText);
  if not TAtlasResultsPlan.Spot(mText, mView.CursorPos.Line, mView.CursorPos.Col,
    TAtlasEditorBuffer.TabWidth(mView.Buffer), mSpot) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  ALine := mSpot.Line;
  ACharacter := mSpot.Character;
  AName := mSpot.Name;
  Result := True;
end;

class procedure TAtlasIdeResults.FindReferences;
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
begin
  if AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    ShowReferences(mFileName, mLine, mCharacter, mName, nil);
  end;
end;

class procedure TAtlasIdeResults.FindImplementations;
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
  mCurrent: TLspSession;
  mFound: TArray<TLspLocation>;
begin
  if not AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    Exit;
  end;
  mCurrent := Session;
  mFound := nil;
  RunCommand(
    procedure
    begin
      mFound := mCurrent.Implementations(mFileName, mLine, mCharacter);
    end,
    procedure
    begin
      ShowImplementationList(mName, mFound);
    end,
    nil);
end;

class procedure TAtlasIdeResults.ShowImplementationList(const AName: string; const ALocations: TArray<TLspLocation>);
var
  mFound: TArray<TAtlasResultEntry>;
begin
  // Im Hauptthread: Die Einträge lesen den Text offener Editoren.
  mFound := Entries(ALocations);
  // Genau eine Implementierung: gleich hinspringen wie „Gehe zu“.
  case TAtlasResultsPlan.Found(Length(mFound)) of
    TAtlasResultsFound.Jump:
      Open(mFound[0].FileName, mFound[0].Line, mFound[0].Character);
    TAtlasResultsFound.Nothing:
      Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
  else
    TAtlasIdeResultsWindow.ShowEntries(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsImplementations,
      [AName, Length(mFound), Length(TAtlasResults.Group(mFound))]), mFound);
  end;
end;

class procedure TAtlasIdeResults.ShowHierarchy(ADirection: TAtlasHierarchyDirection);
begin
  ShowHierarchy(ADirection, False);
end;

class procedure TAtlasIdeResults.ShowHierarchy(ADirection: TAtlasHierarchyDirection; AAsDiagram: Boolean);
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
  mCurrent: TLspSession;
  mRoots: TArray<TAtlasHierarchyItem>;
begin
  if not AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    Exit;
  end;
  mCurrent := Session;
  mRoots := nil;
  RunCommand(
    procedure
    begin
      mRoots := mCurrent.PrepareHierarchy(ADirection, mFileName, mLine, mCharacter);
    end,
    procedure
    begin
      ShowHierarchyRoots(ADirection, mRoots, AAsDiagram);
    end,
    nil);
end;

class procedure TAtlasIdeResults.ShowHierarchyRoots(ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>; AAsDiagram: Boolean);
const
  cTitles: array[TAtlasHierarchyDirection] of TAtlasResultsTextId = (TAtlasResultsTextId.ResultsIncoming,
    TAtlasResultsTextId.ResultsOutgoing, TAtlasResultsTextId.ResultsSupertypes, TAtlasResultsTextId.ResultsSubtypes);
begin
  if Length(ARoots) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowHierarchy(TAtlasResultsStrings.Fmt(cTitles[ADirection], [ARoots[0].Name]), ADirection,
    ARoots, AAsDiagram);
end;

class procedure TAtlasIdeResults.ShowCallDiagram;
begin
  if CallDiagramAllowed then
  begin
    ShowHierarchy(TAtlasHierarchyDirection.Outgoing, True);
  end;
end;

class function TAtlasIdeResults.CallDiagramAllowed: Boolean;
begin
  Result := TAtlasIdeSettings.Current.CallHierarchyDiagram;
end;

class procedure TAtlasIdeResults.ShowDataFlow(ADirection: TAtlasDataFlowDirection);
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
begin
  // Abgeschaltet: Befehl und Menüeintrag sind verborgen; über die Palette nur eine Zeile.
  if not TAtlasIdeSettings.Current.DataFlow then
  begin
    Say(TAtlasResultsStrings.Text(TAtlasResultsTextId.ResultsDataFlowOff));
    Exit;
  end;
  if not AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    Exit;
  end;
  FFlowRequest := TAtlasDataFlowRequest.Create(ADirection, mFileName, mLine, mCharacter);
  FFlowRequest.ExcludeTests := TAtlasIdeSettings.Current.DataFlowExcludeTests;
  FFlowName := mName;
  RunDataFlow(False);
end;

class procedure TAtlasIdeResults.ShowDataFlow(ADirection: TAtlasDataFlowDirection; const AFileName: string; ALine,
  ACharacter: Integer; const AName: string);
var
  mCurrent: TLspSession;
begin
  if not TAtlasIdeSettings.Current.DataFlow then
  begin
    Say(TAtlasResultsStrings.Text(TAtlasResultsTextId.ResultsDataFlowOff));
    Exit;
  end;
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  // Projektweite Anfrage: wie am Cursor alle offenen Puffer abgleichen.
  TAtlasIdeRename.SyncOpenBuffers(mCurrent);
  FFlowRequest := TAtlasDataFlowRequest.Create(ADirection, AFileName, ALine, ACharacter);
  FFlowRequest.ExcludeTests := TAtlasIdeSettings.Current.DataFlowExcludeTests;
  FFlowName := AName;
  RunDataFlow(False);
end;

class procedure TAtlasIdeResults.SearchSymbol;
var
  mWindow: TAtlasPaletteWindow;
  mSymbols: TArray<TAtlasSymbol>;
begin
  if Session = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mSymbols := nil;
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, nil, nil, TAtlasIdeStyle.Colors);
  mWindow.Prompt := '#';
  mWindow.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    begin
      mSymbols := QuerySymbols(APattern);
      Result := TAtlasResultsPlan.SymbolCommands(mSymbols);
    end;
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Index: Integer;
    begin
      Index := StrToIntDef(ACommand.Id, -1);
      if (Index >= 0) and (Index <= High(mSymbols)) then
      begin
        Open(mSymbols[Index].FileName, mSymbols[Index].Line, mSymbols[Index].Character);
      end;
    end;
  mWindow.ShowOver(TAtlasIdeHost.PopupArea);
end;

class procedure TAtlasIdeResults.ShowReferences(const AFileName: string; ALine, ACharacter: Integer;
  const AName: string; const ADone: TAtlasReferencesDone);
var
  mCurrent: TLspSession;
  mLocations: TArray<TLspLocation>;
begin
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  mLocations := nil;
  RunCommand(
    procedure
    begin
      mLocations := mCurrent.References(AFileName, ALine, ACharacter);
    end,
    procedure
    begin
      ShowReferenceList(AName, mLocations, ADone);
    end,
    procedure
    begin
      if Assigned(ADone) then
      begin
        ADone(-1);
      end;
    end);
end;

class procedure TAtlasIdeResults.ShowReferenceList(const AName: string; const ALocations: TArray<TLspLocation>;
  const ADone: TAtlasReferencesDone);
var
  mFound: TArray<TAtlasResultEntry>;
begin
  // Im Hauptthread: Die Einträge lesen den Text offener Editoren.
  mFound := Entries(ALocations);
  TAtlasIdeResultsWindow.ShowReferences(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsReferences,
    [AName, Length(mFound), Length(TAtlasResults.Group(mFound))]), mFound);
  if Assigned(ADone) then
  begin
    ADone(Length(mFound));
  end;
end;

class procedure TAtlasIdeResults.ShowWindow;
begin
  TAtlasIdeResultsWindow.Frame;
end;

class procedure TAtlasIdeResults.Open(const AFileName: string; ALine, ACharacter: Integer);
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
end;

end.
