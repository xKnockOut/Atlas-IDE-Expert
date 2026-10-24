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
  System.StrUtils,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Pascal.Parser;

/// <summary>Klasse aus Klasse.Methode (alles vor dem letzten Punkt); '' ohne Punkt.</summary>
function ContainerOf(const AQualified: string): string;
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AQualified);
  if Dot > 1 then
    Result := Copy(AQualified, 1, Dot - 1)
  else
    Result := '';
end;

function IntervalOf(AObject: TDfmObject): Integer;
var
  Item: TDfmProperty;
begin
  Result := -1;
  for Item in AObject.Properties do
    if SameText(Item.Name, 'Interval') then
      Exit(StrToIntDef(Trim(Item.Value), -1));
end;

{ TEventHandlers }

class function TEventHandlers.MayAssignHandlers(const AText: string): Boolean;
var
  Position, Index: Integer;
begin
  // Schneller Vorfilter ohne Parser: ":=" nach einem Bezeichner, der mit On/Before/After beginnt.
  Result := False;
  Position := Pos(':=', AText);
  while Position > 0 do
  begin
    Index := Position - 1;
    while (Index > 0) and CharInSet(AText[Index], [' ', #9]) do
      Dec(Index);
    while (Index > 0) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      Dec(Index);
    if TDfmProperty.IsEventName(Copy(AText, Index + 1, Position - Index - 1).Trim) then
      Exit(True);
    Position := PosEx(':=', AText, Position + 2);
  end;
end;

class procedure TEventHandlers.Bodies(ATree: TSyntaxTree; ABodies: TDictionary<string, TEventHandlerBody>);
begin
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Block: TSyntaxNode;
      Body: TEventHandlerBody;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', ANode.Name) = 0) then
        Exit;
      Block := ANode.FindChild(TSyntaxKind.Block);
      if Block = nil then
        Block := ANode.FindChild(TSyntaxKind.AsmBlock);
      if Block = nil then
        Exit;
      Body.Line := Block.StartPos.Line;
      // Erste Anweisung in einer eigenen Zeile nach begin, sonst das end.
      Body.BodyLine := Block.EndPos.Line;
      if (Block.Kind = TSyntaxKind.Block) and (Block.ChildCount > 0) and
        (Block.Children[0].StartPos.Line > Block.StartPos.Line) then
        Body.BodyLine := Block.Children[0].StartPos.Line;
      ABodies.AddOrSetValue(LowerCase(ANode.Name), Body);
    end);
end;

class function TEventHandlers.Resolve(var AHandler: TEventHandler; const AFileName: string;
  ABodies: TDictionary<string, TEventHandlerBody>): Boolean;
var
  Body: TEventHandlerBody;
begin
  Result := (ABodies <> nil) and ABodies.TryGetValue(LowerCase(AHandler.Container + '.' + AHandler.Handler), Body);
  if not Result then
    Exit;
  AHandler.FileName := AFileName;
  AHandler.Line := Body.Line;
  AHandler.BodyLine := Body.BodyLine;
end;

class function TEventHandlers.FromForm(const AForm: TEventHandlerForm; const AUnitFile: string;
  ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>;
var
  Model: TFormModel;
  Event: TFormEvent;
  Handler: TEventHandler;
begin
  Result := nil;
  Model := TFormModel.Create(AForm.Text);
  try
    for Event in Model.Events do
    begin
      Handler := Default(TEventHandler);
      Handler.Origin := TEventHandlerOrigin.Form;
      Handler.FormClass := Model.FormClass;
      Handler.Component := Event.Obj.Name;
      Handler.ComponentClass := Event.Obj.TypeName;
      Handler.Event := Event.Event.Name;
      Handler.Handler := Event.Event.Value;
      Handler.Container := Model.FormClass;
      Handler.Line := -1;
      Handler.BodyLine := -1;
      Handler.SourceFile := AForm.FileName;
      Handler.SourceLine := Event.Event.NameRange.StartPos.Line;
      Handler.Interval := IntervalOf(Event.Obj);
      Resolve(Handler, AUnitFile, ABodies);
      Result := Result + [Handler];
    end;
  finally
    Model.Free;
  end;
end;

class function TEventHandlers.FromCode(ATree: TSyntaxTree; const AUnitFile, AUnitText: string;
  ABodies: TDictionary<string, TEventHandlerBody>): TArray<TEventHandler>;
var
  Found: TArray<TEventHandler>;
begin
  Found := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(nil);
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Target, Value, Routine: TSyntaxNode;
      Handler: TEventHandler;
    begin
      Result := True;
      if (ANode.Kind <> TSyntaxKind.AssignStatement) or (ANode.ChildCount < 2) then
        Exit;
      Target := ANode.Children[0];
      Value := ANode.Children[1];
      Handler := Default(TEventHandler);
      Handler.Origin := TEventHandlerOrigin.Code;
      Handler.Line := -1;
      Handler.BodyLine := -1;
      Handler.Interval := -1;
      // Ziel: Komponente.OnXyz oder OnXyz (Eigenschaft der eigenen Klasse).
      if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount > 0) then
      begin
        Handler.Event := Target.Name;
        if (Target.Children[0].EndOffset > Target.Children[0].StartOffset) and
          (Target.Children[0].EndOffset <= Length(AUnitText)) then
          Handler.Component := Copy(AUnitText, Target.Children[0].StartOffset + 1,
            Target.Children[0].EndOffset - Target.Children[0].StartOffset);
        if SameText(Handler.Component, 'Self') then
          Handler.Component := '';
      end
      else if Target.Kind = TSyntaxKind.Identifier then
        Handler.Event := Target.Name
      else
        Exit;
      if not TDfmProperty.IsEventName(Handler.Event) then
        Exit;
      // Wert: Methode oder Self.Methode; nil, anonyme Methoden und fremde Objekte zählen nicht.
      if Value.Kind = TSyntaxKind.Identifier then
        Handler.Handler := Value.Name
      else if (Value.Kind = TSyntaxKind.MemberAccess) and (Value.ChildCount > 0) and
        (Value.Children[0].Kind = TSyntaxKind.Identifier) and SameText(Value.Children[0].Name, 'Self') then
        Handler.Handler := Value.Name
      else
        Exit;
      if (Handler.Handler = '') or SameText(Handler.Handler, 'nil') then
        Exit;
      Routine := ANode.Parent;
      while (Routine <> nil) and not ((Routine.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', Routine.Name) > 0)) do
        Routine := Routine.Parent;
      if Routine = nil then
        Exit;
      Handler.Container := ContainerOf(Routine.Name);
      Handler.FormClass := Handler.Container;
      Handler.SourceFile := AUnitFile;
      Handler.SourceLine := ANode.StartPos.Line;
      // Nur Methoden der eigenen Klasse: lokale Variablen mit Methodenzeigern haben keinen Rumpf hier.
      Resolve(Handler, AUnitFile, ABodies);
      Found := Found + [Handler];
    end);
  Result := Found;
end;

class function TEventHandlers.Collect(const AUnitFile, AUnitText: string;
  const AForms: TArray<TEventHandlerForm>): TArray<TEventHandler>;
var
  Tree: TSyntaxTree;
  Bodies: TDictionary<string, TEventHandlerBody>;
  Form: TEventHandlerForm;
begin
  Result := nil;
  if (Length(AForms) = 0) and not MayAssignHandlers(AUnitText) then
    Exit;
  Bodies := TDictionary<string, TEventHandlerBody>.Create;
  Tree := TPascalParser.Parse(AUnitText, nil);
  try
    TEventHandlers.Bodies(Tree, Bodies);
    for Form in AForms do
      Result := Result + FromForm(Form, AUnitFile, Bodies);
    if MayAssignHandlers(AUnitText) then
      Result := Result + FromCode(Tree, AUnitFile, AUnitText, Bodies);
  finally
    Tree.Free;
    Bodies.Free;
  end;
end;

end.
