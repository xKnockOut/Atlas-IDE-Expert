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
// - ShowCurrent (Befehl „Abhängigkeiten dieser Unit“, #554, und Klick auf das
//   Feld in der Statusleiste) zeigt die Unit im Editor, auch wenn vorher eine
//   aus der Architekturkarte gewählt war.
// - Kosten einer interface-Änderung (#554, build.showInterfaceCost): Steht
//   die Einfügemarke im interface-Teil einer .pas-Unit, zeigt die
//   Statusleiste über SetCostHandler „interface-Änderung: N Units werden neu
//   kompiliert“, der Hinweis nennt die ersten Units. Der Wert kommt im
//   Hintergrund von atlas.interfaceCost, beim Dateiwechsel sofort und dann
//   alle CostRefreshMs, solange die Marke im interface steht (so folgen
//   geänderte uses); die Abschnitte liest TAtlasSectionScanner aus dem
//   Editortext, nur wenn er sich geändert hat. Im implementation-Teil, bei
//   0 Units und außerhalb von Units kein Feld.
// - Abschaltbar mit architecture.enabled (derselbe Uses-Graph); aus schließt
//   das Fenster und nimmt das Feld weg.
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
  /// <summary>Feld der Statusleiste für die Kosten einer interface-Änderung (#554); AText = '' nimmt es weg.
  /// </summary>
  TAtlasInterfaceCostShow = reference to procedure(const AText, AHint: string);

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
    /// <summary>Fenster für die Unit im Editor zeigen (#554, „Abhängigkeiten dieser Unit“).</summary>
    class procedure ShowCurrent; static;
    /// <summary>Wohin die Kosten einer interface-Änderung gehen (#554); nil = nirgends.</summary>
    class procedure SetCostHandler(const AShow: TAtlasInterfaceCostShow); static;
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
  Atlas.Core.UnitRelations.InterfaceCost,
  Atlas.Core.EditorToolbar.Sections,
  Atlas.UI.Strings,
  Atlas.UI.Analysis.Strings,
  Atlas.UI.UnitRelations.Frame,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.UnitRelations.Window;

const
  cTickMs = 250;
  /// <summary>Nachfragen, solange das Fenster offen ist; die Anfrage dauert auf dem Server Millisekunden.</summary>
  cRefreshMs = 2000;
  cTimeoutMs = 15000;
  /// <summary>Kosten nachfragen, solange die Einfügemarke im interface steht (#554).</summary>
  cCostRefreshMs = 5000;

type
  /// <summary>Kosten einer interface-Änderung (#554) für das Feld der Statusleiste.</summary>
  TInterfaceCostState = class
  private
    FRun: TAtlasUnitRelationsRun;
    /// <summary>Besitzer (TUnitRelationsState); Antworten gelten nur, solange er FState ist.</summary>
    FOwner: TObject;
    FShow: TAtlasInterfaceCostShow;
    FFile: string;
    FCost: TAtlasInterfaceCost;
    FKnown: Boolean;
    FRequest: Integer;
    FPending: Boolean;
    FAsked: Cardinal;
    FInInterface: Boolean;
    FSections: TAtlasUnitSections;
    FSectionsFile: string;
    FSectionsVersion: Cardinal;
    FShownText: string;
    FShownHint: string;
    procedure SetText(const AText, AHint: string);
    procedure Show;
    procedure Request;
    function AnswerHandler(ANumber: Integer): TProc<TJSONValue>;
    /// <summary>Abschnitte und Lage der Einfügemarke in AView lesen; Dateiwechsel setzt den Wert zurück.</summary>
    procedure Locate(const AView: IOTAEditView);
  public
    constructor Create(const ARun: TAtlasUnitRelationsRun; AOwner: TObject);
    /// <summary>Laufende Antworten verwerfen.</summary>
    procedure Cancel;
    procedure SetHandler(const AShow: TAtlasInterfaceCostShow);
    /// <summary>Feld der Statusleiste wegnehmen und neu ermitteln (Einstellungen, Aus).</summary>
    procedure Hide;
    /// <summary>Takt: Einfügemarke prüfen, bei Bedarf nachfragen, Feld zeigen.</summary>
    procedure Update;
  end;

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
    /// <summary>Kosten einer interface-Änderung (#554).</summary>
    FCost: TInterfaceCostState;
    procedure Tick(Sender: TObject);
    procedure Wire(AFrame: TAtlasUnitRelationsFrame);
    function EditorFile: string;
    function Target: string;
    procedure ShowJson(AFrame: TAtlasUnitRelationsFrame; const AJson: string);
    procedure ShowInfo(AFrame: TAtlasUnitRelationsFrame; AId: TAtlasAnalysisTextId);
    procedure Request;
    function AnswerHandler(ANumber: Integer; const AFileName: string; AAllLevels: Boolean): TProc<TJSONValue>;
    procedure TakeAnswer(const AFileName: string; AAllLevels: Boolean; AAnswer: TJSONValue);
    procedure ChangeDepth(AAllLevels: Boolean);
    procedure Change(const ACommand, AArgumentsJson: string);
    procedure Open(const AFileName: string; ALine, ACharacter: Integer);
  public
    constructor Create(const ARun: TAtlasUnitRelationsRun);
    destructor Destroy; override;
    procedure Reset;
    procedure Update;
    procedure Pin(const AFileName: string);
    procedure Unpin;
    procedure SetCostHandler(const AShow: TAtlasInterfaceCostShow);
    /// <summary>Feld der Statusleiste wegnehmen und neu ermitteln (Einstellungen, Aus).</summary>
    procedure HideCost;
  end;

function Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ArchitectureEnabled and not TAtlasGuard.Disabled(TAtlasFeature.UnitRelations);
end;

function IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

{ TInterfaceCostState }

constructor TInterfaceCostState.Create(const ARun: TAtlasUnitRelationsRun; AOwner: TObject);
begin
  inherited Create;
  FRun := ARun;
  FOwner := AOwner;
end;

procedure TInterfaceCostState.Cancel;
begin
  Inc(FRequest);
end;

procedure TInterfaceCostState.SetHandler(const AShow: TAtlasInterfaceCostShow);
begin
  Hide;
  FShow := AShow;
end;

procedure TInterfaceCostState.SetText(const AText, AHint: string);
begin
  // Nur bei Änderungen: Der Zeitgeber fragt viermal je Sekunde.
  if (AText = FShownText) and (AHint = FShownHint) then
  begin
    Exit;
  end;
  FShownText := AText;
  FShownHint := AHint;
  if Assigned(FShow) then
  begin
    FShow(AText, AHint);
  end;
end;

procedure TInterfaceCostState.Hide;
begin
  SetText('', '');
  FFile := '';
  FKnown := False;
  FInInterface := False;
end;

procedure TInterfaceCostState.Show;
var
  mText, mUnits: string;
  mMore: Integer;
begin
  if not TAtlasInterfaceCostModel.Visible(TAtlasIdeSettings.Current.ShowInterfaceCost, FInInterface and FKnown,
    FCost) then
  begin
    SetText('', '');
    Exit;
  end;
  if FCost.RecompileCount = 1 then
  begin
    mText := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.InterfaceCostStatusOne);
  end
  else
  begin
    mText := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.InterfaceCostStatus, [FCost.RecompileCount]);
  end;
  mUnits := TAtlasInterfaceCostModel.UnitList(FCost, mMore);
  if mMore > 0 then
  begin
    mUnits := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.InterfaceCostMore, [mUnits, mMore]);
  end;
  SetText(mText, TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.InterfaceCostHint, [FCost.UnitName, mUnits]));
end;

function TInterfaceCostState.AnswerHandler(ANumber: Integer): TProc<TJSONValue>;
var
  mOwner: TObject;
begin
  // Der Besitzer in einer eigenen Variablen: Nach seinem Abbau gibt es dieses Objekt nicht mehr.
  mOwner := FOwner;
  Result :=
    procedure(AAnswer: TJSONValue)
    var
      mCost: TAtlasInterfaceCost;
    begin
      if (TAtlasIdeUnitRelations.FState <> mOwner) or (ANumber <> FRequest) then
      begin
        Exit;
      end;
      FPending := False;
      FAsked := GetTickCount;
      if (AAnswer <> nil) and TAtlasInterfaceCostModel.Parse(AAnswer.ToJSON, mCost) then
      begin
        FCost := mCost;
        FKnown := True;
      end;
      Show;
    end;
end;

procedure TInterfaceCostState.Request;
begin
  Inc(FRequest);
  FPending := True;
  FAsked := GetTickCount;
  if not FRun(TAtlasInterfaceCostModel.cCommand, TAtlasInterfaceCostModel.Arguments(TLspSession.PathToUri(FFile)),
    cTimeoutMs, AnswerHandler(FRequest)) then
  begin
    // Kein Server: in CostRefreshMs noch einmal.
    FPending := False;
  end;
end;

