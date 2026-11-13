unit Atlas.IDE.Debug.DataBreakpoint;

// Anhalten, wenn sich ein Feld ändert (#584) im Debugger der IDE:
// - Befehl Atlas.BreakOnFieldChange „Anhalten, wenn sich FKunde.FSumme
//   ändert“ (Kontextmenü des Editors, nur im angehaltenen Programm): Atlas
//   wertet „Pointer(@FKunde.FSumme)“, „SizeOf(FKunde.FSumme)“ und
//   „SizeOf(Pointer)“ aus und legt mit IOTADebuggerServices.NewAddressBreakpoint
//   einen Datenhaltepunkt (Schreiben) an. Plan und Grenzen kommen aus dem Kern
//   (Atlas.Core.Debug.DataBreakpoint): vier Plätze, 4 Byte unter Win32, 8 unter
//   Win64, ausgerichtet. Ist das Feld größer, fragt Atlas, ob nur der erste Teil
//   überwacht werden soll; bei Strings überwacht der Platz den Zeiger.
// - Belegte Plätze zählt Atlas selbst: aktive Adresshaltepunkte der IDE, die
//   nicht auf Ausführen stehen. Sind alle belegt, kommt eine Meldung statt
//   eines Haltepunkts.
// - Hinweis beim Setzen: gilt nur für dieses eine Objekt; am Ende der Sitzung
//   entfernt Atlas seine Datenhaltepunkte, weil die Adresse beim nächsten Lauf
//   nicht mehr stimmt.
// - Bei jedem Halt liest Atlas die überwachten Bytes neu. Haben sie sich
//   geändert, stehen alter und neuer Wert in der Meldungsansicht und bis zum
//   Weiterlaufen im Atlas-Statusfeld.
// Ein Teil der Feature-Tabelle (debug.dataBreakpoints): aus = kein Zuhörer,
// Befehl unsichtbar. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.DataBreakpoint,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeDataBreakpoint = class
  private const
    cTimeoutMs = 2000;
    cStatusId = 'atlas.debug.dataBreakpoint';
  private type
    /// <summary>Ein gesetzter Datenhaltepunkt mit dem zuletzt gezeigten Wert.</summary>
    TWatch = record
      Expression: string;
      Breakpoint: IOTABreakpoint;
      Plan: TAtlasDataWatchPlan;
      Kind: TAtlasDataValueKind;
      Value: string;
      Bytes: TBytes;
    end;

    TListener = class(TAtlasIdeDebugListener)
    public
      procedure DebugStopped(AStop: TAtlasDebugStop); override;
      procedure DebugResumed; override;
      procedure DebugEnded; override;
    end;
  private class var
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    FWatches: TList<TWatch>;
    class procedure Report(const AText: string); static;
    class function Evaluate(const AExpression: string; out AValue: string): Boolean; static;
    /// <summary>Ausdruck unter der Schreibmarke des obersten Editors; '' ohne.</summary>
    class function CursorExpression: string; static;
    /// <summary>Ausdruck für den Befehl: Teil an, Programm angehalten, Feld unter der Schreibmarke, Platz frei;
    /// False mit Meldung sonst.</summary>
    class function TargetExpression(out AExpression: string): Boolean; static;
    /// <summary>Neuer Eintrag mit aktuellem Wert und Bytes, noch ohne Haltepunkt.</summary>
    class function NewWatch(const AExpression: string; const APlan: TAtlasDataWatchPlan): TWatch; static;
    /// <summary>Aktive Datenhaltepunkte der IDE (Adresshaltepunkte zum Lesen oder Schreiben).</summary>
    class function UsedSlots: Integer; static;
    /// <summary>Plan für AExpression aus Adresse und Größe; False mit Meldung, wenn der Debugger sie nicht liefert.
    /// </summary>
    class function PlanFor(const AExpression: string; out APlan: TAtlasDataWatchPlan): Boolean; static;
    /// <summary>Nur einen Teil überwachen? Fragt bei zu großen Feldern; True ohne Frage sonst.</summary>
    class function AcceptPlan(const AExpression: string; const APlan: TAtlasDataWatchPlan): Boolean; static;
    class function CreateBreakpoint(const APlan: TAtlasDataWatchPlan): IOTABreakpoint; static;
    /// <summary>Anzeigetext des Werts nach einer Änderung.</summary>
    class function NewValue(const AWatch: TWatch; const ABytes: TBytes): string; static;
    class procedure CheckChanges; static;
    class procedure ClearStatus; static;
    class procedure RemoveWatches(AReport: Boolean); static;
  public
    /// <summary>Teil starten: Zuhörer bei der Debug-Sitzung anmelden. AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    /// <summary>Zuhörer abmelden, eigene Datenhaltepunkte entfernen.</summary>
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Text des Befehls: mit dem Ausdruck unter der Schreibmarke, solange das Programm angehalten ist.
    /// </summary>
    class function CommandCaption: string; static;
    /// <summary>Befehl Atlas.BreakOnFieldChange.</summary>
    class procedure WatchAtCursor; static;
  end;

