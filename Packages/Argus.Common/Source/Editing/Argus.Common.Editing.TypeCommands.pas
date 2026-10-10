unit Argus.Common.Editing.TypeCommands;

// Schnellbefehle, die Typen erzeugen oder umbauen (#298), im Rahmen aus #293:
//   /enum TFarbe rot, gruen [names]  Aufzählung mit Präfix (/enum! ohne), mit names auch Namenstabelle
//   /helper TTyp                     record helper bzw. class helper für TTyp
//   /singleton                       class var FInstance, Instance und class destructor
//   /encapsulate FName               Feld wird private, dazu Property Name mit Setter
//   /assign                          Assign(Source: TPersistent) für alle Felder
//   /json                            ToJson und FromJson mit System.JSON für einfache Felder

interface

uses
  Argus.Common.Editing.SlashCommands;

/// <summary>Trägt die Typbefehle in ARegistry ein.</summary>
procedure RegisterTypeCommands(ARegistry: TSlashCommandRegistry);

/// <summary>Präfix aus den Großbuchstaben des Typnamens ohne führendes T, klein: TKundenStatus wird ks.</summary>
function EnumPrefix(const ATypeName: string): string;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Index.Contract,
  Argus.Common.Editing.UsesClause,
  Argus.Common.Editing.CommandSource;

const
  // Typen, die per Zuweisung kopiert und als JSON-Wert geschrieben werden.
  StringTypes: array[0..5] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'Char', 'TCaption');
  IntegerTypes: array[0..10] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'Byte', 'Word', 'SmallInt',
    'ShortInt', 'LongInt', 'NativeInt', 'TColor');
  FloatTypes: array[0..5] of string = ('Double', 'Single', 'Extended', 'Currency', 'Real', 'TDateTime');
  // Bekannte Klassen aus RTL und VCL, die Assign können.
  PersistentTypes: array[0..10] of string = ('TStrings', 'TStringList', 'TPersistent', 'TCollection', 'TFont',
    'TBitmap', 'TPicture', 'TPen', 'TBrush', 'TIcon', 'TGraphic');

function EnumPrefix(const ATypeName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 2 to Length(ATypeName) do
    if CharInSet(ATypeName[Index], ['A'..'Z']) then
      Result := Result + LowerCase(ATypeName[Index]);
  if Result = '' then
    Result := LowerCase(Copy(ATypeName, 1, 1));
end;

function Capitalize(const AText: string): string;
begin
  Result := UpperCase(Copy(AText, 1, 1)) + Copy(AText, 2, MaxInt);
end;

/// <summary>Zeichenoffset von Zeile ALine.</summary>
function LineOffset(ASource: TCommandSource; ALine: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 0 to ALine - 1 do
    Inc(Result, Length(ASource.Lines[Index]) + Length(ASource.LineBreak));
end;

/// <summary>Steht die Befehlszeile in einem type-Abschnitt (nicht in Klasse oder Routine)?
/// False mit Grund, wenn dort kein Typ stehen darf.</summary>
function TypePlace(ASource: TCommandSource; const AName: string; out AInTypeSection: Boolean;
  out AReason: string): Boolean;
var
  ClassSymbol: TIndexSymbol;
  Previous: Integer;
  Section: TSyntaxNode;
  Index, Child: Integer;
begin
  AInTypeSection := False;
  if (ASource.RoutineAt <> nil) or ASource.ClassAt(ClassSymbol) then
    Exit(Fail('/' + AName + ' gilt nur auf Unit-Ebene', AReason));
  Previous := ASource.Line - 1;
  while (Previous >= 0) and (Trim(ASource.Lines[Previous]) = '') do
    Dec(Previous);
  // type-Abschnitt, der die vorige Zeile mit Code enthält.
  for Index := 0 to ASource.Tree.Root.ChildCount - 1 do
  begin
    Section := ASource.Tree.Root[Index];
    if Section.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      for Child := 0 to Section.ChildCount - 1 do
        if (Section[Child].Kind = TSyntaxKind.TypeSection) and (Section[Child].StartPos.Line <= Previous) and
          (Section[Child].EndPos.Line >= Previous) then
          AInTypeSection := True;
  end;
  if ASource.Tree.Root.FindChild(TSyntaxKind.InterfaceSection) = nil then
    Exit(Fail('/' + AName + ' gilt nur in einer Unit', AReason));
  Result := True;
end;

/// <summary>Beginnt die nächste Zeile mit einer weiteren Typdeklaration (Name = …)?</summary>
function TypeFollows(ASource: TCommandSource): Boolean;
var
  Next: Integer;
  Line: string;
begin
  Next := ASource.Line + 1;
  while (Next <= High(ASource.Lines)) and (Trim(ASource.Lines[Next]) = '') do
    Inc(Next);
  if Next > High(ASource.Lines) then
    Exit(False);
  Line := Trim(ASource.Lines[Next]);
  Result := (Pos('=', Line) > 1) and IsValidIdent(Trim(Copy(Line, 1, Pos('=', Line) - 1)));
end;

/// <summary>Ersetzt die Befehlszeile durch ALines; ohne type-Abschnitt kommt "type" davor.</summary>
function TypeDeclaration(ASource: TCommandSource; AInTypeSection: Boolean; const ALines: array of string): TRuleEdit;
var
  Indent, Text: string;
  Index: Integer;
begin
  Text := '';
  Indent := '  ';
  if AInTypeSection then
    Indent := ASource.Indent(ASource.Line)
  else
    Text := 'type' + ASource.LineBreak;
  for Index := 0 to High(ALines) do
    if StartsStr('#', ALines[Index]) then
      Text := Text + Copy(ALines[Index], 2, MaxInt) + ASource.LineBreak
    else
      Text := Text + Indent + ALines[Index] + ASource.LineBreak;
  Result := TRuleEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line + 1, 0), Text);
