unit Atlas.IDE.Debug.InstanceBreakpoint;

// Haltepunkt nur für ein Objekt (#857) im Debugger der IDE:
// - „Haltepunkt nur für dieses Objekt“ (Atlas.BreakpointOnlyForObject): Im
//   angehaltenen Programm wertet Atlas „Pointer(Self)“ aus und schränkt den
//   Haltepunkt auf der Zeile der Schreibmarke darauf ein; eine vorhandene
//   Bedingung bleibt erhalten (Kern Atlas.Core.Debug.InstanceBreakpoint).
//   Dabei merkt sich Atlas die einfachen Felder des Objekts für das spätere
//   Ersetzen (nur solange die IDE läuft).
// - „Haltepunkt nur wenn …“ (Atlas.BreakpointOnlyIf): Feldwert von Self
//   wählen, Bedingung „Nr = 4711“; sie gilt auch in späteren Sitzungen.
// - Beides nur in Methoden: Die Routine an der Zeile des Haltepunkts muss ein
//   Self haben, sonst eine Meldung statt einer Bedingung.
// - Vor dem nächsten Start (IAtlasIdeDebugLaunchCheck) fragt ein Dialog nach
//   Adressbedingungen der letzten Sitzung: entfernen, durch eine
//   Feldbedingung ersetzen (Felder des gemerkten Objekts; ohne gemerkte
//   Felder wird die Adressbedingung entfernt) oder behalten. Der Start läuft
//   in jedem Fall weiter.
// Ein Teil der Feature-Tabelle (debug.instanceBreakpoints): aus = kein
// Zuhörer, Befehle unsichtbar. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Debug.Evaluate,
  Atlas.IDE.Debug.Session;

type
  TAtlasIdeInstanceBreakpoint = class
  private const
    cTimeoutMs = 2000;
  private type
    TListener = class(TAtlasIdeDebugListener, IAtlasIdeDebugLaunchCheck)
    public
      function AllowLaunch(const AProject: IOTAProject): Boolean;
    end;
  private class var
    FMessage: TProc<string>;
    FListener: IAtlasIdeDebugListener;
    /// <summary>Felder der Objekte, auf die ein Haltepunkt eingeschränkt wurde, je Adresse.</summary>
    FFields: TDictionary<UInt64, TAtlasEvalParts>;
    class procedure Report(const AText: string); static;
    /// <summary>Haltepunkt an der Zeile der Schreibmarke in einer Methode des angehaltenen Programms; False mit
    /// Meldung sonst.</summary>
    class function TargetBreakpoint(out ABreakpoint: IOTABreakpoint): Boolean; static;
    class function Evaluate(const AExpression: string; out AValue: string): Boolean; static;
    class function SelfFields: TAtlasEvalParts; static;
    class function FieldItems(const AFields: TAtlasEvalParts): TArray<string>; static;
    /// <summary>Feld wählen; '' bei Abbruch.</summary>
    class function ChooseField(const ABreakpoint: IOTABreakpoint; const AFields: TAtlasEvalParts): string; static;
    class function Place(const ABreakpoint: IOTABreakpoint): string; static;
    class function OrphanBreakpoints: TArray<IOTABreakpoint>; static;
    /// <summary>Ersatzbedingung aus den gemerkten Feldern des Objekts; '' ohne.</summary>
    class function Replacement(const ABreakpoint: IOTABreakpoint): string; static;
    class procedure ResolveOrphans; static;
  public
    /// <summary>Teil starten: Zuhörer bei der Debug-Sitzung anmelden. AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Start(const AMessage: TProc<string>); static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>Befehl Atlas.BreakpointOnlyForObject.</summary>
    class procedure RestrictToObject; static;
    /// <summary>Befehl Atlas.BreakpointOnlyIf.</summary>
    class procedure RestrictToField; static;
  end;

implementation

uses
  Atlas.Core.Debug.InstanceBreakpoint,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Debug.Breakpoints,
  Atlas.IDE.Debug.Evaluator,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.InstanceBreakpoint;

{ TAtlasIdeInstanceBreakpoint.TListener }

function TAtlasIdeInstanceBreakpoint.TListener.AllowLaunch(const AProject: IOTAProject): Boolean;
begin
  TAtlasIdeInstanceBreakpoint.ResolveOrphans;
  Result := True;
end;

{ TAtlasIdeInstanceBreakpoint }

