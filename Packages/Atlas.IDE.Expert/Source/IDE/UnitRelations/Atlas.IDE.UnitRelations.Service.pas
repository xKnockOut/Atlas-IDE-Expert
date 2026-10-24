unit Atlas.IDE.UnitRelations.Service;

// Fenster „Unit-Beziehungen“ (#593) in der IDE:
// - ShowWindow zeigt das Fenster (Ansicht › Atlas › Unit-Beziehungen,
//   Befehlspalette Atlas.UnitRelations). Solange es sichtbar ist, folgt ein
//   Zeitgeber der aktiven Quelltextdatei wie die Gliederung (#537).
// - Beim Dateiwechsel zeigt das Fenster sofort den gemerkten Stand
//   (TAtlasUnitRelationsCache, je Datei und Tiefe) und fragt den Server im
//   Hintergrund mit atlas.unitRelations; danach fragt es alle RefreshMs nach
//   (Index und Text ändern sich beim Tippen) und baut den Baum nur neu, wenn
//   sich die Antwort geändert hat. Ältere Antworten fallen weg.
// - ShowFor (Strg+Doppelklick in der Architekturkarte, #1118) zeigt eine
//   bestimmte Unit, bis der Editor eine andere Datei zeigt.
// - „In implementation/interface verschieben“ und „Eintrag entfernen“ gehen
//   an atlas.server.moveUses bzw. atlas.server.removeUses; das WorkspaceEdit
//   des Servers übernimmt TAtlasIdeWorkspaceEdit (ein Rückgängig-Schritt).
// - Doppelklick öffnet die Unit, Strg+Doppelklick springt zum uses-Eintrag.
// - Abschaltbar mit architecture.enabled (derselbe Uses-Graph); aus schließt
//   das Fenster.
// Den Server erreicht der Dienst über ARun (Install). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Befehl des Servers im Hintergrund (wie TAtlasCodeInsightManager.RunServerCommandAsync); ADone im
  /// Hauptthread mit der Antwort oder nil (Fehler, Zeitlimit), den Wert gibt der Aufrufer danach frei. False =
  /// nicht gestartet (kein Server).</summary>
  TAtlasUnitRelationsRun = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<TJSONValue>): Boolean;

  TAtlasIdeUnitRelations = class
  private class var
    FState: TObject;
  public
    class procedure Install(const ARun: TAtlasUnitRelationsRun); static;
    class procedure Uninstall; static;
    /// <summary>Fenster zeigen; nichts, solange architecture.enabled aus ist.</summary>
    class procedure ShowWindow; static;
    /// <summary>Fenster für AFileName zeigen, bis der Editor eine andere Datei zeigt (#1118, Strg+Doppelklick).
    /// </summary>
    class procedure ShowFor(const AFileName: string); static;
    class procedure ApplySettings; static;
    class procedure ThemeChanged; static;
    class function Enabled: Boolean; static;
  end;

implementation

uses
  System.Classes,
  Winapi.Windows,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.UnitRelations.Model,
  Atlas.UI.Strings,
  Atlas.UI.UnitRelations.Frame,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.UnitRelations.Window;

const
  TickMs = 250;
  /// <summary>Nachfragen, solange das Fenster offen ist; die Anfrage dauert auf dem Server Millisekunden.</summary>
  RefreshMs = 2000;
  TimeoutMs = 15000;

