unit Atlas.IDE.Debug.ObjectMarks;

// Objekte beim Debuggen markieren (#839) in der IDE:
//   - Markieren: Befehl „Objekt markieren …“ (Kontextmenü des Editors im Halt, Fenster „Auswerten“) für den
//     Ausdruck an der Schreibmarke. Adresse über „Pointer(Ausdruck)“ ohne Nebenwirkungen, Klasse aus der VMT im
//     Speicher des Programms (keine Auswertung im Programm), Vorschlag aus Klasse und „Ausdruck.Name“ (Getter
//     erlaubt). Das Etikett fragt InputQuery ab.
//   - Anzeige: Caption liefert zu einem Ausdruck mit einem Wert, der wie ein Objekt aussieht, das Etikett; für
//     Werte im Editor (#508), den Debug-Hover und das Fenster „Auswerten“ (#784). Nur mit Markierungen; die Adresse
//     jedes Ausdrucks wertet Atlas einmal je Halt aus (cAddressTimeoutMs). Gefundene Objekte gelten als „zuletzt
//     gesehen“ unter diesem Ausdruck.
//   - Halt: Atlas liest an jeder markierten Adresse die Klasse aus der VMT; steht dort eine andere als beim
//     Markieren, gilt das Objekt als „vermutlich freigegeben“ und sein Etikett erscheint nirgends mehr.
//   - Ende der Sitzung (ProcessDestroyed): Markierungen und Fenster sind leer.
//   - Fenster „Markierte Objekte“ (TAtlasIdeDebugDockPanel): Etikett, Klasse, Adresse, zuletzt gesehen, Zustand;
//     Entfernen, Farbe wechseln, Etikett ändern.
// Teil „DebugObjectMarks“ (debug.objectMarks); aus = nichts angemeldet, kein Menüpunkt, keine Etiketten. Nur im
// Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Hover.Contract.DebugValue,
  Atlas.Core.Debug.ObjectMarks,
  Atlas.IDE.Debug.StopView,
  Atlas.IDE.Debug.DockPanel,
  Atlas.UI.Debug.ObjectMarksFrame;

type
  TAtlasIdeDebugObjectMarks = class(TAtlasIdeDebugStopView)
  public const
    /// <summary>So lange wartet Atlas auf die Adresse eines Ausdrucks (verzögert unter LLDB).</summary>
    cAddressTimeoutMs = 300;
    /// <summary>Ab dem Halt bis zum Abgleich mit dem Speicher.</summary>
    cCheckDelayMs = 50;
  private class var
    FInstance: TAtlasIdeDebugObjectMarks;
  private
    FMarks: TAtlasObjectMarks;
    /// <summary>Adresse je Ausdruck im jetzigen Halt; 0 = kein Objekt.</summary>
    FAddresses: TDictionary<string, UInt64>;
    FPanel: TAtlasIdeDebugDockPanel;
    FMessage: TProc<string>;
    constructor Create(const AMessage: TProc<string>);
    function AddressOf(const AExpression: string): UInt64;
    procedure CheckMarks;
    procedure Refresh;
    procedure WireFrame(AFrame: TAtlasDebugObjectMarksFrame);
    procedure Rename(AAddress: UInt64);
    function Frame: TAtlasDebugObjectMarksFrame;
  protected
    procedure SessionStarted; override;
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    procedure Advance; override;
  public
    destructor Destroy; override;
    /// <summary>Teil starten; AMessage schreibt in die Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.objectMarks an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Etikett des Objekts unter AExpression mit dem Wert AValueText an AFileName, ALine (1-basiert); ''
    /// ohne Markierung. Merkt das Objekt als gesehen.</summary>
    class function Caption(const AExpression, AValueText, AFileName: string; ALine: Integer): string; static;
    /// <summary>AValueText mit dem Etikett dahinter („(FNr: 4)  ‹Kunde A›“); ohne Etikett unverändert.</summary>
    class function Decorate(const AExpression, AValueText, AFileName: string; ALine: Integer): string; static;
    /// <summary>Für Werte im Editor: Etikett vorn („‹Kunde A› (FNr: 4)“), weil lange Werte hinten gekürzt werden.
    /// </summary>
    class function DecorateInline(const AExpression, AValueText, AFileName: string; ALine: Integer): string; static;
    /// <summary>Für das Fenster „Auswerten“: nur der Zusatz hinter dem Wert („  ‹Kunde A›“); '' ohne Etikett.
    /// </summary>
    class function Suffix(const AExpression, AValueText, AFileName: string; ALine: Integer): string; static;
    /// <summary>Für den Debug-Hover: Wert mit Etikett.</summary>
    class function DecorateHover(const AValue: TAtlasDebugValue; const AFileName: string;
      ALine: Integer): TAtlasDebugValue; static;
    /// <summary>AExpression markieren: Adresse und Klasse lesen, Etikett abfragen. False ohne Objekt.</summary>
    class function MarkExpression(const AExpression, AFileName: string; ALine: Integer): Boolean; static;
    /// <summary>Befehl Atlas.DebugMarkObject: Ausdruck an der Schreibmarke markieren.</summary>
    class procedure MarkAtCursor; static;
    /// <summary>Befehl Atlas.DebugObjectMarks: Fenster „Markierte Objekte“.</summary>
    class procedure ShowWindow; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Debug.InstanceBreakpoint,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Foundation.Settings,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Evaluator,
  Atlas.UI.Debug.ObjectMarks.Strings,
  Atlas.IDE.Hover.DebugValue;