class procedure TAtlasIdeInstanceBreakpoint.Start(const AMessage: TProc<string>);
begin
  FMessage := AMessage;
  if FFields = nil then
  begin
    FFields := TDictionary<UInt64, TAtlasEvalParts>.Create;
  end;
  if FListener = nil then
  begin
    FListener := TListener.Create;
    TAtlasIdeDebugSession.AddListener(FListener);
    TAtlasIdeDebugSession.Start;
  end;
end;

class procedure TAtlasIdeInstanceBreakpoint.Release;
begin
  if FListener <> nil then
  begin
    TAtlasIdeDebugSession.RemoveListener(FListener);
  end;
  FListener := nil;
  FMessage := nil;
  FreeAndNil(FFields);
end;

class function TAtlasIdeInstanceBreakpoint.Started: Boolean;
begin
  Result := FListener <> nil;
end;

class procedure TAtlasIdeInstanceBreakpoint.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeInstanceBreakpoint.Evaluate(const AExpression: string; out AValue: string): Boolean;
begin
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, TAtlasVisualizerEvaluation.Fields, cTimeoutMs, AValue);
end;

class function TAtlasIdeInstanceBreakpoint.Place(const ABreakpoint: IOTABreakpoint): string;
begin
  Result := ExtractFileName(ABreakpoint.FileName);
end;

class function TAtlasIdeInstanceBreakpoint.TargetBreakpoint(out ABreakpoint: IOTABreakpoint): Boolean;
var
  mView: IOTAEditView;
  mLine: Integer;
  mLines: TArray<string>;
begin
  ABreakpoint := nil;
  Result := False;
  if not Started then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceOff));
    Exit;
  end;
  if TAtlasIdeBreakpoints.StoppedProcess = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceNotStopped));
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if mView = nil then
  begin
    Exit;
  end;
  mLine := mView.CursorPos.Line - 1;
  ABreakpoint := TAtlasIdeBreakpoints.Find(mView.Buffer.FileName, mLine);
  if ABreakpoint = nil then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceNoBreakpoint, [mLine + 1]));
    Exit;
  end;
  mLines := TAtlasEditorBuffer.Text(mView.Buffer).Replace(#13#10, #10).Split([#10]);
  Result := TAtlasInstanceBreakpoint.RoutineHasSelf(mLines, mLine);
  if not Result then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceNoSelf, [mLine + 1]));
  end;
end;

class function TAtlasIdeInstanceBreakpoint.SelfFields: TAtlasEvalParts;
var
  mValue: string;
begin
  Result := nil;
  if Evaluate(TAtlasInstanceBreakpoint.cSelfExpression, mValue) then
  begin
    Result := TAtlasInstanceBreakpoint.FieldChoices(mValue);
  end;
end;

class procedure TAtlasIdeInstanceBreakpoint.RestrictToObject;
var
  mBreakpoint: IOTABreakpoint;
  mValue: string;
  mAddress: UInt64;
begin
  if not TargetBreakpoint(mBreakpoint) then
  begin
    Exit;
  end;
  if not Evaluate(TAtlasInstanceBreakpoint.cSelfAddressExpression, mValue) or
    not TAtlasInstanceBreakpoint.TryParseAddress(mValue, mAddress) then
  begin
    Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceNoAddress, [mValue]));
    Exit;
  end;
  FFields.AddOrSetValue(mAddress, SelfFields);
  mBreakpoint.Expression := TAtlasInstanceBreakpoint.RestrictToObject(mBreakpoint.Expression, mAddress,
    TAtlasInstanceStyle.Pointer);
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceRestricted, [Place(mBreakpoint),
    mBreakpoint.LineNumber, TAtlasInstanceBreakpoint.AddressText(mAddress)]));
end;

class function TAtlasIdeInstanceBreakpoint.FieldItems(const AFields: TAtlasEvalParts): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFields));
  for mIndex := 0 to High(AFields) do
  begin
    Result[mIndex] := TAtlasInstanceBreakpoint.FieldCondition(AFields[mIndex].Name, AFields[mIndex].Value);
  end;
end;

class function TAtlasIdeInstanceBreakpoint.ChooseField(const ABreakpoint: IOTABreakpoint;
  const AFields: TAtlasEvalParts): string;
var
  mItems: TArray<string>;
  mItem: Integer;