type
  TUnitRelationsState = class
  private
    FRun: TAtlasUnitRelationsRun;
    FTimer: TTimer;
    FCache: TAtlasUnitRelationsCache;
    /// <summary>Gezeigte Datei; '' = Meldung.</summary>
    FFileName: string;
    /// <summary>Von ShowFor gewählt, gilt solange der Editor FPinnedEditor zeigt.</summary>
    FPinned: string;
    FPinnedEditor: string;
    FAllLevels: Boolean;
    FRequest: Integer;
    FPending: Boolean;
    FAsked: Cardinal;
    FLastJson: string;
    FShownMessage: Boolean;
    procedure Tick(Sender: TObject);
    procedure Wire(AFrame: TAtlasUnitRelationsFrame);
    function EditorFile: string;
    function Target: string;
    procedure ShowJson(AFrame: TAtlasUnitRelationsFrame; const AJson: string);
    procedure ShowInfo(AFrame: TAtlasUnitRelationsFrame; AId: TAtlasTextId);
    procedure Request;
    procedure ChangeDepth(AAllLevels: Boolean);
    procedure Change(const ACommand, AArgumentsJson: string);
    procedure Open(const AFileName: string; ALine, ACharacter: Integer);
  public
    constructor Create(const ARun: TAtlasUnitRelationsRun);
    destructor Destroy; override;
    procedure Reset;
    procedure Update;
    procedure Pin(const AFileName: string);
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ArchitectureEnabled and not TAtlasGuard.Disabled(TAtlasFeature.UnitRelations);
end;

function IsPascalFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk');
end;

{ TUnitRelationsState }

constructor TUnitRelationsState.Create(const ARun: TAtlasUnitRelationsRun);
begin
  inherited Create;
  FRun := ARun;
  FCache := TAtlasUnitRelationsCache.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  TAtlasIdeUnitRelationsWindow.OnFrame :=
    procedure(AFrame: TAtlasUnitRelationsFrame)
    begin
      Wire(AFrame);
    end;
  // Früh anmelden, damit die IDE das Fenster im Desktop speichert und wiederherstellt (#879).
  TAtlasIdeUnitRelationsWindow.Prepare;
  // Das Fenster gab es schon (Paket neu geladen): neu verdrahten.
  if TAtlasIdeUnitRelationsWindow.ExistingFrame <> nil then
    Wire(TAtlasIdeUnitRelationsWindow.ExistingFrame);
end;

destructor TUnitRelationsState.Destroy;
var
  Frame: TAtlasUnitRelationsFrame;
begin
  // Antworten, die noch unterwegs sind, finden FState nicht mehr und fallen weg.
  Inc(FRequest);
  FTimer.Free;
  TAtlasIdeUnitRelationsWindow.OnFrame := nil;
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if Frame <> nil then
  begin
    Frame.OnOpen := nil;
    Frame.OnMove := nil;
    Frame.OnRemove := nil;
    Frame.OnDepthChanged := nil;
  end;
  FCache.Free;
  inherited Destroy;
end;

procedure TUnitRelationsState.Reset;
begin
  FFileName := '';
  FLastJson := '';
  FShownMessage := False;
end;

procedure TUnitRelationsState.Wire(AFrame: TAtlasUnitRelationsFrame);
begin
  AFrame.AllLevels := FAllLevels;
  AFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations,
        procedure
        begin
          Open(AFileName, ALine, ACharacter);
        end);
    end;
  AFrame.OnMove :=
    procedure(const AUnit: string; AToInterface: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations,
        procedure
        begin
          Change(TAtlasUnitRelationsCommands.MoveCommand, TAtlasUnitRelationsCommands.MoveArguments(
            TLspSession.PathToUri(FFileName), AUnit, AToInterface));
        end);
    end;
  AFrame.OnRemove :=
    procedure(const AUnit: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations,
        procedure
        begin
          Change(TAtlasUnitRelationsCommands.RemoveCommand, TAtlasUnitRelationsCommands.RemoveArguments(
            TLspSession.PathToUri(FFileName), AUnit));
        end);
    end;
  AFrame.OnDepthChanged :=
    procedure(AAllLevels: Boolean)
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations,
        procedure
        begin
          ChangeDepth(AAllLevels);
        end);
    end;
  Reset;
end;

function TUnitRelationsState.EditorFile: string;
var
  View: IOTAEditView;
begin
  Result := '';
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) and IsPascalFile(View.Buffer.FileName) then
    Result := View.Buffer.FileName;
end;

function TUnitRelationsState.Target: string;
var
  Editor: string;
begin
  Editor := EditorFile;
  if (FPinned <> '') and SameText(Editor, FPinnedEditor) then
    Exit(FPinned);
  FPinned := '';
  Result := Editor;
end;

procedure TUnitRelationsState.Pin(const AFileName: string);
begin
  FPinned := AFileName;
  FPinnedEditor := EditorFile;