/// <summary>Zeigergröße des Programms: 8 unter Win64, sonst 4.</summary>
function PointerSize: Integer;
begin
  Result := TAtlasObjectMarks.cPointerSize32;
  if SameText(TAtlasIdeDebugSession.LaunchPlatform, 'Win64') then
  begin
    Result := TAtlasObjectMarks.cPointerSize64;
  end;
end;

/// <summary>Klasse des Objekts an AAddress aus dem Speicher des angehaltenen Programms; '' wenn nicht lesbar.
/// </summary>
function ClassAt(AAddress: UInt64): string;
begin
  Result := TAtlasObjectMarks.ReadClassName(AAddress, PointerSize,
    function(AAt: UInt64; ACount: Integer; out ABytes: TBytes): Boolean
    begin
      Result := TAtlasIdeDebugEvaluator.ReadMemory(AAt, ACount, ABytes);
    end);
end;

/// <summary>AExpression im angehaltenen Programm als eigene Auswertung der Sitzung (Zustandswechsel sind kein
/// Fortsetzen).</summary>
function EvaluateQuietly(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
  out AText: string): Boolean;
begin
  TAtlasIdeDebugSession.BeginInternal;
  try
    Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, AEvaluation,
      TAtlasIdeDebugObjectMarks.cAddressTimeoutMs, AText);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

{ TAtlasIdeDebugObjectMarks }

constructor TAtlasIdeDebugObjectMarks.Create(const AMessage: TProc<string>);
begin
  inherited Create;
  FMessage := AMessage;
  FMarks := TAtlasObjectMarks.Create;
  FAddresses := TDictionary<string, UInt64>.Create;
  FPanel := TAtlasIdeDebugDockPanel.Create('AtlasDebugObjectMarks', TAtlasDebugObjectMarksFrame,
    function: string
    begin
      Result := TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksCaption);
    end);
  CreateTimer(cCheckDelayMs);
end;

destructor TAtlasIdeDebugObjectMarks.Destroy;
begin
  FreeAndNil(FPanel);
  FreeAndNil(FAddresses);
  FreeAndNil(FMarks);
  FMessage := nil;
  inherited Destroy;
end;

function TAtlasIdeDebugObjectMarks.Frame: TAtlasDebugObjectMarksFrame;
begin
  Result := nil;
  if (FPanel <> nil) and (FPanel.ExistingFrame is TAtlasDebugObjectMarksFrame) then
  begin
    Result := TAtlasDebugObjectMarksFrame(FPanel.ExistingFrame);
  end;
end;

procedure TAtlasIdeDebugObjectMarks.Refresh;
var
  mFrame: TAtlasDebugObjectMarksFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetMarks(FMarks.Items);
  end;
end;

procedure TAtlasIdeDebugObjectMarks.SessionStarted;
begin
  FMarks.Clear;
  FAddresses.Clear;
  Refresh;
end;

procedure TAtlasIdeDebugObjectMarks.SessionStopped;
begin
  FAddresses.Clear;
  if FMarks.Count > 0 then
  begin
    // Kurz nach dem Halt: Der Debugger hat den Prozess dann sicher angehalten.
    FTimer.Enabled := True;
  end;
end;

procedure TAtlasIdeDebugObjectMarks.SessionResumed;
begin
  FTimer.Enabled := False;
  FAddresses.Clear;
end;

procedure TAtlasIdeDebugObjectMarks.SessionEnded;
begin
  FTimer.Enabled := False;
  FMarks.Clear;
  FAddresses.Clear;
  Refresh;
end;

procedure TAtlasIdeDebugObjectMarks.Advance;
begin
  FTimer.Enabled := False;
  CheckMarks;
end;