implementation

uses
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.InstanceBreakpoint,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.Evaluator,
  Atlas.UI.Debug.Strings;

{ TAtlasIdeDataBreakpoint.TListener }

procedure TAtlasIdeDataBreakpoint.TListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  TAtlasIdeDataBreakpoint.CheckChanges;
end;

procedure TAtlasIdeDataBreakpoint.TListener.DebugResumed;
begin
  TAtlasIdeDataBreakpoint.ClearStatus;
end;

procedure TAtlasIdeDataBreakpoint.TListener.DebugEnded;
begin
  TAtlasIdeDataBreakpoint.RemoveWatches(True);
end;

{ TAtlasIdeDataBreakpoint }

class procedure TAtlasIdeDataBreakpoint.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FWatches = nil then
  begin
    FWatches := TList<TWatch>.Create;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
  end;
end;

class procedure TAtlasIdeDataBreakpoint.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  RemoveWatches(False);
  ClearStatus;
  FMessage := nil;
  FreeAndNil(FWatches);
end;

class function TAtlasIdeDataBreakpoint.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeDataBreakpoint.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeDataBreakpoint.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  // Eigene Auswertung: Zustandswechsel dabei sind kein Weiterlaufen.
  TAtlasIdeDebugSession.BeginInternal;
  try
    Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Fields, cTimeoutMs, AValue);
  finally
    TAtlasIdeDebugSession.EndInternal;
  end;
end;

class function TAtlasIdeDataBreakpoint.CursorExpression: string;
var
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
  mLine: string;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := mView.CursorPos;
  mLine := TAtlasEditorBuffer.LineText(mView, mCursor.Line);
  Result := TAtlasDataBreakpoint.ExpressionAt(mLine, TLspSession.ColumnToIndex(mLine, mCursor.Col,
    TAtlasEditorBuffer.TabWidth(mView.Buffer)));
end;

class function TAtlasIdeDataBreakpoint.CommandCaption: string;
var
  mExpression: string;
begin
  mExpression := '';
  if Started and (TAtlasIdeBreakpoints.StoppedProcess <> nil) then
  begin
    mExpression := CursorExpression;
  end;
  if mExpression = '' then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DataCommand);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataCommandFor, [mExpression]);
  end;
end;

class function TAtlasIdeDataBreakpoint.UsedSlots: Integer;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTAAddressBreakpoint;
begin
  Result := 0;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.GetAddressBkptCount - 1 do
  begin
    mBreakpoint := mServices.GetAddressBkpt(mIndex);
    if (mBreakpoint <> nil) and mBreakpoint.Enabled and
      (mBreakpoint.GetAccessType <> TOTAAccessType.atExecute) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasIdeDataBreakpoint.PlanFor(const AExpression: string; out APlan: TAtlasDataWatchPlan): Boolean;
var
  mValue: string;
  mAddress: UInt64;
  mSize, mPointerSize: Integer;
begin
  APlan := Default(TAtlasDataWatchPlan);
  Result := False;
  if not Evaluate(TAtlasDataBreakpoint.AddressExpression(AExpression), mValue) or
    not TAtlasInstanceBreakpoint.TryParseAddress(mValue, mAddress) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataNoAddress, [AExpression, mValue]));
    Exit;
  end;
  if not Evaluate(TAtlasDataBreakpoint.SizeExpression(AExpression), mValue) or
    not TAtlasDataBreakpoint.TryParseSize(mValue, mSize) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataNoSize, [AExpression, mValue]));
    Exit;
  end;
  if not Evaluate(TAtlasDataBreakpoint.cPointerSizeExpression, mValue) or
    not TAtlasDataBreakpoint.TryParseSize(mValue, mPointerSize) then
  begin
    mPointerSize := 0;
  end;
  APlan := TAtlasDataBreakpoint.Plan(mAddress, mSize, TAtlasDataBreakpoint.MaxLength(mPointerSize));
  Result := APlan.Length > 0;
end;

class function TAtlasIdeDataBreakpoint.AcceptPlan(const AExpression: string;
  const APlan: TAtlasDataWatchPlan): Boolean;
begin
  Result := not APlan.Partial or (MessageDlg(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataPartialQuestion,
    [AExpression, APlan.Size, APlan.Length]), mtConfirmation, [mbYes, mbNo], 0) = mrYes);
end;

class function TAtlasIdeDataBreakpoint.CreateBreakpoint(const APlan: TAtlasDataWatchPlan): IOTABreakpoint;
var
  mServices: IOTADebuggerServices;
  mAddress: TOTAAddress;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mAddress := APlan.Address;
  try
    Result := mServices.NewAddressBreakpoint(mAddress, LongWord(APlan.Length), TOTAAccessType.atWrite,
      TAtlasIdeBreakpoints.StoppedProcess);
  except
    on Exception do
      Result := nil;
  end;