end;

procedure TUnitRelationsState.ShowJson(AFrame: TAtlasUnitRelationsFrame; const AJson: string);
var
  Relations: TAtlasUnitRelations;
begin
  if AJson = FLastJson then
    Exit;
  if not TAtlasUnitRelationsModel.Parse(AJson, Relations) then
  begin
    if not AFrame.HasRelations then
      ShowInfo(AFrame, TAtlasTextId.UnitRelationsFailed);
    Exit;
  end;
  FLastJson := AJson;
  FShownMessage := False;
  // Der Server liest die Datei so, wie der Editor sie meldet; der Name im Fenster bleibt der des Editors.
  if Relations.FileName = '' then
    Relations.FileName := FFileName;
  AFrame.SetRelations(Relations);
end;

procedure TUnitRelationsState.ShowInfo(AFrame: TAtlasUnitRelationsFrame; AId: TAtlasTextId);
begin
  FLastJson := '';
  FShownMessage := True;
  AFrame.SetMessage(TAtlasStrings.Text(AId));
end;

procedure TUnitRelationsState.Request;
var
  Frame: TAtlasUnitRelationsFrame;
  Number: Integer;
  FileName: string;
  AllLevels: Boolean;
begin
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (Frame = nil) or (FFileName = '') then
    Exit;
  Inc(FRequest);
  Number := FRequest;
  FileName := FFileName;
  AllLevels := FAllLevels;
  FPending := True;
  FAsked := GetTickCount;
  if not FRun(TAtlasUnitRelationsCommands.Command,
    TAtlasUnitRelationsCommands.Arguments(TLspSession.PathToUri(FileName), AllLevels), TimeoutMs,
    procedure(AAnswer: TJSONValue)
    var
      Current: TAtlasUnitRelationsFrame;
      Json: string;
    begin
      if (TAtlasIdeUnitRelations.FState <> Self) or (Number <> FRequest) then
        Exit;
      FPending := False;
      // Gezählt wird ab der Antwort: Ein langsamer Server bekommt nicht gleich die nächste Anfrage.
      FAsked := GetTickCount;
      Current := TAtlasIdeUnitRelationsWindow.ExistingFrame;
      if Current = nil then
        Exit;
      Json := '';
      if AAnswer <> nil then
        Json := AAnswer.ToJSON;
      if Json = '' then
      begin
        if not Current.HasRelations then
          ShowInfo(Current, TAtlasTextId.UnitRelationsFailed);
        Exit;
      end;
      FCache.Put(FileName, AllLevels, Json);
      ShowJson(Current, Json);
    end) then
  begin
    FPending := False;
    if not Frame.HasRelations then
      ShowInfo(Frame, TAtlasTextId.UnitRelationsNoServer);
  end;
end;

procedure TUnitRelationsState.Update;
var
  Frame: TAtlasUnitRelationsFrame;
  FileName, Json: string;
begin
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if Frame = nil then
    Exit;
  FileName := Target;
  if FileName = '' then
  begin
    if (FFileName <> '') or not FShownMessage then
    begin
      FFileName := '';
      ShowInfo(Frame, TAtlasTextId.UnitRelationsNoFile);
    end;
    Exit;
  end;
  if not SameText(FileName, FFileName) then
  begin
    // Dateiwechsel: gemerkter Stand sofort, die Antwort des Servers folgt.
    FFileName := FileName;
    FLastJson := '';
    if FCache.TryGet(FileName, FAllLevels, Json) then
      ShowJson(Frame, Json)
    else
      ShowInfo(Frame, TAtlasTextId.UnitRelationsLoading);
    Request;
    Exit;
  end;
  if not FPending and (GetTickCount - FAsked >= RefreshMs) then
    Request;
end;

procedure TUnitRelationsState.ChangeDepth(AAllLevels: Boolean);
var
  Frame: TAtlasUnitRelationsFrame;
  Json: string;