procedure TAtlasIdeDebugObjectMarks.CheckMarks;
var
  mMark: TAtlasObjectMark;
  mChanged: Boolean;
begin
  if TAtlasIdeDebugValues.StoppedThread = nil then
  begin
    Exit;
  end;
  mChanged := False;
  for mMark in FMarks.Items do
  begin
    if not mMark.Freed and FMarks.Check(mMark.Address, ClassAt(mMark.Address)) then
    begin
      mChanged := True;
    end;
  end;
  if mChanged then
  begin
    Refresh;
  end;
end;

function TAtlasIdeDebugObjectMarks.AddressOf(const AExpression: string): UInt64;
var
  mKey, mText: string;
begin
  mKey := LowerCase(Trim(AExpression));
  if FAddresses.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := 0;
  if EvaluateQuietly(Format(TAtlasObjectMarks.cAddressExpression, [Trim(AExpression)]),
    TAtlasVisualizerEvaluation.Fields, mText) and not TAtlasInstanceBreakpoint.TryParseAddress(mText, Result) then
  begin
    Result := 0;
  end;
  FAddresses.AddOrSetValue(mKey, Result);
end;

class function TAtlasIdeDebugObjectMarks.Caption(const AExpression, AValueText, AFileName: string;
  ALine: Integer): string;
var
  mAddress: UInt64;
begin
  Result := '';
  if (FInstance = nil) or (FInstance.FMarks.Count = 0) or not TAtlasObjectMarks.LooksLikeObject(AValueText) or
    (TAtlasIdeDebugValues.StoppedThread = nil) then
  begin
    Exit;
  end;
  mAddress := FInstance.AddressOf(AExpression);
  Result := FInstance.FMarks.CaptionOf(mAddress);
  if (Result <> '') and FInstance.FMarks.Seen(mAddress, AExpression, TAtlasObjectMarks.PlaceText(AFileName, ALine))
  then
  begin
    FInstance.Refresh;
  end;
end;

class function TAtlasIdeDebugObjectMarks.Decorate(const AExpression, AValueText, AFileName: string;
  ALine: Integer): string;
begin
  Result := TAtlasObjectMarks.Decorate(AValueText, Caption(AExpression, AValueText, AFileName, ALine),
    TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksValueFormat));
end;

class function TAtlasIdeDebugObjectMarks.DecorateInline(const AExpression, AValueText, AFileName: string;
  ALine: Integer): string;
begin
  Result := TAtlasObjectMarks.Decorate(AValueText, Caption(AExpression, AValueText, AFileName, ALine),
    TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksInlineFormat));
end;

class function TAtlasIdeDebugObjectMarks.Suffix(const AExpression, AValueText, AFileName: string;
  ALine: Integer): string;
begin
  Result := TAtlasObjectMarks.Decorate('', Caption(AExpression, AValueText, AFileName, ALine),
    TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.ObjectMarksValueFormat));
end;

class function TAtlasIdeDebugObjectMarks.DecorateHover(const AValue: TAtlasDebugValue; const AFileName: string;
  ALine: Integer): TAtlasDebugValue;
begin
  Result := AValue;
  if AValue.State = TAtlasDebugValueState.Value then
  begin
    Result.Text := Decorate(AValue.Expression, AValue.Text, AFileName, ALine);
  end;
end;

class function TAtlasIdeDebugObjectMarks.MarkExpression(const AExpression, AFileName: string; ALine: Integer): Boolean;
var
  mAddress: UInt64;
  mText, mTypeName, mName, mCaption: string;
begin
  Result := False;
  if (FInstance = nil) or (Trim(AExpression) = '') or (TAtlasIdeDebugValues.StoppedThread = nil) then
  begin
    Exit;
  end;
  mAddress := 0;
  if not EvaluateQuietly(Format(TAtlasObjectMarks.cAddressExpression, [Trim(AExpression)]),
    TAtlasVisualizerEvaluation.Fields, mText) or not TAtlasInstanceBreakpoint.TryParseAddress(mText, mAddress) then
  begin
    FInstance.FMessage(TAtlasObjectMarksStrings.Fmt(TAtlasObjectMarksTextId.MarkObjectNoObject, [AExpression]));
    Exit;
  end;
  mTypeName := ClassAt(mAddress);
  mName := '';
  // Namensfeld nur als Vorschlag: Getter erlaubt, Aufrufe nicht.
  if (mTypeName <> '') and not EvaluateQuietly(Trim(AExpression) + '.Name', TAtlasVisualizerEvaluation.Properties,
    mName) then
  begin
    mName := '';
  end;
  mCaption := FInstance.FMarks.CaptionOf(mAddress);
  if mCaption = '' then
  begin
    mCaption := TAtlasObjectMarks.Suggest(mTypeName, mName);
  end;
  if not InputQuery(TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.MarkObjectTitle),
    TAtlasObjectMarksStrings.Fmt(TAtlasObjectMarksTextId.MarkObjectPrompt, [AExpression]), mCaption) then
  begin
    Exit;
  end;
  Result := FInstance.FMarks.Mark(mAddress, mCaption, mTypeName, AExpression,
    TAtlasObjectMarks.PlaceText(AFileName, ALine));
  if Result then
  begin
    FInstance.FTimer.Enabled := False;
    FInstance.Refresh;
    // Werte im Editor und Fenster zeigen das Etikett beim nächsten Halt; der Hover sofort.
    FInstance.FMessage(TAtlasObjectMarksStrings.Fmt(TAtlasObjectMarksTextId.MarkObjectDone,
      [mCaption, TAtlasInstanceBreakpoint.AddressText(mAddress)]));
  end;
