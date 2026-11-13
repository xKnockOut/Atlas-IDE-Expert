unit Atlas.IDE.Debug.Logpoints;

// Logpunkte (#583), IDE-Schicht: Ein Logpunkt ist ein Quelltext-Haltepunkt
// der IDE ohne Anhalten (DoBreak aus) in der Gruppe cGroup, der eine Meldung
// und höchstens einen ausgewerteten Ausdruck ins Ereignisprotokoll schreibt
// (TAtlasLogpointPlan). Atlas führt Meldung und Wert im eigenen
// Ereignisprotokoll (#580) zu einer Zeile zusammen.
// - Set: an der Zeile eines Rechtsklicks in die Rinne
//   (TAtlasIdeGutterMarks.TakeLine), sonst an der Cursorzeile; der Dialog
//   (TAtlasLogpointDialog) setzt, ändert oder entfernt. Ein gewöhnlicher
//   Haltepunkt an der Zeile wird zum Logpunkt.
// - Den Text mit Platzhaltern merkt Atlas je Datei und Zeile, solange die IDE
//   läuft; sonst wird er aus Meldung und Ausdruck des Haltepunkts
//   zurückgewonnen.
// - Alle aus, an, löschen: nur Haltepunkte der Gruppe cGroup.
// - Lines/Item liefern der Rinne (TAtlasIdeLogpointGutter) die Zeilen ohne
//   IDE-Aufrufe; Refresh liest die Haltepunkte höchstens alle cRefreshMs neu.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.UI.Debug.LogpointDialog;

type
  /// <summary>Logpunkt an einer Zeile, wie ihn die Rinne zeigt.</summary>
  TAtlasIdeLogpointMark = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Enabled: Boolean;
    Input: TAtlasLogpointInput;
  end;

  TAtlasIdeLogpoints = class
  public const
    /// <summary>Haltepunktgruppe der Logpunkte (in der Haltepunktliste der IDE sichtbar).</summary>
    cGroup = 'Atlas.Logpunkte';
    cRefreshMs = 1000;
  private class var
    FMessage: TProc<string>;
    /// <summary>Text mit Platzhaltern je Schlüssel Datei|Zeile.</summary>
    FInputs: TDictionary<string, TAtlasLogpointInput>;
    /// <summary>Datei (groß) → Logpunkte; neu gelesen von Refresh.</summary>
    FMarks: TDictionary<string, TArray<TAtlasIdeLogpointMark>>;
    FRefreshedAt: UInt64;
    class function KeyOf(const AFileName: string; ALine: Integer): string; static;
    class function TargetLine(out AFileName: string; out ALine: Integer): Boolean; static;
    class function Find(const AFileName: string; ALine: Integer): IOTABreakpoint; static;
    class function InputOf(const ABreakpoint: IOTABreakpoint; ALine: Integer): TAtlasLogpointInput; static;
    class function Apply(const AFileName: string; ALine: Integer; const AExisting: IOTABreakpoint;
      const AInput: TAtlasLogpointInput): Boolean; static;
    class procedure Remove(const AFileName: string; ALine: Integer; const ABreakpoint: IOTABreakpoint); static;
    class function Own: TArray<IOTABreakpoint>; static;
    class procedure Say(const AText: string); static;
    class procedure Changed; static;
  public
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Gehört ABreakpoint zu den Logpunkten?</summary>
    class function IsLogpoint(const ABreakpoint: IOTABreakpoint): Boolean; static;
    /// <summary>Dialog für die Zeile der Rinne bzw. des Cursors.</summary>
    class procedure SetAtCursor; static;
    class procedure DisableAll; static;
    class procedure EnableAll; static;
    class procedure DeleteAll; static;
    /// <summary>Haltepunkte neu lesen; ohne AForce höchstens alle cRefreshMs.</summary>
    class procedure Refresh(AForce: Boolean); static;
    /// <summary>Logpunkte in AFileName (aus dem Zwischenstand von Refresh).</summary>
    class function Marks(const AFileName: string): TArray<TAtlasIdeLogpointMark>; static;
    class function TryMark(const AFileName: string; ALine: Integer; out AMark: TAtlasIdeLogpointMark): Boolean;
      static;
  end;