procedure TInterfaceCostState.Locate(const AView: IOTAEditView);
var
  mSnapshot: TAtlasEditorSnapshot;
  mCursor: TOTAEditPos;
  mFileName: string;
begin
  mFileName := AView.Buffer.FileName;
  mSnapshot := TAtlasEditorSnapshots.Get(AView);
  if (mSnapshot.Version <> FSectionsVersion) or not SameText(mFileName, FSectionsFile) then
  begin
    FSections := TAtlasSectionScanner.Scan(mSnapshot.Text);
    FSectionsVersion := mSnapshot.Version;
    FSectionsFile := mFileName;
  end;
  mCursor := AView.CursorPos;
  FInInterface := TAtlasInterfaceCostModel.InInterfacePart(FSections, mCursor.Line - 1, mCursor.Col - 1);
  if not SameText(mFileName, FFile) then
  begin
    // Dateiwechsel: alter Wert gilt nicht mehr, laufende Antworten fallen weg.
    Inc(FRequest);
    FFile := mFileName;
    FCost := Default(TAtlasInterfaceCost);
    FKnown := False;
    FPending := False;
    FAsked := GetTickCount - cCostRefreshMs;
  end;
end;

procedure TInterfaceCostState.Update;
var
  mView: IOTAEditView;
begin
  mView := nil;
  if Assigned(FShow) and TAtlasIdeSettings.Current.ShowInterfaceCost then
  begin
    mView := TAtlasEditorBuffer.ActiveView;
  end;
  // Nur Units haben einen interface-Teil.
  if (mView = nil) or (mView.Buffer = nil) or not SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Hide;
    Exit;
  end;
  Locate(mView);
  // Gefragt wird nur, solange die Marke im interface steht; im implementation-Teil braucht niemand den Wert.
  if FInInterface and not FPending and (GetTickCount - FAsked >= cCostRefreshMs) then
  begin
    Request;
  end;
  Show;
end;

{ TUnitRelationsState }

constructor TUnitRelationsState.Create(const ARun: TAtlasUnitRelationsRun);
begin
  inherited Create;
  FRun := ARun;
  FCache := TAtlasUnitRelationsCache.Create;
  FCost := TInterfaceCostState.Create(ARun, Self);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
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
  begin
    Wire(TAtlasIdeUnitRelationsWindow.ExistingFrame);
  end;
end;

destructor TUnitRelationsState.Destroy;
var
  mFrame: TAtlasUnitRelationsFrame;