begin
  Result := '';
  mItems := FieldItems(AFields);
  if TAtlasInstanceBreakpointDialog.Ask(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceFieldTitle),
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceFieldSummary, [Place(ABreakpoint), ABreakpoint.LineNumber]),
    mItems, TArray<string>.Create(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceFieldApply),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceCancel)), 1, mItem) = 0 then
  begin
    if (mItem >= 0) and (mItem <= High(mItems)) then
    begin
      Result := mItems[mItem];
    end;
  end;
end;

class procedure TAtlasIdeInstanceBreakpoint.RestrictToField;
var
  mBreakpoint: IOTABreakpoint;
  mFields: TAtlasEvalParts;
  mCondition: string;
begin
  if not TargetBreakpoint(mBreakpoint) then
  begin
    Exit;
  end;
  mFields := SelfFields;
  if mFields = nil then
  begin
    Report(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceNoFields));
    Exit;
  end;
  mCondition := ChooseField(mBreakpoint, mFields);
  if mCondition = '' then
  begin
    Exit;
  end;
  mBreakpoint.Expression := TAtlasInstanceBreakpoint.Combine(mBreakpoint.Expression, mCondition);
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceFieldSet, [Place(mBreakpoint), mBreakpoint.LineNumber,
    mCondition]));
end;

class function TAtlasIdeInstanceBreakpoint.OrphanBreakpoints: TArray<IOTABreakpoint>;
var
  mServices: IOTADebuggerServices;
  mIndex: Integer;
  mBreakpoint: IOTASourceBreakpoint;
  mFound: TList<IOTABreakpoint>;
begin
  Result := nil;
  mServices := TAtlasIdeBreakpoints.Debugger;
  if mServices = nil then
  begin
    Exit;
  end;
  mFound := TList<IOTABreakpoint>.Create;
  try
    for mIndex := 0 to mServices.SourceBkptCount - 1 do
    begin
      mBreakpoint := mServices.SourceBkpts[mIndex];
      if (mBreakpoint <> nil) and TAtlasInstanceBreakpoint.HasAddressCondition(mBreakpoint.Expression) then
      begin
        mFound.Add(mBreakpoint);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

class function TAtlasIdeInstanceBreakpoint.Replacement(const ABreakpoint: IOTABreakpoint): string;
var
  mAddress: UInt64;
  mFields: TAtlasEvalParts;
begin
  Result := '';
  for mAddress in TAtlasInstanceBreakpoint.Addresses(ABreakpoint.Expression) do
  begin
    if (FFields <> nil) and FFields.TryGetValue(mAddress, mFields) and (mFields <> nil) then
    begin
      Exit(ChooseField(ABreakpoint, mFields));
    end;
  end;
end;

class procedure TAtlasIdeInstanceBreakpoint.ResolveOrphans;
var
  mOrphans: TArray<IOTABreakpoint>;
  mItems: TArray<string>;
  mIndex, mItem, mChoice, mReplaced: Integer;
  mField: string;
begin
  mOrphans := OrphanBreakpoints;
  if mOrphans = nil then
  begin
    Exit;
  end;
  SetLength(mItems, Length(mOrphans));
  for mIndex := 0 to High(mOrphans) do
  begin
    mItems[mIndex] := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckProblemLine,
      [Place(mOrphans[mIndex]), mOrphans[mIndex].LineNumber, mOrphans[mIndex].Expression]);
  end;
  mChoice := TAtlasInstanceBreakpointDialog.Ask(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceOrphanTitle),
    TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceOrphanSummary, [Length(mOrphans)]), mItems,
    TArray<string>.Create(TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceOrphanRemove),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceOrphanReplace),
    TAtlasDebugStrings.Text(TAtlasDebugTextId.InstanceOrphanKeep)), 2, mItem);
  if mChoice < 0 then
  begin
    Exit;
  end;
  mReplaced := 0;
  for mIndex := 0 to High(mOrphans) do
  begin
    mField := '';
    if mChoice = 1 then
    begin
      mField := Replacement(mOrphans[mIndex]);
    end;
    if mField <> '' then
    begin
      mOrphans[mIndex].Expression := TAtlasInstanceBreakpoint.ReplaceAddress(mOrphans[mIndex].Expression, mField);
      Inc(mReplaced);
    end
    else
    begin
      mOrphans[mIndex].Expression := TAtlasInstanceBreakpoint.WithoutAddress(mOrphans[mIndex].Expression);
    end;
  end;
  Report(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.InstanceOrphanDone, [Length(mOrphans) - mReplaced, mReplaced]));
end;

end.