implementation

uses
  ToolsAPI.Editor,
  Atlas.Core.Debug.Logpoint,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.UI.Debug.Strings;

/// <summary>Ort für Meldung und Titel: "Unit1.pas:12".</summary>
function PlaceOf(const AFileName: string; ALine: Integer): string;
begin
  Result := ExtractFileName(AFileName) + ':' + IntToStr(ALine + 1);
end;

/// <summary>Text des Logpunkts als Text der Vorlage: Klammern verdoppelt.</summary>
function Escaped(const AText: string): string;
begin
  Result := AText.Replace('{', '{{').Replace('}', '}}');
end;

/// <summary>Text der Vorlage aus Meldung und Ausdruck eines Haltepunkts (ohne gemerkten Text).</summary>
function TemplateOf(const AMessage, AExpression, APrefix: string): string;
var
  mText: string;
  mAt: Integer;
begin
  mText := Trim(AMessage);
  if (APrefix <> '') and mText.StartsWith(APrefix, True) then
  begin
    mText := TrimLeft(Copy(mText, Length(APrefix) + 1, MaxInt));
  end;
  mAt := mText.LastIndexOf(TAtlasLogpointPlan.cPlaceMark);
  if mAt >= 0 then
  begin
    mText := Copy(mText, 1, mAt);
  end;
  mAt := Pos(TAtlasLogpointPlan.cValueMark, mText);
  if (AExpression = '') or (mAt = 0) then
  begin
    Exit(Escaped(mText));
  end;
  // Ein Platzhalter ohne Angabe wertet denselben Ausdruck aus, auch einen zusammengesetzten.
  Result := Escaped(Copy(mText, 1, mAt - 1)) + '{' + AExpression + '}' +
    Escaped(Copy(mText, mAt + Length(TAtlasLogpointPlan.cValueMark), MaxInt));
end;

{ TAtlasIdeLogpoints }

class procedure TAtlasIdeLogpoints.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FInputs = nil then
  begin
    FInputs := TDictionary<string, TAtlasLogpointInput>.Create;
  end;
  if FMarks = nil then
  begin
    FMarks := TDictionary<string, TArray<TAtlasIdeLogpointMark>>.Create;
  end;
  Refresh(True);
end;

class procedure TAtlasIdeLogpoints.Release;
begin
  FreeAndNil(FMarks);
  FreeAndNil(FInputs);
  FMessage := nil;
  FRefreshedAt := 0;
end;

class function TAtlasIdeLogpoints.Started: Boolean;
begin
  Result := FInputs <> nil;
end;

class procedure TAtlasIdeLogpoints.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeLogpoints.KeyOf(const AFileName: string; ALine: Integer): string;
begin
  Result := UpperCase(AFileName) + '|' + IntToStr(ALine);
end;

class function TAtlasIdeLogpoints.IsLogpoint(const ABreakpoint: IOTABreakpoint): Boolean;
begin
  Result := (ABreakpoint <> nil) and SameText(ABreakpoint.GroupName, cGroup);
end;

class function TAtlasIdeLogpoints.TargetLine(out AFileName: string; out ALine: Integer): Boolean;
var
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Exit(False);
  end;
  AFileName := mView.Buffer.FileName;
  // Rechtsklick in die Rinne gilt vor dem Cursor, solange er frisch ist und zur Datei passt.
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
  Result := ALine >= 0;
end;

class function TAtlasIdeLogpoints.Find(const AFileName: string; ALine: Integer): IOTABreakpoint;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mExisting: IOTASourceBreakpoint;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mExisting := mServices.SourceBkpts[mIndex];
    if (mExisting <> nil) and SameText(mExisting.FileName, AFileName) and (mExisting.LineNumber = ALine + 1) then
    begin
      Exit(mExisting);
    end;
  end;