end;

{ /enum }

function ExecuteEnum(const AContext: TSlashContext; APrefixed: Boolean; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Arguments, TypeName, Prefix, Members, Names, Value: string;
  Values: TArray<string>;
  WithNames, InTypeSection: Boolean;
  Space, Index: Integer;
  Lines: TArray<string>;
begin
  AEdits := nil;
  Arguments := Trim(AContext.Arguments);
  WithNames := EndsText(' names', Arguments);
  if WithNames then
    Arguments := Trim(Copy(Arguments, 1, Length(Arguments) - 6));
  Space := Pos(' ', Arguments);
  TypeName := Copy(Arguments, 1, Space - 1);
  Values := Copy(Arguments, Space + 1, MaxInt).Split([',']);
  if (Space = 0) or not IsValidIdent(TypeName) or (Length(Values) = 0) then
    Exit(Fail('Erwartet wird /enum TTyp wert1, wert2 [names]', AReason));
  for Index := 0 to High(Values) do
  begin
    Values[Index] := Trim(Values[Index]);
    if not IsValidIdent(Values[Index]) then
      Exit(Fail('Erwartet wird /enum TTyp wert1, wert2 [names]', AReason));
  end;
  if APrefixed then
    Prefix := EnumPrefix(TypeName)
  else
    Prefix := '';
  Members := '';
  Names := '';
  for Value in Values do
  begin
    if Members <> '' then
    begin
      Members := Members + ', ';
      Names := Names + ', ';
    end;
    if APrefixed then
      Members := Members + Prefix + Capitalize(Value)
    else
      Members := Members + Value;
    Names := Names + QuotedStr(Value);
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, AContext.Name, InTypeSection, AReason) then
      Exit(False);
    Lines := [Format('%s = (%s);', [TypeName, Members])];
    if WithNames then
    begin
      Lines := Lines + ['#const', Format('#  %sNamen: array[%s] of string = (%s);',
        [Copy(TypeName, 2, MaxInt), TypeName, Names])];
      // Folgen weitere Typen, braucht es wieder "type".
      if TypeFollows(Source) then
        Lines := Lines + ['#type'];
    end;
    AEdits := [TypeDeclaration(Source, InTypeSection, Lines)];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /helper }

/// <summary>Ist ATypeName eine Klasse (in der Datei oder im Index)?</summary>
function IsClassType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;
var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, ATypeName) and (Symbol.Container = '') then
      Exit(Symbol.Kind = TIndexSymbolKind.ClassType);
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(ATypeName) do
      if Location.Symbol.Kind = TIndexSymbolKind.ClassType then
        Exit(True);
  Result := MatchText(ATypeName, PersistentTypes) or MatchText(ATypeName, ['TObject', 'TComponent', 'TControl',
    'TForm', 'TFrame', 'TList', 'TStream']);
