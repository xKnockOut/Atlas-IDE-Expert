unit Atlas.Common.Editing.ComponentCommands;

// Schnellbefehle für eigene Komponenten (#320) im Rahmen aus #293:
//   /notify OnChange[: Typ]  Ereignisfeld, Property und DoChange-Methode
//   /changed Farbe           Setter der Property nach dem Muster "if F <> Value then
//                            begin F := Value; Changed; end" (Invalidate bei Controls)
//   /loaded                  Loaded mit inherited (nur TComponent-Nachfahren)
//   /notification [FFeld]    Notification für Komponentenfelder und FreeNotification im Setter
// Ob eine Klasse von TComponent bzw. TControl abstammt, ergibt sich aus der
// Vorfahrenkette in der Unit und im Symbolindex.

interface

uses
  Atlas.Common.Editing.SlashCommands;

/// <summary>Trägt /notify, /changed, /loaded und /notification in ARegistry ein.</summary>
procedure RegisterComponentCommands(ARegistry: TSlashCommandRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Common.Editing.CommandSource;

type
  TKinds = set of TIndexSymbolKind;

const
  ComponentRoots: array[0..13] of string = ('TComponent', 'TControl', 'TWinControl', 'TCustomControl',
    'TGraphicControl', 'TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule', 'TDataSet', 'TCustomPanel',
    'TPanel', 'TCustomConnection');
  ControlRoots: array[0..9] of string = ('TControl', 'TWinControl', 'TCustomControl', 'TGraphicControl', 'TForm',
    'TCustomForm', 'TFrame', 'TCustomFrame', 'TCustomPanel', 'TPanel');

/// <summary>Vorfahren von AClassName, soweit Unit und Index sie kennen; der erste ist der direkte.</summary>
function Ancestors(ASource: TCommandSource; const AIndex: ISymbolIndex; const AClassName: string): TArray<string>;
var
  Name, Next: string;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Depth: Integer;
  Found: Boolean;
begin
  Result := nil;
  Name := AClassName;
  for Depth := 1 to 32 do
  begin
    Next := '';
    Found := False;
    for Symbol in ASource.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and SameText(Symbol.Name, Name) and (Symbol.Container = '') then
      begin
        Found := True;
        if Length(Symbol.Ancestors) > 0 then
          Next := Symbol.Ancestors[0];
        Break;
      end;
    if not Found and (AIndex <> nil) then
      for Location in AIndex.FindSymbols(Name) do
        if Location.Symbol.Kind = TIndexSymbolKind.ClassType then
        begin
          if Length(Location.Symbol.Ancestors) > 0 then
            Next := Location.Symbol.Ancestors[0];
          Break;
        end;
    if (Next = '') or (IndexText(Next, Result) >= 0) then
      Exit;
    Result := Result + [Next];
    Name := Next;
  end;
end;

function DescendsFrom(const AChain: TArray<string>; const ARoots: array of string): Boolean;
var
  Name: string;
begin
  for Name in AChain do
    if MatchText(Name, ARoots) then
      Exit(True);
  Result := False;
end;

/// <summary>Mitglied AName der Klasse AClass in der Unit (Feld, Property, Methode).</summary>
function FindMember(ASource: TCommandSource; const AClass: TIndexSymbol; const AName: string;
  AKinds: TKinds; out AMember: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind in AKinds) and SameText(Symbol.Name, AName) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.Range.StartPos.Line >= AClass.Range.StartPos.Line) and
      (Symbol.Range.EndPos.Line <= AClass.Range.EndPos.Line) then
    begin
      AMember := Symbol;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Rumpf TKlasse.AName in der implementation; nil ohne.</summary>
function FindBody(ASource: TCommandSource; const AClassName, AName: string): TSyntaxNode;
var
  Section: TSyntaxNode;
  Index: Integer;
begin
  Result := nil;
  Section := ASource.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  if Section = nil then
    Exit;
  for Index := 0 to Section.ChildCount - 1 do
    if (Section[Index].Kind = TSyntaxKind.RoutineDecl) and SameText(Section[Index].Name, AClassName + '.' + AName) and
      (Section[Index].FindChild(TSyntaxKind.Block) <> nil) then
      Exit(Section[Index]);
end;

/// <summary>Abschnitte vor "end" der Klasse: Feld in private (vorhandener Abschnitt oder neuer), dann AMore.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const AField: string;
  const AMore: array of string): TArray<TRuleEdit>;
var
  Line, EndLine, Index: Integer;
  Indent, Body: string;
