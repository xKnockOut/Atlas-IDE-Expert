unit Atlas.Common.Editing.ComponentCommands;

// Schnellbefehle für eigene Komponenten (#320) im Rahmen aus #293:
//   /notify OnChange[: Typ]  Ereignisfeld, Property und DoChange-Methode
//   /changed Farbe           Setter der Property nach dem Muster "if F <> Value then
//                            begin F := Value; Changed; end" (Invalidate bei Controls)
//   /loaded                  Loaded mit inherited (nur TComponent-Nachfahren)
//   /notification [FFeld]    Notification für Komponentenfelder und FreeNotification im Setter
//   /event Button1.OnClick   Handler mit der Signatur des Ereignistyps im Formular anlegen und in der
//                            DFM bzw. FMX zuweisen (#295); "/event OnCreate" für das Formular selbst
// Ob eine Klasse von TComponent bzw. TControl abstammt, ergibt sich aus der
// Vorfahrenkette in der Unit und im Symbolindex.

interface

uses
  Atlas.Common.Editing.Contract;

/// <summary>Trägt /notify, /changed, /loaded, /notification und /event über ARegister ein.</summary>
procedure RegisterComponentCommands(const ARegister: TSlashRegister);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ClassCompletion,
  Atlas.Common.Editing.ClassCommands,
  Atlas.Text.Lines,
  Atlas.Common.Editing.ClassMembers,
  Atlas.Common.Editing.CommandSource;

/// <summary>Abschnitte vor "end" der Klasse: Feld in private (vorhandener Abschnitt oder neuer), dann AMore.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const AField: string;
  const AMore: array of string): TArray<TTextEdit>;
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