end;

function ExecuteHelper(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeName, Kind: string;
  InTypeSection: Boolean;
begin
  AEdits := nil;
  TypeName := Trim(AContext.Arguments);
  if not IsValidIdent(TypeName, True) then
    Exit(Fail('Erwartet wird /helper TTyp', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, 'helper', InTypeSection, AReason) then
      Exit(False);
    if IsClassType(Source, AContext.Index, TypeName) then
      Kind := 'class'
    else
      Kind := 'record';
    AEdits := [TypeDeclaration(Source, InTypeSection, [
      '// Nur ein Helper je Typ ist wirksam: der zuletzt sichtbare.',
      Format('%sHelper = %s helper for %s', [StringReplace(TypeName, '.', '', [rfReplaceAll]), Kind, TypeName]),
      'public', 'end;'])];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ Klassenbefehle }

/// <summary>Deklarationen vor "end" der Klasse, Rümpfe hinter ihre letzte Methode.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const ADeclarations: array of string;
  const ABodies: string): TArray<TRuleEdit>;
var
  EndLine, Index: Integer;
  Indent, Text: string;
begin
  EndLine := AClass.Range.EndPos.Line;
  Indent := ASource.Indent(EndLine);
  Text := '';
  for Index := 0 to High(ADeclarations) do
  begin
    if Index > 0 then
      Text := Text + ASource.LineBreak;
    // Abschnittsnamen ohne, Mitglieder mit zusätzlicher Einrückung.
    if MatchText(ADeclarations[Index], ['private', 'protected', 'public', 'published', 'strict private']) then
      Text := Text + Indent + ADeclarations[Index]
    else
      Text := Text + Indent + '  ' + ADeclarations[Index];
  end;
  Result := [ASource.BeforeLine(EndLine, Text)];
  if ABodies <> '' then
    Result := Result + [ASource.AddBody(AClass.Name, ABodies)];
end;

function Join(ASource: TCommandSource; const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
  begin
    if Index > 0 then
      Result := Result + ASource.LineBreak;
    Result := Result + ALines[Index];
  end;
end;

/// <summary>Felder von AClass in der Datei.</summary>
function FieldsOf(ASource: TCommandSource; const AClass: TIndexSymbol): TArray<TIndexSymbol>;
var
  Symbol: TIndexSymbol;
begin
  Result := nil;
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Field) and SameText(Symbol.Container, AClass.Name) and
      (Symbol.TypeName <> '') then
      Result := Result + [Symbol];
end;

/// <summary>Klasse oder Record um die Befehlszeile.</summary>
function TypeAt(ASource: TCommandSource; const AName: string; out AType: TIndexSymbol;
  out AReason: string): Boolean;
var
  Symbol: TIndexSymbol;
begin
  if ASource.ClassAt(AType) then
    Exit(True);
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.RecordType) and (Symbol.Range.StartPos.Line < ASource.Line) and
      (Symbol.Range.EndPos.Line > ASource.Line) then
    begin
      AType := Symbol;
      Exit(True);
    end;
  Result := Fail('/' + AName + ' gilt nur in einer Klasse oder einer ihrer Methoden', AReason);
end;

{ /singleton }