begin
  // Antworten, die noch unterwegs sind, finden FState nicht mehr und fallen weg.
  Inc(FRequest);
  FCost.Cancel;
  FTimer.Free;
  FCost.Hide;
  TAtlasIdeUnitRelationsWindow.OnFrame := nil;
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.OnOpen := nil;
    mFrame.OnMove := nil;
    mFrame.OnRemove := nil;
    mFrame.OnDepthChanged := nil;
  end;
  FCache.Free;
  FCost.Free;
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
          Change(TAtlasUnitRelationsCommands.cMoveCommand, TAtlasUnitRelationsCommands.MoveArguments(
            TLspSession.PathToUri(FFileName), AUnit, AToInterface));
        end);
    end;
  AFrame.OnRemove :=
    procedure(const AUnit: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.UnitRelations,
        procedure
        begin
          Change(TAtlasUnitRelationsCommands.cRemoveCommand, TAtlasUnitRelationsCommands.RemoveArguments(
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
  mView: IOTAEditView;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and IsPascalFile(mView.Buffer.FileName) then
  begin
    Result := mView.Buffer.FileName;
  end;
end;

function TUnitRelationsState.Target: string;
var
  mEditor: string;
begin
  mEditor := EditorFile;
  if (FPinned <> '') and SameText(mEditor, FPinnedEditor) then
  begin
    Exit(FPinned);
  end;
  FPinned := '';
  Result := mEditor;
end;

procedure TUnitRelationsState.Pin(const AFileName: string);
begin
  FPinned := AFileName;
  FPinnedEditor := EditorFile;
end;

procedure TUnitRelationsState.Unpin;
begin
  FPinned := '';
end;

procedure TUnitRelationsState.SetCostHandler(const AShow: TAtlasInterfaceCostShow);
begin
  FCost.SetHandler(AShow);
end;

procedure TUnitRelationsState.HideCost;
begin
  FCost.Hide;
end;

procedure TUnitRelationsState.ShowJson(AFrame: TAtlasUnitRelationsFrame; const AJson: string);
var
  mRelations: TAtlasUnitRelations;
begin
  if AJson = FLastJson then
  begin
    Exit;
  end;
  if not TAtlasUnitRelationsModel.Parse(AJson, mRelations) then
  begin
    if not AFrame.HasRelations then
    begin
      ShowInfo(AFrame, TAtlasAnalysisTextId.UnitRelationsFailed);
    end;
    Exit;
  end;
  FLastJson := AJson;
  FShownMessage := False;
  // Der Server liest die Datei so, wie der Editor sie meldet; der Name im Fenster bleibt der des Editors.
  if mRelations.FileName = '' then
  begin
    mRelations.FileName := FFileName;
  end;
  AFrame.SetRelations(mRelations);
end;

procedure TUnitRelationsState.ShowInfo(AFrame: TAtlasUnitRelationsFrame; AId: TAtlasAnalysisTextId);
begin
  FLastJson := '';
  FShownMessage := True;
  AFrame.SetMessage(TAtlasAnalysisStrings.Text(AId));
end;

procedure TUnitRelationsState.Request;
var
  mFrame: TAtlasUnitRelationsFrame;
  mNumber: Integer;
  mFileName: string;
  mAllLevels: Boolean;
begin
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (mFrame = nil) or (FFileName = '') then
  begin
    Exit;
  end;
  Inc(FRequest);
  mNumber := FRequest;
  mFileName := FFileName;
  mAllLevels := FAllLevels;
  FPending := True;
  FAsked := GetTickCount;
  if not FRun(TAtlasUnitRelationsCommands.cCommand,
    TAtlasUnitRelationsCommands.Arguments(TLspSession.PathToUri(mFileName), mAllLevels), cTimeoutMs,
    AnswerHandler(mNumber, mFileName, mAllLevels)) then
  begin
    FPending := False;
    if not mFrame.HasRelations then
    begin
      ShowInfo(mFrame, TAtlasAnalysisTextId.UnitRelationsNoServer);
    end;
  end;
end;

function TUnitRelationsState.AnswerHandler(ANumber: Integer; const AFileName: string;
  AAllLevels: Boolean): TProc<TJSONValue>;
begin
  Result :=
    procedure(AAnswer: TJSONValue)
    begin
      if (TAtlasIdeUnitRelations.FState = Self) and (ANumber = FRequest) then
      begin
        TakeAnswer(AFileName, AAllLevels, AAnswer);
      end;
    end;
end;

procedure TUnitRelationsState.TakeAnswer(const AFileName: string; AAllLevels: Boolean; AAnswer: TJSONValue);
var
  mCurrent: TAtlasUnitRelationsFrame;
  mJson: string;
begin
  FPending := False;
  // Gezählt wird ab der Antwort: Ein langsamer Server bekommt nicht gleich die nächste Anfrage.
  FAsked := GetTickCount;
  mCurrent := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if mCurrent = nil then
  begin
    Exit;
  end;
  mJson := '';
  if AAnswer <> nil then
  begin
    mJson := AAnswer.ToJSON;
  end;
  if mJson <> '' then
  begin
    FCache.Put(AFileName, AAllLevels, mJson);
    ShowJson(mCurrent, mJson);
  end
  else if not mCurrent.HasRelations then
  begin
    ShowInfo(mCurrent, TAtlasAnalysisTextId.UnitRelationsFailed);
  end;
end;

procedure TUnitRelationsState.Update;
var
  mFrame: TAtlasUnitRelationsFrame;
  mFileName, mJson: string;
begin
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFileName := Target;
  if mFileName = '' then
  begin
    if (FFileName <> '') or not FShownMessage then
    begin
      FFileName := '';
      ShowInfo(mFrame, TAtlasAnalysisTextId.UnitRelationsNoFile);
    end;
    Exit;
  end;
  if not SameText(mFileName, FFileName) then
  begin
    // Dateiwechsel: gemerkter Stand sofort, die Antwort des Servers folgt.
    FFileName := mFileName;
    FLastJson := '';
    if FCache.TryGet(mFileName, FAllLevels, mJson) then
    begin
      ShowJson(mFrame, mJson);
    end
    else
    begin
      ShowInfo(mFrame, TAtlasAnalysisTextId.UnitRelationsLoading);
    end;
    Request;
    Exit;
  end;
  if not FPending and (GetTickCount - FAsked >= cRefreshMs) then
  begin
    Request;
  end;
end;

procedure TUnitRelationsState.ChangeDepth(AAllLevels: Boolean);
var
  mFrame: TAtlasUnitRelationsFrame;
  mJson: string;
begin
  if AAllLevels = FAllLevels then
  begin
    Exit;
  end;
  FAllLevels := AAllLevels;
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (mFrame = nil) or (FFileName = '') then
  begin
    Exit;
  end;
  FLastJson := '';
  if FCache.TryGet(FFileName, FAllLevels, mJson) then
  begin
    ShowJson(mFrame, mJson);
  end;
  Request;
end;

procedure TUnitRelationsState.Change(const ACommand, AArgumentsJson: string);
var
  mFrame: TAtlasUnitRelationsFrame;
begin
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if (mFrame = nil) or (FFileName = '') then
  begin
    Exit;
  end;
  if not FRun(ACommand, AArgumentsJson, cTimeoutMs,
    procedure(AAnswer: TJSONValue)
    var
      Edit: TLspWorkspaceEdit;
      Outcome: TAtlasWorkspaceEditResult;
      Current: TAtlasUnitRelationsFrame;
    begin
      if TAtlasIdeUnitRelations.FState <> Self then
      begin
        Exit;
      end;
      Current := TAtlasIdeUnitRelationsWindow.ExistingFrame;
      Edit := TLspWorkspaceEdit.FromJson(nil);
      if AAnswer is TJSONObject then
      begin
        Edit := TLspWorkspaceEdit.FromJson(TJSONObject(AAnswer).GetValue('edit'));
      end;
      if Edit.IsEmpty then
      begin
        if Current <> nil then
        begin
          Current.Info.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsEditRefused);
        end;
        Exit;
      end;
      Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, TAtlasUnopenedPolicy.OpenInEditor,
        TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsEditAction));
      if (Outcome.Error <> '') and (Current <> nil) then
      begin
        Current.Info.Caption := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsEditFailed,
          [Outcome.Error]);
      end;
      // Bald neu fragen: Der Server sieht den geänderten Text mit dem nächsten Abgleich des Puffers.
      FAsked := GetTickCount - cRefreshMs + 500;
    end) then
  begin
    mFrame.Info.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsNoServer);
  end;