/// <summary>Methodenzeigertyp ATypeName: "procedure" bzw. "function", Parameterliste ohne Klammern und
/// Ergebnistyp ('' bei Prozeduren). False ohne "of object".</summary>
function EventSignature(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AKind, AParameters, AResultType: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Text, FileText, Tail: string;
  Open, Close, OfPos: Integer;
begin
  AKind := 'procedure';
  AParameters := '';
  AResultType := '';
  if SameText(ATypeName, 'TNotifyEvent') then
  begin
    AParameters := 'Sender: TObject';
    Exit(True);
  end;
  Text := '';
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, ATypeName) and (Symbol.Container = '') then
      Text := RangeText(ASource.Lines, Symbol.Range);
  // Aus dem Index: der Kopf der Deklaration (#492), sonst der Text der Datei.
  if (Text = '') and (AIndex <> nil) then
    for Location in AIndex.FindSymbols(ATypeName) do
      if ContainsText(Location.Symbol.Signature, 'of object') then
      begin
        Text := Location.Symbol.Signature;
        Break;
      end
      else if LoadText(Location.FileName, FileText) then
      begin
        Text := RangeText(FileText.Replace(#13#10, #10).Split([#10]), Location.Symbol.Range);
        Break;
      end;
  Open := Pos('(', Text);
  Close := LastDelimiter(')', Text);
  OfPos := Pos('of object', LowerCase(Text));
  Result := (Text <> '') and (OfPos > 0);
  if not Result then
    Exit;
  if ContainsText(Copy(Text, 1, OfPos), 'function') then
    AKind := 'function';
  if (Open > 0) and (Close > Open) and (Close < OfPos) then
    AParameters := Trim(Copy(Text, Open + 1, Close - Open - 1))
  else
    Close := Pos(AKind, LowerCase(Text)) + Length(AKind) - 1;
  // Ergebnis: zwischen ")" bzw. "function" und "of object" hinter dem Doppelpunkt.
  Tail := Trim(Copy(Text, Close + 1, OfPos - Close - 1));
  if (AKind = 'function') and StartsStr(':', Tail) then
    AResultType := Trim(Copy(Tail, 2, MaxInt));
end;

/// <summary>Parameterliste des Ereignistyps ohne Klammern, z. B. "Sender: TObject; const AText: string".</summary>
function EventParameters(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AParameters: string): Boolean;
var
  Kind, ResultType: string;
begin
  Result := EventSignature(ASource, AIndex, ATypeName, Kind, AParameters, ResultType);
end;

function ExecuteNotify(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteChanged(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Prop: TIndexSymbol;
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
    // Benachrichtigung: Invalidate bei Controls, sonst eine vorhandene Changed- bzw. DoChange-Methode; der Befehl
    // heißt "changed", deshalb ohne beide Changed.
    Call := TSetterGenerator.NotifyCall(Source, AContext.Index, ClassSymbol);
    if Call = '' then
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
    Body := TSetterGenerator.Body(Field, Value, Call, LB);
    if Routine <> nil then
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      AEdits := [TTextEdit.Create(TTextRange.Create(Block.StartPos.Line, 0, Block.EndPos.Line + 1, 0), Body + LB),
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
    AEdits := [TTextEdit.Create(Prop.Range, NewDeclaration),
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

function ExecuteLoaded(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteNotification(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
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

{ /event }

/// <summary>Zeile, vor der ein Handler in den ersten (published) Abschnitt des Formulars kommt: die erste
/// Sichtbarkeitszeile, sonst das "end" der Klasse.</summary>
function HandlerLine(ASource: TCommandSource; const AClass: TIndexSymbol): Integer;
var
  Line: Integer;
  Word: string;
begin
  for Line := AClass.Range.StartPos.Line + 1 to AClass.Range.EndPos.Line - 1 do
  begin
    Word := LowerCase(Trim(ASource.Lines[Line]));
    if (Word = 'private') or (Word = 'protected') or (Word = 'public') or (Word = 'published') or
      StartsStr('strict ', Word) then
      Exit(Line);
  end;
  Result := AClass.Range.EndPos.Line;
end;

/// <summary>Objekt AName in AObject oder darunter; nil ohne.</summary>
function FindDfmObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := FindDfmObject(Child, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

/// <summary>Einrückung der Zeile ALine in ALines.</summary>
function LineIndent(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
    Result := Copy(ALines[ALine], 1, Length(ALines[ALine]) - Length(TrimLeft(ALines[ALine])));
end;

function ExecuteEvent(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
const
  Usage = 'Erwartet wird /event Button1.OnClick bzw. /event OnCreate';
var
  Source: TCommandSource;
  ClassSymbol, Symbol, Existing: TIndexSymbol;
  Own: TUnitIndex;
  Component, Event, ComponentType, Base, Handler, FileName, FormFile, FormText, Extension, Kind, Params,
    ResultType, Header, Body, Declaration, LB, Indent, NewForm, FormLB, Uri: string;
  Dot, Number, Line: Integer;
  Resolver: TNameResolver;
  TypeSymbol, EventSymbol: TResolvedSymbol;
  Document: TDfmDocument;
  Target: TDfmObject;
  FormLines: TArray<string>;
  Prop: TDfmProperty;
  Edit: TTextEdit;
  Host: ISlashHost;
  Chain: TArray<string>;
begin
  AEdits := nil;
  Dot := Pos('.', AContext.Arguments);
  if Dot > 0 then
  begin
    Component := Trim(Copy(AContext.Arguments, 1, Dot - 1));
    Event := Trim(Copy(AContext.Arguments, Dot + 1, MaxInt));
  end
  else
  begin
    Component := '';
    Event := Trim(AContext.Arguments);
  end;
  if ((Component <> '') and not IsValidIdent(Component)) or not IsValidIdent(Event) or
    not StartsText('On', Event) or (Length(Event) < 3) then
    Exit(Fail(Usage, AReason));
  if AContext.Host = nil then
    Exit(Fail('/event braucht den Editor', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/event gilt nur in einer Formularklasse oder einer ihrer Methoden', AReason));
    // Typ der Komponente: Feld der Klasse, ohne Komponente die Klasse selbst.
    ComponentType := ClassSymbol.Name;
    if Component <> '' then
    begin
      ComponentType := '';
      for Symbol in Source.UnitIndex.Symbols do
        if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, ClassSymbol.Name) and
          SameText(Symbol.Name, Component) then
          ComponentType := Symbol.TypeName;
      if ComponentType = '' then
        Exit(Fail(Format('%s hat kein Feld %s', [ClassSymbol.Name, Component]), AReason));
    end;
    FileName := '';
    if AContext.Uri <> '' then
      FileName := TDocumentUris.ToPath(AContext.Uri);
    Own := Source.UnitIndex;
    Own.FileName := FileName;
    Resolver := TNameResolver.Create(AContext.Index);
    try
      Resolver.Namespaces := AContext.Namespaces;
      if not Resolver.ResolveNameFrom(Own, ComponentType, TypeSymbol) or
        not Resolver.DeclaredMember(TypeSymbol, Event, EventSymbol) or
        (EventSymbol.SymbolKind <> TIndexSymbolKind.Property_) or (EventSymbol.TypeName = '') then
        Exit(Fail(Format('%s hat kein Ereignis %s', [ComponentType, Event]), AReason));
    finally
      Resolver.Free;
    end;
    Chain := EventSymbol.TypeName.Split(['.']);
    if not EventSignature(Source, AContext.Index, Chain[High(Chain)], Kind, Params, ResultType) then
      Exit(Fail(Format('Ereignistyp %s nicht gefunden (procedure(...) of object)', [EventSymbol.TypeName]),
        AReason));
    // Name wie in der IDE: Button1Click, für das Formular selbst FormCreate.
    if Component <> '' then
      Base := Component
    else if DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ['TDataModule']) then
      Base := 'DataModule'
    else if DescendsFrom(Ancestors(Source, AContext.Index, ClassSymbol.Name), ['TFrame']) then
      Base := 'Frame'
    else
      Base := 'Form';
    Base := Base + Copy(Event, 3, MaxInt);
    Handler := Base;
    Number := 1;
    while FindMember(Source, ClassSymbol, Handler, [TIndexSymbolKind.Method], Existing) do
    begin
      Inc(Number);
      Handler := Base + IntToStr(Number);
    end;
    // Formulardatei neben der Unit: Zuweisung eintragen.
    FormFile := '';
    for Extension in TArray<string>.Create('.dfm', '.fmx') do
      if (FormFile = '') and (FileName <> '') and AContext.Host.ReadFile(ChangeFileExt(FileName, Extension),
        FormText) then
        FormFile := ChangeFileExt(FileName, Extension);
    if FormFile = '' then
      Exit(Fail('Neben der Unit liegt keine .dfm oder .fmx', AReason));
    Document := TDfmParser.Parse(FormText);
    try
      if Document.Root = nil then
        Exit(Fail(Format('%s ist keine Text-DFM', [ExtractFileName(FormFile)]), AReason));
      if Component = '' then
        Target := Document.Root
      else
        Target := FindDfmObject(Document.Root, Component);
      if Target = nil then
        Exit(Fail(Format('%s steht nicht in %s', [Component, ExtractFileName(FormFile)]), AReason));
      for Prop in Target.Properties do
        if SameText(Prop.Name, Event) then
          Exit(Fail(Format('%s ist schon %s zugewiesen', [AContext.Arguments, Trim(Prop.Value)]), AReason));
      // Hinter die letzte Eigenschaft des Objekts, ohne Eigenschaften hinter seine Kopfzeile.
      FormLines := TTextLines.SplitLines(FormText, FormLB);
      Line := Target.Range.StartPos.Line;
      Indent := LineIndent(FormLines, Line) + '  ';
      for Prop in Target.Properties do
        if Prop.ValueRange.EndPos.Line > Line then
          Line := Prop.ValueRange.EndPos.Line;
      Insert(Indent + Event + ' = ' + Handler, FormLines, Line + 1);
      NewForm := TTextLines.JoinLines(FormLines, FormLB);
    finally
      Document.Free;
    end;
    LB := Source.LineBreak;
    Header := Kind + ' ' + Handler;
    if Params <> '' then
      Header := Header + '(' + Params + ')';
    if ResultType <> '' then
      Header := Header + ': ' + ResultType;
    Declaration := Header + ';';
    Header := Kind + ' ' + ClassSymbol.Name + '.' + Copy(Header, Length(Kind) + 2, MaxInt);
    Body := Header + ';' + LB + 'begin' + LB + LB + 'end;';
    Line := HandlerLine(Source, ClassSymbol);
    AEdits := [Source.BeforeLine(Line, Source.Indent(ClassSymbol.Range.EndPos.Line) + '  ' + Declaration)];
    if TClassCompletion.BodyEdit(Source.Tree, Source.Text, ClassSymbol.Name, Body, Edit) then
      AEdits := AEdits + [Edit]
    else
      AEdits := AEdits + [Source.AddBody(ClassSymbol.Name, Body)];
    AEdits := AEdits + [Source.RemoveCommand];
  finally
    Source.Free;
  end;
  Host := AContext.Host;
  Uri := AContext.Uri;
  AContext.Defer(
    procedure
    begin
      Host.WriteFiles(Uri, [TSlashFile.Create(FormFile, NewForm, False)], '');
    end);
  Result := True;
end;

function Command(const AName, ASummary, AExample: string; const AExecute: TSlashExecute): TSlashCommand;
begin
  Result.Name := AName;
  Result.Summary := ASummary;
  Result.Example := AExample;
  Result.Execute := AExecute;
end;

procedure RegisterComponentCommands(const ARegister: TSlashRegister);
begin
  ARegister(Command('notify', 'Ereignis mit Feld, Property und Do-Methode', '/notify OnChange',
    ExecuteNotify));
  ARegister(Command('changed', 'Setter mit Änderungsprüfung und Benachrichtigung', '/changed Farbe',
    ExecuteChanged));
  ARegister(Command('loaded', 'Loaded überschreiben', '/loaded', ExecuteLoaded));
  ARegister(Command('event', 'Ereignis-Handler anlegen und in der DFM zuweisen', '/event Button1.OnClick',
    ExecuteEvent));
  ARegister(Command('notification', 'Notification für Komponentenfelder', '/notification FDataSource',
    ExecuteNotification));
end;

end.