end;

class function TAtlasIdeLogpoints.InputOf(const ABreakpoint: IOTABreakpoint; ALine: Integer): TAtlasLogpointInput;
begin
  Result := Default(TAtlasLogpointInput);
  if not IsLogpoint(ABreakpoint) then
  begin
    Exit;
  end;
  if FInputs.TryGetValue(KeyOf(ABreakpoint.FileName, ALine), Result) then
  begin
    Exit;
  end;
  Result.Text := TemplateOf(ABreakpoint.LogMessage, ABreakpoint.EvalExpression,
    TAtlasIdeSettings.Current.DebugLogpointPrefix);
  Result.Condition := ABreakpoint.Expression;
  Result.PassCount := ABreakpoint.PassCount;
end;

class function TAtlasIdeLogpoints.Apply(const AFileName: string; ALine: Integer; const AExisting: IOTABreakpoint;
  const AInput: TAtlasLogpointInput): Boolean;
var
  mBreakpoint: IOTABreakpoint;
  mPlan: TAtlasLogpointPlan;
begin
  mBreakpoint := AExisting;
  if mBreakpoint = nil then
  begin
    mBreakpoint := TAtlasIdeBreakpoints.Add(AFileName, ALine, cGroup);
  end;
  if mBreakpoint = nil then
  begin
    Exit(False);
  end;
  mPlan := TAtlasLogpointPlan.Build(TAtlasLogpointTemplate.Parse(AInput.Text),
    TAtlasIdeSettings.Current.DebugLogpointPrefix, PlaceOf(AFileName, ALine), AInput.Condition, AInput.PassCount);
  mBreakpoint.GroupName := cGroup;
  mBreakpoint.DoBreak := False;
  mBreakpoint.LogMessage := mPlan.LogMessage;
  mBreakpoint.EvalExpression := mPlan.EvalExpression;
  mBreakpoint.LogResult := mPlan.EvalExpression <> '';
  mBreakpoint.Expression := mPlan.Condition;
  mBreakpoint.PassCount := mPlan.PassCount;
  mBreakpoint.Enabled := True;
  FInputs.AddOrSetValue(KeyOf(AFileName, ALine), AInput);
  Result := True;
end;

class procedure TAtlasIdeLogpoints.Remove(const AFileName: string; ALine: Integer;
  const ABreakpoint: IOTABreakpoint);
var
  mServices: IOTADebuggerServices;
begin
  FInputs.Remove(KeyOf(AFileName, ALine));
  mServices := TAtlasIdeBreakpoints.Debugger;
  if (mServices <> nil) and (ABreakpoint <> nil) then
  begin
    mServices.RemoveBreakpoint(ABreakpoint);
  end;
end;

class procedure TAtlasIdeLogpoints.SetAtCursor;
var
  mFileName: string;
  mLine: Integer;
  mExisting: IOTABreakpoint;
  mInput: TAtlasLogpointInput;
  mPlace: string;
begin
  if not Started then
  begin
    Exit;
  end;
  if not TargetLine(mFileName, mLine) then
  begin
    Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointNoEditor));
    Exit;
  end;
  mExisting := Find(mFileName, mLine);
  mInput := InputOf(mExisting, mLine);
  mPlace := PlaceOf(mFileName, mLine);
  case TAtlasLogpointDialog.Execute(mPlace, IsLogpoint(mExisting), mInput) of
    TAtlasLogpointChoice.SetLogpoint:
      if Apply(mFileName, mLine, mExisting, mInput) then
      begin
        Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LogpointSaidSet, [mPlace]));
      end
      else
      begin
        Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointFailed));
      end;
    TAtlasLogpointChoice.Remove:
      begin
        Remove(mFileName, mLine, mExisting);
        Say(TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointSaidRemoved));
      end;
  else
    Exit;
  end;
  Changed;
