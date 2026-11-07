unit Atlas.Common.Dfm.EventHandlers;

// Beim nächsten Ereignis anhalten (#856), Teil ohne Index: welche Methoden
// einer Unit als Ereignis-Handler zugewiesen sind, mit Komponente, Ereignis
// und der Zeile des begin im Rumpf.
// - Aus den Formulardateien der Unit (.dfm/.fmx): jede Ereignis-Eigenschaft
//   (OnClick = btnSpeichernClick, BeforePost = TabelleBeforePost) über
//   TFormModel; Aktionen sind Objekte wie andere (TAction.OnExecute).
// - Aus dem Code: Zuweisungen Komponente.OnXyz := Methode bzw.
//   OnXyz := Methode (am Formular selbst) und Self.Methode als Wert.
//   Container ist die Klasse der umgebenden Methode. Anonyme Methoden,
//   nil und Methoden fremder Objekte (Form1.Tick) zählen nicht.
// Den Rumpf sucht die Unit selbst (Klasse.Methode mit begin); fehlt er
// (geerbtes Formular, Handler im Vorfahren), bleibt Line -1, und die
// Server-Seite (Atlas.Common.Lsp.EventHandlers) sucht über den Index weiter.
// Bei Timern steht Interval aus der Formulardatei dabei (-1 = Vorgabe 1000).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  TEventHandlerOrigin = (Form, Code);
  {$SCOPEDENUMS OFF}

  TEventHandler = record
    Origin: TEventHandlerOrigin;
    /// <summary>Klasse des Formulars bzw. der Methode mit der Zuweisung.</summary>
    FormClass: string;
    /// <summary>Komponentenname aus der Formulardatei bzw. der Ausdruck vor dem Punkt (FTimer); beim Formular
    /// selbst dessen Name bzw. ''.</summary>
    Component: string;
    /// <summary>Klasse der Komponente (TButton); '' bei Zuweisungen im Code.</summary>
    ComponentClass: string;
    /// <summary>OnClick, BeforePost …</summary>
    Event: string;
    Handler: string;
    /// <summary>Klasse, deren Methode der Handler ist.</summary>
    Container: string;
    /// <summary>Unit mit dem Rumpf; '' solange unbekannt.</summary>
    FileName: string;
    /// <summary>Zeile (ab 0) des begin im Rumpf; -1 solange unbekannt.</summary>
    Line: Integer;
    /// <summary>Zeile (ab 0) der ersten Anweisung, bei leerem Rumpf des end; dort sind die Parameter (Sender)
    /// schon auswertbar. -1 solange unbekannt.</summary>
    BodyLine: Integer;
    /// <summary>Formulardatei bzw. Unit mit der Zuweisung und deren Zeile (ab 0).</summary>
    SourceFile: string;
    SourceLine: Integer;
    /// <summary>Interval der Komponente in ms; -1 ohne Angabe.</summary>
    Interval: Integer;
  end;

  /// <summary>Rumpf einer Methode: Zeile des begin und der ersten Anweisung (bzw. des end).</summary>
  TEventHandlerBody = record
    Line: Integer;
    BodyLine: Integer;
  end;

  TEventHandlerForm = record
    FileName: string;
    Text: string;
  end;

  TEventHandlers = class
  public
    /// <summary>Handler der Unit AUnitFile aus ihren Formulardateien AForms und ihrem Code.</summary>
    class function Collect(const AUnitFile, AUnitText: string;
      const AForms: TArray<TEventHandlerForm>): TArray<TEventHandler>; static;
    /// <summary>Handler aus einer Formulardatei; Rümpfe aus ABodies (Klasse.Methode klein → begin-Zeile).</summary>
    class function FromForm(const AForm: TEventHandlerForm; const AUnitFile: string;
      ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>; static;
    /// <summary>Trägt den Rumpf aus ABodies ein; False ohne.</summary>
    class function Resolve(var AHandler: TEventHandler; const AFileName: string;
      ABodies: TDictionary<string, TEventHandlerBody>): Boolean; static;
    /// <summary>Zuweisungen von Handlern im Code.</summary>
    class function FromCode(ATree: TSyntaxTree; const AUnitFile, AUnitText: string;
      ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>; static;
    /// <summary>Rümpfe der Methoden: Klasse.Methode (klein) → Zeilen des Rumpfs.</summary>
    class procedure Bodies(ATree: TSyntaxTree; ABodies: TDictionary<string, TEventHandlerBody>); static;
    /// <summary>Lohnt das Lesen des Codes? Nur mit einer Zuweisung an On…, Before… oder After….</summary>
    class function MayAssignHandlers(const AText: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.StrUtils,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Pascal.Parser;

/// <summary>Klasse aus Klasse.Methode (alles vor dem letzten Punkt); '' ohne Punkt.</summary>
function ContainerOf(const AQualified: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AQualified);
  if mDot > 1 then
  begin
    Result := Copy(AQualified, 1, mDot - 1);
  end
  else
  begin
    Result := '';
  end;
end;

function IntervalOf(AObject: TDfmObject): Integer;
var
  mItem: TDfmProperty;
begin
  Result := -1;
  for mItem in AObject.Properties do
  begin
    if SameText(mItem.Name, 'Interval') then
    begin
      Exit(StrToIntDef(Trim(mItem.Value), -1));
    end;
  end;
end;

{ TEventHandlers }

class function TEventHandlers.MayAssignHandlers(const AText: string): Boolean;
var
  mPosition, mIndex: Integer;
begin
  // Schneller Vorfilter ohne Parser: ":=" nach einem Bezeichner, der mit On/Before/After beginnt.
  Result := False;
  mPosition := Pos(':=', AText);
  while mPosition > 0 do
  begin
    mIndex := mPosition - 1;
    while (mIndex > 0) and CharInSet(AText[mIndex], [' ', #9]) do
    begin
      Dec(mIndex);
    end;
    while (mIndex > 0) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    begin
      Dec(mIndex);
    end;
    if TDfmProperty.IsEventName(Copy(AText, mIndex + 1, mPosition - mIndex - 1).Trim) then
    begin
      Exit(True);
    end;
    mPosition := PosEx(':=', AText, mPosition + 2);
  end;
end;

class procedure TEventHandlers.Bodies(ATree: TSyntaxTree; ABodies: TDictionary<string, TEventHandlerBody>);
begin
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Block: TSyntaxNode;
      Body: TEventHandlerBody;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', ANode.Name) = 0) then
      begin
        Exit;
      end;
      Block := ANode.FindChild(TSyntaxKind.Block);
      if Block = nil then
      begin
        Block := ANode.FindChild(TSyntaxKind.AsmBlock);
      end;
      if Block = nil then
      begin
        Exit;
      end;
      Body.Line := Block.StartPos.Line;
      // Erste Anweisung in einer eigenen Zeile nach begin, sonst das end.
      Body.BodyLine := Block.EndPos.Line;
      if (Block.Kind = TSyntaxKind.Block) and (Block.ChildCount > 0) and
        (Block.Children[0].StartPos.Line > Block.StartPos.Line) then
      begin
        Body.BodyLine := Block.Children[0].StartPos.Line;
      end;
      ABodies.AddOrSetValue(LowerCase(ANode.Name), Body);
    end);
end;

class function TEventHandlers.Resolve(var AHandler: TEventHandler; const AFileName: string;
  ABodies: TDictionary<string, TEventHandlerBody>): Boolean;
var
  mBody: TEventHandlerBody;
begin
  Result := (ABodies <> nil) and ABodies.TryGetValue(LowerCase(AHandler.Container + '.' + AHandler.Handler), mBody);
  if not Result then
  begin
    Exit;
  end;
  AHandler.FileName := AFileName;
  AHandler.Line := mBody.Line;
  AHandler.BodyLine := mBody.BodyLine;
end;

class function TEventHandlers.FromForm(const AForm: TEventHandlerForm; const AUnitFile: string;
  ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>;
var
  mModel: TFormModel;
  mEvent: TFormEvent;
  mHandler: TEventHandler;
begin
  Result := nil;
  mModel := TFormModel.Create(AForm.Text);
  try
    for mEvent in mModel.Events do
    begin
      mHandler := Default(TEventHandler);
      mHandler.Origin := TEventHandlerOrigin.Form;
      mHandler.FormClass := mModel.FormClass;
      mHandler.Component := mEvent.Obj.Name;
      mHandler.ComponentClass := mEvent.Obj.TypeName;
      mHandler.Event := mEvent.Event.Name;
      mHandler.Handler := mEvent.Event.Value;
      mHandler.Container := mModel.FormClass;
      mHandler.Line := -1;
      mHandler.BodyLine := -1;
      mHandler.SourceFile := AForm.FileName;
      mHandler.SourceLine := mEvent.Event.NameRange.StartPos.Line;
      mHandler.Interval := IntervalOf(mEvent.Obj);
      Resolve(mHandler, AUnitFile, ABodies);
      Result := Result + [mHandler];
    end;
  finally
    mModel.Free;
  end;
end;

/// <summary>Ereignis und Komponente aus dem Ziel einer Zuweisung (Komponente.OnXyz oder OnXyz der eigenen
/// Klasse); False bei anderem Ziel.</summary>
function ReadEventTarget(ATarget: TSyntaxNode; const AUnitText: string; var AHandler: TEventHandler): Boolean;
var
  mObject: TSyntaxNode;
begin
  Result := True;
  if (ATarget.Kind = TSyntaxKind.MemberAccess) and (ATarget.ChildCount > 0) then
  begin
    AHandler.Event := ATarget.Name;
    mObject := ATarget.Children[0];
    if (mObject.EndOffset > mObject.StartOffset) and (mObject.EndOffset <= Length(AUnitText)) then
    begin
      AHandler.Component := Copy(AUnitText, mObject.StartOffset + 1, mObject.EndOffset - mObject.StartOffset);
    end;
    if SameText(AHandler.Component, 'Self') then
    begin
      AHandler.Component := '';
    end;
  end
  else if ATarget.Kind = TSyntaxKind.Identifier then
  begin
    AHandler.Event := ATarget.Name;
  end
  else
  begin
    Result := False;
  end;
  Result := Result and TDfmProperty.IsEventName(AHandler.Event);
end;

/// <summary>Wert ist Self.Methode.</summary>
function IsSelfMember(AValue: TSyntaxNode): Boolean;
begin
  Result := (AValue.Kind = TSyntaxKind.MemberAccess) and (AValue.ChildCount > 0) and
    (AValue.Children[0].Kind = TSyntaxKind.Identifier) and SameText(AValue.Children[0].Name, 'Self');
end;

/// <summary>Methode aus dem Wert einer Zuweisung (Methode oder Self.Methode); nil, anonyme Methoden und fremde
/// Objekte zählen nicht.</summary>
function ReadEventValue(AValue: TSyntaxNode; var AHandler: TEventHandler): Boolean;
begin
  Result := (AValue.Kind = TSyntaxKind.Identifier) or IsSelfMember(AValue);
  if Result then
  begin
    AHandler.Handler := AValue.Name;
    Result := (AHandler.Handler <> '') and not SameText(AHandler.Handler, 'nil');
  end;
end;

/// <summary>Methode (Klasse.Name), in der ANode steht; nil außerhalb.</summary>
function EnclosingMethod(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not ((Result.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Result.Name) > 0)) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Zuordnung aus der Zuweisung ANode (Komponente.OnXyz := Methode) in einer Methode; False sonst.
/// </summary>
function CodeHandlerOf(ANode: TSyntaxNode; const AUnitFile, AUnitText: string; out AHandler: TEventHandler): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  AHandler := Default(TEventHandler);
  AHandler.Origin := TEventHandlerOrigin.Code;
  AHandler.Line := -1;
  AHandler.BodyLine := -1;
  AHandler.Interval := -1;
  mRoutine := nil;
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount >= 2) and
    ReadEventTarget(ANode.Children[0], AUnitText, AHandler) and ReadEventValue(ANode.Children[1], AHandler);
  if Result then
  begin
    mRoutine := EnclosingMethod(ANode);
    Result := mRoutine <> nil;
  end;
  if Result then
  begin
    AHandler.Container := ContainerOf(mRoutine.Name);
    AHandler.FormClass := AHandler.Container;
    AHandler.SourceFile := AUnitFile;
    AHandler.SourceLine := ANode.StartPos.Line;
  end;
end;

class function TEventHandlers.FromCode(ATree: TSyntaxTree; const AUnitFile, AUnitText: string;
  ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>;
var
  mFound: TArray<TEventHandler>;
begin
  mFound := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit(nil);
  end;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mHandler: TEventHandler;
    begin
      Result := True;
      if CodeHandlerOf(ANode, AUnitFile, AUnitText, mHandler) then
      begin
        // Nur Methoden der eigenen Klasse: lokale Variablen mit Methodenzeigern haben keinen Rumpf hier.
        Resolve(mHandler, AUnitFile, ABodies);
        mFound := mFound + [mHandler];
      end;
    end);
  Result := mFound;
end;

class function TEventHandlers.Collect(const AUnitFile, AUnitText: string;
  const AForms: TArray<TEventHandlerForm>): TArray<TEventHandler>;
var
  mTree: TSyntaxTree;
  mBodies: TDictionary<string, TEventHandlerBody>;
  mForm: TEventHandlerForm;
begin
  Result := nil;
  if (Length(AForms) = 0) and not MayAssignHandlers(AUnitText) then
  begin
    Exit;
  end;
  mBodies := TDictionary<string, TEventHandlerBody>.Create;
  mTree := TSyntaxTreeCache.Parse(AUnitText, nil);
  try
    TEventHandlers.Bodies(mTree, mBodies);
    for mForm in AForms do
    begin
      Result := Result + FromForm(mForm, AUnitFile, mBodies);
    end;
    if MayAssignHandlers(AUnitText) then
    begin
      Result := Result + FromCode(mTree, AUnitFile, AUnitText, mBodies);
    end;
  finally
    mTree.Free;
    mBodies.Free;
  end;
end;

end.