begin
  if AAllLevels = FAllLevels then
    Exit;
  FAllLevels := AAllLevels;
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (Frame = nil) or (FFileName = '') then
    Exit;
  FLastJson := '';
  if FCache.TryGet(FFileName, FAllLevels, Json) then
    ShowJson(Frame, Json);
  Request;
end;

procedure TUnitRelationsState.Change(const ACommand, AArgumentsJson: string);
var
  Frame: TAtlasUnitRelationsFrame;
begin
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (Frame = nil) or (FFileName = '') then
    Exit;
  if not FRun(ACommand, AArgumentsJson, TimeoutMs,
    procedure(AAnswer: TJSONValue)
    var
      Edit: TLspWorkspaceEdit;
      Outcome: TAtlasWorkspaceEditResult;
      Current: TAtlasUnitRelationsFrame;
    begin
      if TAtlasIdeUnitRelations.FState <> Self then
        Exit;
      Current := TAtlasIdeUnitRelationsWindow.ExistingFrame;
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if AAnswer is TJSONObject then
        Edit := TLspWorkspaceEdit.FromJson(TJSONObject(AAnswer).GetValue('edit'));
      if Edit.IsEmpty then
      begin
        if Current <> nil then
          Current.Info.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsEditRefused);
        Exit;
      end;
      Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.OpenInEditor,
        TAtlasStrings.Text(TAtlasTextId.UnitRelationsEditAction));
      if (Outcome.Error <> '') and (Current <> nil) then
        Current.Info.Caption := TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsEditFailed, [Outcome.Error]);
      // Bald neu fragen: Der Server sieht den geänderten Text mit dem nächsten Abgleich des Puffers.
      FAsked := GetTickCount - RefreshMs + 500;
    end) then
    Frame.Info.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsNoServer);
end;

procedure TUnitRelationsState.Open(const AFileName: string; ALine, ACharacter: Integer);
var
  Actions: IOTAActionServices;
begin
  if AFileName = '' then
    Exit;
  if ALine >= 0 then
    TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter)
  else if Supports(BorlandIDEServices, IOTAActionServices, Actions) then
    // Nur die Unit: Ist sie schon offen, bleibt der Cursor, wo er war.
    Actions.OpenFile(AFileName);
end;

procedure TUnitRelationsState.Tick(Sender: TObject);
begin
  if not Active or not TAtlasIdeUnitRelationsWindow.Visible then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.UnitRelations,
    procedure
    begin
      Update;
    end);
end;

{ TAtlasIdeUnitRelations }

class procedure TAtlasIdeUnitRelations.Install(const ARun: TAtlasUnitRelationsRun);
begin
  FreeAndNil(FState);
  FState := TUnitRelationsState.Create(ARun);
end;

class procedure TAtlasIdeUnitRelations.Uninstall;
begin
  FreeAndNil(FState);
  TAtlasIdeUnitRelationsWindow.Release;
end;

class function TAtlasIdeUnitRelations.Enabled: Boolean;
begin
  Result := Active;
end;

class procedure TAtlasIdeUnitRelations.ShowWindow;
var
  Frame: TAtlasUnitRelationsFrame;
begin
  if (FState = nil) or not Active then
    Exit;
  Frame := TAtlasIdeUnitRelationsWindow.Show;
  if Frame = nil then
    Exit;
  TUnitRelationsState(FState).Reset;
  TUnitRelationsState(FState).Update;
  if Frame.Filter.CanFocus then
    Frame.Filter.SetFocus;
end;

class procedure TAtlasIdeUnitRelations.ShowFor(const AFileName: string);
begin
  if (FState = nil) or not Active or (AFileName = '') then
    Exit;
  TUnitRelationsState(FState).Pin(AFileName);
  ShowWindow;
end;

class procedure TAtlasIdeUnitRelations.ApplySettings;
begin
  if (FState <> nil) and not Active then
    TAtlasIdeUnitRelationsWindow.Hide;
end;

class procedure TAtlasIdeUnitRelations.ThemeChanged;
var
  Frame: TAtlasUnitRelationsFrame;
begin
  TAtlasIdeUnitRelationsWindow.ApplyTheme;
  Frame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if Frame <> nil then
    Frame.Tree.Invalidate;
end;

end.