end;

class procedure TAtlasIdeDebugObjectMarks.MarkAtCursor;
var
  mView: IOTAEditView;
  mLine, mExpression: string;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  mExpression := '';
  if (mView <> nil) and (mView.Buffer <> nil) then
  begin
    mLine := TAtlasEditorBuffer.LineText(mView, mView.CursorPos.Line);
    // CursorPos.Col ist 1-basiert und steht hinter dem Zeichen; Tabs zählen hier wie ein Zeichen.
    mExpression := TAtlasDebugExpression.AtCharacter(mLine, mView.CursorPos.Col - 1);
    if mExpression = '' then
    begin
      mExpression := TAtlasDebugExpression.AtCharacter(mLine, mView.CursorPos.Col - 2);
    end;
  end;
  if mExpression = '' then
  begin
    FInstance.FMessage(TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.MarkObjectNoExpression));
    Exit;
  end;
  MarkExpression(mExpression, mView.Buffer.FileName, mView.CursorPos.Line);
end;

procedure TAtlasIdeDebugObjectMarks.Rename(AAddress: UInt64);
var
  mMark: TAtlasObjectMark;
  mCaption: string;
begin
  if not FMarks.Find(AAddress, mMark) then
  begin
    Exit;
  end;
  mCaption := mMark.Caption;
  if InputQuery(TAtlasObjectMarksStrings.Text(TAtlasObjectMarksTextId.MarkObjectTitle),
    TAtlasObjectMarksStrings.Fmt(TAtlasObjectMarksTextId.MarkObjectPrompt, [mMark.LastExpression]), mCaption) and
    FMarks.Mark(AAddress, mCaption, mMark.TypeName, mMark.LastExpression, mMark.LastPlace) then
  begin
    Refresh;
  end;
end;

procedure TAtlasIdeDebugObjectMarks.WireFrame(AFrame: TAtlasDebugObjectMarksFrame);
begin
  AFrame.OnRemove :=
    procedure(AAddress: UInt64)
    begin
      if FMarks.Remove(AAddress) then
      begin
        Refresh;
      end;
    end;
  AFrame.OnColor :=
    procedure(AAddress: UInt64)
    var
      mMark: TAtlasObjectMark;
    begin
      if FMarks.Find(AAddress, mMark) and FMarks.SetColor(AAddress, mMark.Color + 1) then
      begin
        Refresh;
      end;
    end;
  AFrame.OnRename :=
    procedure(AAddress: UInt64)
    begin
      Rename(AAddress);
    end;
  AFrame.SetMarks(FMarks.Items);
end;

class procedure TAtlasIdeDebugObjectMarks.Start(const AMessage: TProc<string>);
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeDebugObjectMarks.Create(AMessage);
  FInstance.FPanel.OnFrame :=
    procedure(AFrame: TCustomFrame)
    begin
      if (FInstance <> nil) and (AFrame is TAtlasDebugObjectMarksFrame) then
      begin
        FInstance.WireFrame(TAtlasDebugObjectMarksFrame(AFrame));
      end;
    end;
  // Früh anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).
  FInstance.FPanel.Prepare;
  FInstance.Listen;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugObjectMarks.Release;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeDebugObjectMarks.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugObjectMarks.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugObjectMarks;
end;

class procedure TAtlasIdeDebugObjectMarks.ShowWindow;
begin
  if FInstance <> nil then
  begin
    FInstance.FPanel.Show;
    FInstance.Refresh;
  end;
end;

class procedure TAtlasIdeDebugObjectMarks.ThemeChanged;
begin
  if FInstance <> nil then
  begin
    FInstance.FPanel.ApplyTheme;
  end;
end;

end.