end;

class function TAtlasIdeDataBreakpoint.TargetExpression(out AExpression: string): Boolean;
begin
  AExpression := '';
  Result := False;
  if not Started then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.DataOff));
  end
  else if TAtlasIdeBreakpoints.StoppedProcess = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.DataNotStopped));
  end
  else
  begin
    AExpression := CursorExpression;
    if AExpression = '' then
    begin
      Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.DataNoExpression));
    end
    else if TAtlasDataBreakpoint.FreeSlots(UsedSlots) = 0 then
    begin
      Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataNoSlot, [TAtlasDataBreakpoint.cSlots]));
    end
    else
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasIdeDataBreakpoint.NewWatch(const AExpression: string; const APlan: TAtlasDataWatchPlan): TWatch;
var
  mValue: string;
begin
  Result := Default(TWatch);
  Result.Expression := AExpression;
  Result.Plan := APlan;
  if not Evaluate(AExpression, mValue) then
  begin
    mValue := '';
  end;
  Result.Value := mValue;
  if not TAtlasIdeDebugEvaluator.ReadMemory(APlan.Address, APlan.Length, Result.Bytes) then
  begin
    Result.Bytes := nil;
  end;
  Result.Kind := TAtlasDataBreakpoint.KindOf(mValue, Result.Bytes, APlan.Partial);
end;

class procedure TAtlasIdeDataBreakpoint.WatchAtCursor;
var
  mExpression: string;
  mPlan: TAtlasDataWatchPlan;
  mWatch: TWatch;
begin
  if not TargetExpression(mExpression) or not PlanFor(mExpression, mPlan) or not AcceptPlan(mExpression, mPlan) then
  begin
    Exit;
  end;
  mWatch := NewWatch(mExpression, mPlan);
  mWatch.Breakpoint := CreateBreakpoint(mPlan);
  if mWatch.Breakpoint = nil then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataRejected, [mExpression,
      TAtlasDataBreakpoint.cSlots]));
    Exit;
  end;
  FWatches.Add(mWatch);
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataSet, [mExpression, mPlan.Length,
    TAtlasInstanceBreakpoint.AddressText(mPlan.Address), mWatch.Value]));
  if mWatch.Kind = TAtlasDataValueKind.Text then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.DataTextHint));
  end;
  Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.DataSessionHint));
end;

class function TAtlasIdeDataBreakpoint.NewValue(const AWatch: TWatch; const ABytes: TBytes): string;
begin
  Result := TAtlasDataBreakpoint.ValueText(AWatch.Kind, ABytes);
  if (AWatch.Kind = TAtlasDataValueKind.Text) and
    not Evaluate(TAtlasDataBreakpoint.TextExpression(AWatch.Plan.Address), Result) then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.DataReassigned);
  end;
end;

class procedure TAtlasIdeDataBreakpoint.CheckChanges;
var
  mIndex: Integer;
  mWatch: TWatch;
  mBytes: TBytes;
  mValue, mLast: string;
begin
  if FWatches = nil then
  begin
    Exit;
  end;
  mLast := '';
  for mIndex := 0 to FWatches.Count - 1 do
  begin
    mWatch := FWatches[mIndex];
    if not TAtlasIdeDebugEvaluator.ReadMemory(mWatch.Plan.Address, mWatch.Plan.Length, mBytes) or
      not TAtlasDataBreakpoint.Changed(mWatch.Bytes, mBytes) then
    begin
      Continue;
    end;
    mValue := NewValue(mWatch, mBytes);
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataChanged, [mWatch.Expression, mWatch.Value, mValue]));
    mLast := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataStatus, [mWatch.Expression, mWatch.Value, mValue]);
    mWatch.Bytes := mBytes;
    mWatch.Value := mValue;
    FWatches[mIndex] := mWatch;
  end;
  if mLast <> '' then
  begin
    TAtlasIdeHost.SetStatusExtra(cStatusId, mLast);
  end;
end;

class procedure TAtlasIdeDataBreakpoint.ClearStatus;
begin
  TAtlasIdeHost.SetStatusExtra(cStatusId, '');
end;

class procedure TAtlasIdeDataBreakpoint.RemoveWatches(AReport: Boolean);
var
  mBreakpoints: TArray<IOTABreakpoint>;
  mIndex: Integer;
begin
  ClearStatus;
  if (FWatches = nil) or (FWatches.Count = 0) then
  begin
    Exit;
  end;
  SetLength(mBreakpoints, FWatches.Count);
  for mIndex := 0 to FWatches.Count - 1 do
  begin
    mBreakpoints[mIndex] := FWatches[mIndex].Breakpoint;
  end;
  FWatches.Clear;
  if AReport then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DataRemoved, [Length(mBreakpoints)]));
  end;
  TAtlasIdeBreakpoints.RemoveAll(mBreakpoints);
end;

end.