function ExecuteSingleton(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Name: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/singleton gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Name := ClassSymbol.Name;
    AEdits := AddToClass(Source, ClassSymbol, ['private', Format('class var FInstance: %s;', [Name]), 'public',
      'class destructor Destroy;', Format('class function Instance: %s;', [Name])],
      Join(Source, [Format('class destructor %s.Destroy;', [Name]), 'begin', '  FreeAndNil(FInstance);', 'end;',
      '', Format('class function %s.Instance: %s;', [Name, Name]), 'begin', '  if FInstance = nil then',
      Format('    FInstance := %s.Create;', [Name]), '  Result := FInstance;', 'end;'])) + [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /encapsulate }

function ExecuteEncapsulate(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Field, Symbol: TIndexSymbol;
  Name, FieldName: string;
  Found: Boolean;
begin
  AEdits := nil;
  FieldName := Trim(AContext.Arguments);
  if not IsValidIdent(FieldName) then
    Exit(Fail('Erwartet wird /encapsulate FName', AReason));
  if not StartsText('F', FieldName) or (Length(FieldName) < 2) then
    Exit(Fail('/encapsulate braucht ein Feld mit F-Präfix; sonst zuerst umbenennen', AReason));
  Name := Copy(FieldName, 2, MaxInt);
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/encapsulate gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Found := False;
    for Symbol in FieldsOf(Source, ClassSymbol) do
      if SameText(Symbol.Name, FieldName) then
      begin
        Field := Symbol;
        Found := True;
      end;
    if not Found then
      Exit(Fail('Kein Feld ' + FieldName + ' in ' + ClassSymbol.Name, AReason));
    if Field.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate] then
      Exit(Fail(FieldName + ' ist schon private', AReason));
    // Nur Felder, die allein in ihrer Zeile stehen ("FName: string;").
    if (Field.Range.StartPos.Line <> Field.Range.EndPos.Line) or
      not StartsText(FieldName + ':', StringReplace(Trim(Source.Lines[Field.Range.StartPos.Line]), ' :', ':', [])) or
      (Pos(',', Source.Lines[Field.Range.StartPos.Line]) > 0) then
      Exit(Fail(FieldName + ' muss allein in seiner Zeile deklariert sein', AReason));
    AEdits := AddToClass(Source, ClassSymbol, ['private', Format('%s: %s;', [FieldName, Field.TypeName]),
      Format('procedure Set%s(const Value: %s);', [Name, Field.TypeName]), 'public',
      Format('property %s: %s read %s write Set%s;', [Name, Field.TypeName, FieldName, Name])],
      Join(Source, [Format('procedure %s.Set%s(const Value: %s);', [ClassSymbol.Name, Name, Field.TypeName]),
      'begin', Format('  %s := Value;', [FieldName]), 'end;']));
    // Alte Deklaration entfernen.
    AEdits := AEdits + [TRuleEdit.Create(TTextRange.Create(Field.Range.StartPos.Line, 0,
      Field.Range.StartPos.Line + 1, 0), ''), Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /assign }

function IsObjectField(ASource: TCommandSource; const AIndex: ISymbolIndex; const AField: TIndexSymbol): Boolean;
begin
  Result := not MatchText(AField.TypeName, StringTypes) and not MatchText(AField.TypeName, IntegerTypes) and
    not MatchText(AField.TypeName, FloatTypes) and not SameText(AField.TypeName, 'Boolean') and
    IsClassType(ASource, AIndex, AField.TypeName);
end;

function ExecuteAssign(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Field: TIndexSymbol;
  Name, Body: string;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/assign gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Name := ClassSymbol.Name;
    Body := Join(Source, [Format('procedure %s.Assign(Source: TPersistent);', [Name]), 'begin',
      Format('  if Source is %s then', [Name]), '  begin']);
    for Field in FieldsOf(Source, ClassSymbol) do
      if IsObjectField(Source, AContext.Index, Field) then
        Body := Body + Source.LineBreak + Format('    %s.Assign(%s(Source).%s);', [Field.Name, Name, Field.Name])
      else
        Body := Body + Source.LineBreak + Format('    %s := %s(Source).%s;', [Field.Name, Name, Field.Name]);
    Body := Body + Source.LineBreak + Join(Source, ['  end', '  else', '    inherited Assign(Source);', 'end;']);
    AEdits := AddToClass(Source, ClassSymbol, ['public', 'procedure Assign(Source: TPersistent); override;'], Body) +
      [Source.RemoveCommand];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /json }

function ExecuteJson(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeSymbol, Field: TIndexSymbol;
  Name, Key, ToJson, FromJson, Text: string;
  IsClass: Boolean;
  UsesEdit: TRuleEdit;
begin
  AEdits := nil;
  Source := TCommandSource.Create(AContext);
  try
    if not TypeAt(Source, 'json', TypeSymbol, AReason) then
      Exit(False);
    Name := TypeSymbol.Name;
    IsClass := TypeSymbol.Kind = TIndexSymbolKind.ClassType;
    ToJson := Join(Source, [Format('function %s.ToJson: TJSONObject;', [Name]), 'begin',
      '  Result := TJSONObject.Create;']);
    FromJson := Join(Source, [Format('class function %s.FromJson(AJson: TJSONObject): %s;', [Name, Name]), 'begin']);
    if IsClass then
      FromJson := FromJson + Source.LineBreak + Format('  Result := %s.Create;', [Name])
    else
      FromJson := FromJson + Source.LineBreak + Format('  Result := Default(%s);', [Name]);
    for Field in FieldsOf(Source, TypeSymbol) do
    begin
      Key := Field.Name;
      if StartsText('F', Key) and (Length(Key) > 1) and CharInSet(Key[2], ['A'..'Z']) then
        Key := Copy(Key, 2, MaxInt);
      if MatchText(Field.TypeName, StringTypes) then
      begin
        ToJson := ToJson + Source.LineBreak + Format('  Result.AddPair(''%s'', %s);', [Key, Field.Name]);
        FromJson := FromJson + Source.LineBreak +
          Format('  Result.%s := AJson.GetValue<string>(''%s'');', [Field.Name, Key]);
      end
      else if MatchText(Field.TypeName, IntegerTypes) or MatchText(Field.TypeName, FloatTypes) then
      begin
        ToJson := ToJson + Source.LineBreak +
          Format('  Result.AddPair(''%s'', TJSONNumber.Create(%s));', [Key, Field.Name]);
        FromJson := FromJson + Source.LineBreak +
          Format('  Result.%s := AJson.GetValue<%s>(''%s'');', [Field.Name, Field.TypeName, Key]);
      end
      else if SameText(Field.TypeName, 'Boolean') then
      begin
        ToJson := ToJson + Source.LineBreak +
          Format('  Result.AddPair(''%s'', TJSONBool.Create(%s));', [Key, Field.Name]);
        FromJson := FromJson + Source.LineBreak +
          Format('  Result.%s := AJson.GetValue<Boolean>(''%s'');', [Field.Name, Key]);
      end
      else
      begin
        ToJson := ToJson + Source.LineBreak + Format('  // TODO %s: %s', [Field.Name, Field.TypeName]);
        FromJson := FromJson + Source.LineBreak + Format('  // TODO %s: %s', [Field.Name, Field.TypeName]);
      end;
    end;
    Text := ToJson + Source.LineBreak + 'end;' + Source.LineBreak + Source.LineBreak + FromJson + Source.LineBreak +
      'end;';
    AEdits := AddToClass(Source, TypeSymbol, ['public', 'function ToJson: TJSONObject;',
      Format('class function FromJson(AJson: TJSONObject): %s; static;', [Name])], Text) + [Source.RemoveCommand];
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Source.Tree.Tokens), 'System.JSON', AContext.Namespaces) and
      TUsesClauses.AddUnit(Source.Tree.Tokens, LineOffset(Source, TypeSymbol.Range.StartPos.Line), 'System.JSON',
      Source.LineBreak, UsesEdit) then
      AEdits := AEdits + [UsesEdit];
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

procedure RegisterTypeCommands(ARegistry: TSlashCommandRegistry);
begin
  ARegistry.Register(Command('enum', 'Aufzählungstyp mit Präfix anlegen', '/enum TFarbe rot, gruen, blau names',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, True, AEdits, AReason);
    end));
  ARegistry.Register(Command('enum!', 'Aufzählungstyp ohne Präfix anlegen', '/enum! TFarbe rot, gruen',
    function(const AContext: TSlashContext; out AEdits: TArray<TRuleEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, False, AEdits, AReason);
    end));
  ARegistry.Register(Command('helper', 'Record- bzw. Class-Helper anlegen', '/helper TFarbe', ExecuteHelper));
  ARegistry.Register(Command('singleton', 'Klasse zum Singleton machen', '/singleton', ExecuteSingleton));
  ARegistry.Register(Command('encapsulate', 'Feld in Property mit Setter umwandeln', '/encapsulate FName',
    ExecuteEncapsulate));
  ARegistry.Register(Command('assign', 'Assign für alle Felder anlegen', '/assign', ExecuteAssign));
  ARegistry.Register(Command('json', 'ToJson und FromJson anlegen', '/json', ExecuteJson));
end;

end.