begin
  Result := nil;
  EndLine := AClass.Range.EndPos.Line;
  Indent := ASource.Indent(EndLine);
  Body := '';
  if AField <> '' then
  begin
    Line := ASource.PrivateLine(AClass);
    if Line >= 0 then
      Result := [ASource.AfterLine(Line, ASource.Indent(Line) + '  ' + AField)]
    else
      Body := Indent + 'private' + ASource.LineBreak + Indent + '  ' + AField;
  end;
  // AMore: abwechselnd Abschnitt und Deklaration.
  Index := 0;
  while Index < High(AMore) do
  begin
    if Body <> '' then
      Body := Body + ASource.LineBreak;
    Body := Body + Indent + AMore[Index] + ASource.LineBreak + Indent + '  ' + AMore[Index + 1];
    Inc(Index, 2);
  end;
  if Body <> '' then
    Result := Result + [ASource.BeforeLine(EndLine, Body)];
end;

{ /notify }

/// <summary>Parameterliste des Ereignistyps ohne Klammern, z. B. "Sender: TObject; const AText: string".</summary>
function EventParameters(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AParameters: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Text, FileText: string;
  Open, Close: Integer;
begin
  AParameters := '';
  if SameText(ATypeName, 'TNotifyEvent') then
  begin
    AParameters := 'Sender: TObject';
    Exit(True);
  end;
  Text := '';
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, ATypeName) and (Symbol.Container = '') then
      Text := RangeText(ASource.Lines, Symbol.Range);
  if (Text = '') and (AIndex <> nil) then
    for Location in AIndex.FindSymbols(ATypeName) do
      if LoadText(Location.FileName, FileText) then
      begin
        Text := RangeText(FileText.Replace(#13#10, #10).Split([#10]), Location.Symbol.Range);
        Break;
      end;
  Open := Pos('(', Text);
  Close := LastDelimiter(')', Text);
  Result := (Text <> '') and ContainsText(Text, 'of object');
  if Result and (Open > 0) and (Close > Open) then
    AParameters := Trim(Copy(Text, Open + 1, Close - Open - 1));
end;

function ExecuteNotify(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Existing: TIndexSymbol;
  Name, TypeName, Base, Field, Method, Parameters, Own, Names, Section, LB: string;
  Groups: TArray<string>;
begin
  AEdits := nil;
  if not SplitDeclaration(AContext.Arguments, ':', Name, TypeName) then
  begin
    Name := Trim(AContext.Arguments);
    TypeName := 'TNotifyEvent';
  end;
  if not IsValidIdent(Name) or not StartsText('On', Name) or (Length(Name) < 3) then
    Exit(Fail('Erwartet wird /notify OnName[: Ereignistyp]', AReason));
  Base := Copy(Name, 3, MaxInt);
  Field := 'F' + Name;
  Method := 'Do' + Base;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/notify gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if FindMember(Source, ClassSymbol, Name, [TIndexSymbolKind.Property_], Existing) or
      FindMember(Source, ClassSymbol, Field, [TIndexSymbolKind.Field], Existing) then
      Exit(Fail(Format('%s hat schon %s', [ClassSymbol.Name, Name]), AReason));
    if not EventParameters(Source, AContext.Index, TypeName, Parameters) then
      Exit(Fail(Format('Ereignistyp %s nicht gefunden (procedure(...) of object)', [TypeName]), AReason));
    // Sender: TObject am Anfang setzt Self ein; die übrigen Parameter reicht DoX durch.
    Groups := Parameters.Split([';']);
    if (Length(Groups) > 0) and ContainsText(Groups[0], 'Sender') then
    begin
      Own := Trim(string.Join(';', Copy(Groups, 1, MaxInt)));
      Names := ParameterNames('(' + Own + ')');
      if Names <> '' then
        Names := 'Self, ' + Names
      else
        Names := 'Self';
    end
    else
    begin
      Own := Parameters;
      Names := ParameterNames('(' + Own + ')');
    end;
    if Own <> '' then
      Own := '(' + Own + ')';
    if DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ComponentRoots) then
      Section := 'published'
    else
      Section := 'public';
    LB := Source.LineBreak;
    AEdits := AddToClass(Source, ClassSymbol, Format('%s: %s;', [Field, TypeName]),
      ['protected', Format('procedure %s%s; virtual;', [Method, Own]), Section,
      Format('property %s: %s read %s write %s;', [Name, TypeName, Field, Field])]);
    AEdits := AEdits + [Source.AddBody(ClassSymbol.Name, Format('procedure %s.%s%s;', [ClassSymbol.Name, Method,
      Own]) + LB + 'begin' + LB + Format('  if Assigned(%s) then', [Field]) + LB + Format('    %s(%s);',
      [Field, Names]) + LB + 'end;'), Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /changed }

/// <summary>Wort hinter AKeyword (read/write) in der Property-Deklaration; '' ohne.</summary>
function Accessor(const ADeclaration, AKeyword: string): string;
var
  Words: TArray<string>;
  Index: Integer;
begin
  Words := ADeclaration.Replace(';', ' ').Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for Index := 0 to High(Words) - 1 do
    if SameText(Words[Index], AKeyword) then
      Exit(Words[Index + 1]);
  Result := '';
end;

function ExecuteChanged(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Prop, Member: TIndexSymbol;
  Name, Declaration, Field, Writer, Call, Value, Indent, LB, Body, NewDeclaration: string;
  Routine, Block: TSyntaxNode;
  Signature: string;
begin
  AEdits := nil;
  Name := Trim(AContext.Arguments);
  if not IsValidIdent(Name) then
    Exit(Fail('Erwartet wird /changed Property', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/changed gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if not FindMember(Source, ClassSymbol, Name, [TIndexSymbolKind.Property_], Prop) then
      Exit(Fail(Format('%s hat keine Property %s', [ClassSymbol.Name, Name]), AReason));
    Declaration := RangeText(Source.Lines, Prop.Range);
    Field := Accessor(Declaration, 'read');
    if Field = '' then
      Field := 'F' + Name;
    Writer := Accessor(Declaration, 'write');
    // Benachrichtigung: Invalidate bei Controls, sonst eine vorhandene Changed- bzw. DoChange-Methode.
    if DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ControlRoots) then
      Call := 'Invalidate'
    else if FindMember(Source, ClassSymbol, 'DoChange', [TIndexSymbolKind.Method], Member) and
      not FindMember(Source, ClassSymbol, 'Changed', [TIndexSymbolKind.Method], Member) then
      Call := 'DoChange'
    else
      Call := 'Changed';
    LB := Source.LineBreak;
    Value := 'Value';
    Routine := nil;
    if (Writer <> '') and not SameText(Writer, Field) then
    begin
      Routine := FindBody(Source, ClassSymbol.Name, Writer);
      if Routine = nil then
        Exit(Fail(Format('Rumpf von %s.%s nicht gefunden', [ClassSymbol.Name, Writer]), AReason));
      Signature := RoutineSignature(Source.Lines[Routine.StartPos.Line]);
      if ParameterNames(Signature) <> '' then
        Value := ParameterNames(Signature);
    end;
    Body := 'begin' + LB + Format('  if %s <> %s then', [Field, Value]) + LB + '  begin' + LB +
      Format('    %s := %s;', [Field, Value]) + LB + Format('    %s;', [Call]) + LB + '  end;' + LB + 'end;';
    if Routine <> nil then
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      AEdits := [TRuleEdit.Create(TTextRange.Create(Block.StartPos.Line, 0, Block.EndPos.Line + 1, 0), Body + LB),
        Source.RemoveCommand];
      Exit(True);
    end;
    // Ohne Setter: anlegen wie /prop und die Property darauf umstellen.
    Writer := 'Set' + Name;
    if (Prop.TypeName = '') then
      Exit(Fail(Format('Typ von %s nicht erkannt', [Name]), AReason));
    if Pos(' write ', Declaration) > 0 then
      NewDeclaration := StringReplace(Declaration, ' write ' + Accessor(Declaration, 'write'), ' write ' + Writer,
        [rfIgnoreCase])
    else
      NewDeclaration := StringReplace(Declaration, ';', ' write ' + Writer + ';', []);
    if Prop.Range.StartPos.Line <> Prop.Range.EndPos.Line then
      Exit(Fail('Mehrzeilige Property-Deklaration: Setter bitte mit /prop anlegen', AReason));
    Indent := Source.Indent(ClassSymbol.Range.EndPos.Line);
    AEdits := [TRuleEdit.Create(Prop.Range, NewDeclaration),
      Source.BeforeLine(ClassSymbol.Range.EndPos.Line, Indent + 'private' + LB + Indent + '  ' +
      Format('procedure %s(const Value: %s);', [Writer, Prop.TypeName])),
      Source.AddBody(ClassSymbol.Name, Format('procedure %s.%s(const Value: %s);', [ClassSymbol.Name, Writer,
      Prop.TypeName]) + LB + Body), Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /loaded }

function ExecuteLoaded(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Member: TIndexSymbol;
  LB: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/loaded gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if not DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ComponentRoots) then
      Exit(Fail(Format('%s stammt nicht von TComponent ab; Loaded gibt es dort nicht', [ClassSymbol.Name]),
        AReason));
    if FindMember(Source, ClassSymbol, 'Loaded', [TIndexSymbolKind.Method], Member) then
      Exit(Fail(Format('%s hat schon Loaded', [ClassSymbol.Name]), AReason));
    LB := Source.LineBreak;
    AEdits := AddToClass(Source, ClassSymbol, '', ['protected', 'procedure Loaded; override;']) +
      [Source.AddBody(ClassSymbol.Name, Format('procedure %s.Loaded;', [ClassSymbol.Name]) + LB + 'begin' + LB +
      '  inherited Loaded;' + LB + 'end;'), Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /notification }

function IsComponentType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ComponentRoots) or
    DescendsFrom(Ancestors(ASource, AIndex, ATypeName), ComponentRoots);
end;

function ExecuteNotification(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Symbol, Prop: TIndexSymbol;
  Fields, Lines_: TArray<string>;
  Field, LB, BodyText, Setter, Declaration, Condition: string;
  Routine, Block: TSyntaxNode;
  Index: Integer;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/notification gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    if not DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ComponentRoots) then
      Exit(Fail(Format('%s stammt nicht von TComponent ab', [ClassSymbol.Name]), AReason));
    Fields := nil;
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
        ((AContext.Arguments = '') and IsComponentType(Source, AContext.Index, Symbol.TypeName) or
        SameText(Symbol.Name, Trim(AContext.Arguments))) then
        Fields := Fields + [Symbol.Name];
    if Fields = nil then
      Exit(Fail(IfThen(AContext.Arguments = '', 'Keine Felder mit Komponententyp',
        Format('%s hat kein Feld %s', [ClassSymbol.Name, AContext.Arguments])), AReason));
    LB := Source.LineBreak;
    Routine := FindBody(Source, ClassSymbol.Name, 'Notification');
    BodyText := '';
    if Routine <> nil then
      for Index := Routine.StartPos.Line to Routine.EndPos.Line do
        BodyText := BodyText + Source.Lines[Index] + #10;
    // Vorhandene Bedingungen nicht verdoppeln.
    Lines_ := nil;
    for Field in Fields do
    begin
      Condition := Format('(AComponent = %s)', [Field]);
      if not ContainsText(BodyText, Condition) then
        Lines_ := Lines_ + [Format('  if (Operation = opRemove) and %s then', [Condition]),
          Format('    %s := nil;', [Field])];
    end;
    if Lines_ = nil then
      Exit(Fail('Notification behandelt diese Felder schon', AReason));
    if Routine <> nil then
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      AEdits := [Source.BeforeLine(Block.EndPos.Line, string.Join(LB, Lines_))];
    end
    else
      AEdits := AddToClass(Source, ClassSymbol, '', ['protected',
        'procedure Notification(AComponent: TComponent; Operation: TOperation); override;']) +
        [Source.AddBody(ClassSymbol.Name, Format('procedure %s.Notification(AComponent: TComponent; ' +
        'Operation: TOperation);', [ClassSymbol.Name]) + LB + 'begin' + LB +
        '  inherited Notification(AComponent, Operation);' + LB + string.Join(LB, Lines_) + LB + 'end;')];
    // Setter der zugehörigen Properties melden sich beim neuen Wert an und beim alten ab.
    for Symbol in Source.UnitIndex.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.Property_) and SameText(Symbol.Container, ClassSymbol.Name) then
      begin
        Prop := Symbol;
        Declaration := RangeText(Source.Lines, Prop.Range);
        Field := Accessor(Declaration, 'read');
        Setter := Accessor(Declaration, 'write');
        if (IndexText(Field, Fields) < 0) or (Setter = '') or SameText(Setter, Field) then
          Continue;
        Routine := FindBody(Source, ClassSymbol.Name, Setter);
        if Routine = nil then
          Continue;
        BodyText := '';
        for Index := Routine.StartPos.Line to Routine.EndPos.Line do
          BodyText := BodyText + Source.Lines[Index] + #10;
        if ContainsText(BodyText, 'FreeNotification') then
          Continue;
        Block := Routine.FindChild(TSyntaxKind.Block);
        AEdits := AEdits + [Source.AfterLine(Block.StartPos.Line, Format('  if %s <> nil then', [Field]) + LB +
          Format('    %s.RemoveFreeNotification(Self);', [Field])), Source.BeforeLine(Block.EndPos.Line,
          Format('  if %s <> nil then', [Field]) + LB + Format('    %s.FreeNotification(Self);', [Field]))];
      end;
    AEdits := AEdits + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterComponentCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('notify', 'Ereignis mit Feld, Property und Do-Methode', '/notify OnChange',
    ExecuteNotify));
  ARegistry.Register(Command('changed', 'Setter mit Änderungsprüfung und Benachrichtigung', '/changed Farbe',
    ExecuteChanged));
  ARegistry.Register(Command('loaded', 'Loaded überschreiben', '/loaded', ExecuteLoaded));
  ARegistry.Register(Command('notification', 'Notification für Komponentenfelder', '/notification FDataSource',
    ExecuteNotification));
end;

end.