end;

class function TAtlasIdeLogpoints.Own: TArray<IOTABreakpoint>;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTABreakpoint;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.SourceBkptCount - 1 do
  begin
    mBreakpoint := mServices.SourceBkpts[mIndex];
    if IsLogpoint(mBreakpoint) then
    begin
      Result := Result + [mBreakpoint];
    end;
  end;
end;

class procedure TAtlasIdeLogpoints.DisableAll;
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoints := Own;
  for mBreakpoint in mBreakpoints do
  begin
    mBreakpoint.Enabled := False;
  end;
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LogpointSaidDisabled, [Length(mBreakpoints)]));
  Changed;
end;

class procedure TAtlasIdeLogpoints.EnableAll;
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mBreakpoint: IOTABreakpoint;
begin
  mBreakpoints := Own;
  for mBreakpoint in mBreakpoints do
  begin
    mBreakpoint.Enabled := True;
  end;
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LogpointSaidEnabled, [Length(mBreakpoints)]));
  Changed;
end;

class procedure TAtlasIdeLogpoints.DeleteAll;
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mBreakpoint: IOTABreakpoint;
  mServices: IOTADebuggerServices;
begin
  mServices := TAtlasIdeBreakpoints.Debugger;
  mBreakpoints := Own;
  if mServices <> nil then
  begin
    for mBreakpoint in mBreakpoints do
    begin
      mServices.RemoveBreakpoint(mBreakpoint);
    end;
  end;
  if FInputs <> nil then
  begin
    FInputs.Clear;
  end;
  Say(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.LogpointSaidDeleted, [Length(mBreakpoints)]));
  Changed;
end;

class procedure TAtlasIdeLogpoints.Changed;
var
  mEditors: INTACodeEditorServices;
begin
  Refresh(True);
  if Supports(BorlandIDEServices, INTACodeEditorServices, mEditors) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mEditors);
  end;
end;

class procedure TAtlasIdeLogpoints.Refresh(AForce: Boolean);
var
  mBreakpoint: IOTABreakpoint;
  mSource: IOTASourceBreakpoint;
  mMark: TAtlasIdeLogpointMark;
  mKey: string;
  mList: TArray<TAtlasIdeLogpointMark>;
begin
  if (FMarks = nil) or (not AForce and (GetTickCount64 - FRefreshedAt < cRefreshMs)) then
  begin
    Exit;
  end;
  FRefreshedAt := GetTickCount64;
  FMarks.Clear;
  for mBreakpoint in Own do
  begin
    if not Supports(mBreakpoint, IOTASourceBreakpoint, mSource) then
    begin
      Continue;
    end;
    mMark := Default(TAtlasIdeLogpointMark);
    mMark.Line := mSource.LineNumber - 1;
    mMark.Enabled := mSource.Enabled;
    mMark.Input := InputOf(mSource, mMark.Line);
    mKey := UpperCase(mSource.FileName);
    mList := nil;
    FMarks.TryGetValue(mKey, mList);
    FMarks.AddOrSetValue(mKey, mList + [mMark]);
  end;
end;

class function TAtlasIdeLogpoints.Marks(const AFileName: string): TArray<TAtlasIdeLogpointMark>;
begin
  Result := nil;
  if FMarks <> nil then
  begin
    FMarks.TryGetValue(UpperCase(AFileName), Result);
  end;
end;

class function TAtlasIdeLogpoints.TryMark(const AFileName: string; ALine: Integer;
  out AMark: TAtlasIdeLogpointMark): Boolean;
var
  mMark: TAtlasIdeLogpointMark;
begin
  AMark := Default(TAtlasIdeLogpointMark);
  for mMark in Marks(AFileName) do
  begin
    if mMark.Line = ALine then
    begin
      AMark := mMark;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