end;

procedure TUnitRelationsState.Open(const AFileName: string; ALine, ACharacter: Integer);
var
  mActions: IOTAActionServices;
begin
  if AFileName = '' then
  begin
    Exit;
  end;
  if ALine >= 0 then
  begin
    TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
  end
  else if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    // Nur die Unit: Ist sie schon offen, bleibt der Cursor, wo er war.
    mActions.OpenFile(AFileName);
  end;
end;

procedure TUnitRelationsState.Tick(Sender: TObject);
begin
  if not Active then
  begin
    FCost.Hide;
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.UnitRelations,
    procedure
    begin
      if TAtlasIdeUnitRelationsWindow.Visible then
      begin
        Update;
      end;
      FCost.Update;
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
  mFrame: TAtlasUnitRelationsFrame;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeUnitRelationsWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  TUnitRelationsState(FState).Reset;
  TUnitRelationsState(FState).Update;
  if mFrame.Filter.CanFocus then
  begin
    mFrame.Filter.SetFocus;
  end;
end;

class procedure TAtlasIdeUnitRelations.ShowFor(const AFileName: string);
begin
  if (FState = nil) or not Active or (AFileName = '') then
  begin
    Exit;
  end;
  TUnitRelationsState(FState).Pin(AFileName);
  ShowWindow;
end;

class procedure TAtlasIdeUnitRelations.ShowCurrent;
begin
  if (FState = nil) or not Active then
  begin
    Exit;
  end;
  TUnitRelationsState(FState).Unpin;
  ShowWindow;
end;

class procedure TAtlasIdeUnitRelations.SetCostHandler(const AShow: TAtlasInterfaceCostShow);
begin
  if FState <> nil then
  begin
    TUnitRelationsState(FState).SetCostHandler(AShow);
  end;
end;

class procedure TAtlasIdeUnitRelations.ApplySettings;
begin
  if FState = nil then
  begin
    Exit;
  end;
  if not Active then
  begin
    TAtlasIdeUnitRelationsWindow.Hide;
  end;
  // build.showInterfaceCost oder Sprache geändert: Feld mit dem nächsten Takt neu.
  TUnitRelationsState(FState).HideCost;
end;

class procedure TAtlasIdeUnitRelations.ThemeChanged;
var
  mFrame: TAtlasUnitRelationsFrame;
begin
  TAtlasIdeUnitRelationsWindow.ApplyTheme;
  mFrame := TAtlasIdeUnitRelationsWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.Tree.Invalidate;
  end;
end;

end.
