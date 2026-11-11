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
// Datenfluss (#690): „Woher kommt der Wert?“ und „Wohin geht der Wert?“ als Baum; jede aufgeklappte Quelle
// fragt mit dem Pfad ihrer Vorfahren und den Filtern der ersten Anfrage nach (navigation.dataFlow).

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Results.Model;

type
  TAtlasIdeResults = class
  private
    class var FSessionOf: TFunc<TLspSession>;
    class var FMessage: TProc<string>;
    /// <summary>Erste Anfrage des zuletzt gezeigten Datenflusses; Filter und Folgeanfragen bauen darauf.</summary>
    class var FFlowRequest: TAtlasDataFlowRequest;
    /// <summary>Wort am Cursor zur ersten Anfrage, für den Titel eines leeren Baums.</summary>
    class var FFlowName: string;
    class function Entries(const ALocations: TArray<TLspLocation>): TArray<TAtlasResultEntry>; static;
    /// <summary>Erste Ebene holen und zeigen; AFromFilter: kein „nichts gefunden“, der Baum leert sich nur.</summary>
    class procedure RunDataFlow(AFromFilter: Boolean); static;
    class function ExpandDataFlow(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
      const APath: TArray<string>): TAtlasDataFlowResult; static;
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
    /// <summary>Referenzen auf ein Symbol an einem Fundort (z. B. aus dem Tooltip); Anzahl der Fundstellen.</summary>
    class function ShowReferences(const AFileName: string; ALine, ACharacter: Integer; const AName: string): Integer;
      static;
    /// <summary>Ergebnisfenster zeigen.</summary>
    class procedure ShowWindow; static;
    class procedure Open(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Completion.Word,
  Atlas.Core.Commands.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Results.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Files;

const
  // Beim Tippen: lieber leer als die IDE aufhalten.
  cSymbolTimeoutMs = 1500;

function ReadText(const AFileName: string): string;
begin
  Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
end;

/// <summary>Kinder einer Hierarchie-Ebene unter dem Wächter; leer ohne Server oder bei Fehler (mit Meldung).</summary>
function GuardedChildren(ADirection: TAtlasHierarchyDirection;
  const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
var
  mChildren: TArray<TAtlasHierarchyItem>;
begin
  mChildren := nil;
  TAtlasGuard.Run(TAtlasFeature.Results,
    procedure
    var
      mCurrent: TLspSession;
    begin
      mCurrent := TAtlasIdeResults.Session;
      if mCurrent = nil then
      begin
        Exit;
      end;
      try
        mChildren := mCurrent.HierarchyChildren(ADirection, AItem);
      except
        on E: ELspClientError do
          TAtlasIdeResults.Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
      end;
    end);
  Result := mChildren;
end;

/// <summary>Nächste Ebene des Datenflusses unter dem Wächter.</summary>
function GuardedFlow(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
  const APath: TArray<string>): TAtlasDataFlowResult;
var
  mFound: TAtlasDataFlowResult;
begin
  mFound := Default(TAtlasDataFlowResult);
  TAtlasGuard.Run(TAtlasFeature.Results,
    procedure
    begin
      mFound := TAtlasIdeResults.ExpandDataFlow(ADirection, ASource, APath);
    end);
  Result := mFound;
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

/// <summary>Zeilen der Symbolsuche; die Kennung ist der Index in ASymbols.</summary>
function SymbolCommands(const ASymbols: TArray<TAtlasSymbol>): TArray<TAtlasCommand>;
var
  mIndex: Integer;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mIndex := 0 to High(ASymbols) do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := IntToStr(mIndex);
    mCommand.Caption := ASymbols[mIndex].Name;
    mCommand.Path := ExtractFileName(ASymbols[mIndex].FileName);
    if ASymbols[mIndex].Container <> '' then
    begin
      mCommand.Path := ASymbols[mIndex].Container + ' · ' + mCommand.Path;
    end;
    mCommand.ShortCut := TAtlasResults.SymbolBadge(ASymbols[mIndex].Kind);
    Result := Result + [mCommand];
  end;
end;

/// <summary>Fläche, über der die Symbolsuche erscheint: aktives Formular, Hauptfenster oder Arbeitsfläche.</summary>
function PaletteArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

{ TAtlasIdeResults }

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
    function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
    begin
      Result := GuardedChildren(ADirection, AItem);
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
    function(ADirection: TAtlasDataFlowDirection; const ASource: TAtlasDataFlowSymbol;
      const APath: TArray<string>): TAtlasDataFlowResult
    begin
      Result := GuardedFlow(ADirection, ASource, APath);
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
  TAtlasIdeResultsWindow.Release;
end;

class function TAtlasIdeResults.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class procedure TAtlasIdeResults.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class procedure TAtlasIdeResults.Open(const AFileName: string; ALine, ACharacter: Integer);
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
end;

class function TAtlasIdeResults.AtCursor(out AFileName: string; out ALine, ACharacter: Integer;
  out AName: string): Boolean;
var
  mCurrent: TLspSession;
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mCursor: TOTAEditPos;
  mFirst, mLast: Integer;
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
  mLines := mText.Split([#13#10, #10]);
  mCursor := mView.CursorPos;
  if (mCursor.Line < 1) or (mCursor.Line > Length(mLines)) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  ALine := mCursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(mLines[ALine], mCursor.Col, TAtlasEditorBuffer.TabWidth(mView.Buffer));
  mFirst := TAtlasWord.StartBefore(mLines[ALine], ACharacter);
  mLast := TAtlasWord.EndAfter(mLines[ALine], ACharacter);
  AName := Copy(mLines[ALine], mFirst + 1, mLast - mFirst);
  Result := True;
end;

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

class function TAtlasIdeResults.ShowReferences(const AFileName: string; ALine, ACharacter: Integer;
  const AName: string): Integer;
var
  mCurrent: TLspSession;
  mFound: TArray<TAtlasResultEntry>;
begin
  Result := 0;
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      mFound := Entries(mCurrent.References(AFileName, ALine, ACharacter));
    except
      on E: ELspClientError do
      begin
        Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  Result := Length(mFound);
  TAtlasIdeResultsWindow.ShowReferences(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsReferences,
    [AName, Length(mFound), Length(TAtlasResults.Group(mFound))]), mFound);
end;

class procedure TAtlasIdeResults.FindReferences;
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
begin
  if AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    ShowReferences(mFileName, mLine, mCharacter, mName);
  end;
end;

class procedure TAtlasIdeResults.FindImplementations;
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
  mFound: TArray<TAtlasResultEntry>;
begin
  if not AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      mFound := Entries(Session.Implementations(mFileName, mLine, mCharacter));
    except
      on E: ELspClientError do
      begin
        Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  // Genau eine Implementierung: gleich hinspringen wie „Gehe zu“.
  if Length(mFound) = 1 then
  begin
    Open(mFound[0].FileName, mFound[0].Line, mFound[0].Character);
    Exit;
  end;
  if Length(mFound) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowEntries(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsImplementations,
    [mName, Length(mFound), Length(TAtlasResults.Group(mFound))]), mFound);
end;

class procedure TAtlasIdeResults.ShowHierarchy(ADirection: TAtlasHierarchyDirection);
begin
  ShowHierarchy(ADirection, False);
end;

class function TAtlasIdeResults.CallDiagramAllowed: Boolean;
begin
  Result := TAtlasIdeSettings.Current.CallHierarchyDiagram;
end;

class procedure TAtlasIdeResults.ShowCallDiagram;
begin
  if CallDiagramAllowed then
  begin
    ShowHierarchy(TAtlasHierarchyDirection.Outgoing, True);
  end;
end;

class procedure TAtlasIdeResults.ShowHierarchy(ADirection: TAtlasHierarchyDirection; AAsDiagram: Boolean);
const
  cTitles: array[TAtlasHierarchyDirection] of TAtlasTextId = (TAtlasTextId.ResultsIncoming,
    TAtlasTextId.ResultsOutgoing, TAtlasTextId.ResultsSupertypes, TAtlasTextId.ResultsSubtypes);
var
  mFileName, mName: string;
  mLine, mCharacter: Integer;
  mRoots: TArray<TAtlasHierarchyItem>;
begin
  if not AtCursor(mFileName, mLine, mCharacter, mName) then
  begin
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      mRoots := Session.PrepareHierarchy(ADirection, mFileName, mLine, mCharacter);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if Length(mRoots) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowHierarchy(TAtlasStrings.Fmt(cTitles[ADirection], [mRoots[0].Name]), ADirection, mRoots,
    AAsDiagram);
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

class procedure TAtlasIdeResults.RunDataFlow(AFromFilter: Boolean);
const
  cTitles: array[TAtlasDataFlowDirection] of TAtlasTextId = (TAtlasTextId.ResultsDataFlowSources,
    TAtlasTextId.ResultsDataFlowTargets);
var
  mCurrent: TLspSession;
  mFound: TAtlasDataFlowResult;
begin
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      mFound := mCurrent.DataFlow(FFlowRequest);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
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
  TAtlasIdeResultsWindow.ShowDataFlow(TAtlasStrings.Fmt(cTitles[FFlowRequest.Direction],
    [mFound.Symbol.Name, Length(mFound.Nodes)]), FFlowRequest.Direction, mFound,
    TAtlasIdeSettings.Current.DataFlowMaxDepth, FFlowRequest.OnlyProject, FFlowRequest.ExcludeTests);
end;

class function TAtlasIdeResults.ExpandDataFlow(ADirection: TAtlasDataFlowDirection;
  const ASource: TAtlasDataFlowSymbol; const APath: TArray<string>): TAtlasDataFlowResult;
var
  mCurrent: TLspSession;
  mRequest: TAtlasDataFlowRequest;
begin
  Result := Default(TAtlasDataFlowResult);
  mCurrent := Session;
  if mCurrent = nil then
  begin
    Exit;
  end;
  // Gefragt wird an der Deklaration der Quelle; der Pfad lässt den Server Zyklen erkennen.
  mRequest := TAtlasDataFlowRequest.Create(ADirection, ASource.FileName, ASource.Line, ASource.Character);
  mRequest.Path := APath;
  mRequest.OnlyProject := FFlowRequest.OnlyProject;
  mRequest.ExcludeTests := FFlowRequest.ExcludeTests;
  Screen.Cursor := crHourGlass;
  try
    try
      Result := mCurrent.DataFlow(mRequest);
    except
      on E: ELspClientError do
        Say(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.ResultsFailed, [E.Message]));
    end;
  finally
    Screen.Cursor := crDefault;
  end;
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
      Result := SymbolCommands(mSymbols);
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
  mWindow.ShowOver(PaletteArea);
end;

class procedure TAtlasIdeResults.ShowWindow;
begin
  TAtlasIdeResultsWindow.Frame;
end;

end.
