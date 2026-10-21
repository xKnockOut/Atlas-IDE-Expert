unit Atlas.Common.Editing.TypeCommands;

// Schnellbefehle, die Typen erzeugen oder umbauen (#298), im Rahmen aus #293:
//   /enum TFarbe rot, gruen [names]  Aufzählung mit Präfix (/enum! ohne), mit names auch Namenstabelle
//   /helper TTyp                     record helper bzw. class helper für TTyp; bei Aufzählungen mit
//                                    Namenstabelle cNames, ToString und FromString (#875,
//                                    slashCommands.enumHelper); bei Mengen Contains, ToText, Toggle
//                                    und All (slashCommands.setHelper)
//   /singleton                       class var FInstance, Instance und class destructor
//   /encapsulate FName               Feld wird private, dazu Property Name mit Setter
//   /assign                          Assign(Source: TPersistent) für alle Felder
//   /json                            ToJson und FromJson mit System.JSON für einfache Felder
//   /thread TWorker                  TThread-Nachfahre mit Execute-Schleife (#299)
//   /exception EName [: EBasis]      Ausnahmeklasse (#304)

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.CommandSource;

/// <summary>Trägt die Typbefehle in ARegistry ein.</summary>
procedure RegisterTypeCommands(ARegistry: TSlashCommandRegistry);

/// <summary>Präfix aus den Großbuchstaben des Typnamens ohne führendes T, klein: TKundenStatus wird ks.</summary>
function EnumPrefix(const ATypeName: string): string;
/// <summary>Ist ATypeName eine Klasse (in der Datei, im Index oder bekannt aus RTL/VCL)?</summary>
function IsClassType(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string): Boolean;

// Bausteine für weitere Typbefehle (#323).

/// <summary>Steht die Befehlszeile auf Unit-Ebene? AInTypeSection, wenn sie in einem type-Abschnitt steht.</summary>
function TypePlace(ASource: TCommandSource; const AName: string; out AInTypeSection: Boolean;
  out AReason: string): Boolean;
/// <summary>Ersetzt die Befehlszeile durch ALines; ohne type-Abschnitt kommt "type" davor.</summary>
function TypeDeclaration(ASource: TCommandSource; AInTypeSection: Boolean; const ALines: array of string): TTextEdit;
/// <summary>Deklarationen vor "end" der Klasse, Rümpfe hinter ihre letzte Methode.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const ADeclarations: array of string;
  const ABodies: string): TArray<TTextEdit>;
/// <summary>ALines mit dem Zeilenende der Datei verbunden.</summary>
function Join(ASource: TCommandSource; const ALines: array of string): string;
/// <summary>Felder von AClass in der Datei.</summary>
function FieldsOf(ASource: TCommandSource; const AClass: TIndexSymbol): TArray<TIndexSymbol>;
/// <summary>Ist das Feld ein Objekt (Klassentyp, kein einfacher Typ)?</summary>
function IsObjectField(ASource: TCommandSource; const AIndex: ISymbolIndex; const AField: TIndexSymbol): Boolean;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.ClassMembers;

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
function TypeDeclaration(ASource: TCommandSource; AInTypeSection: Boolean; const ALines: array of string): TTextEdit;
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
  Result := TTextEdit.Create(TTextRange.Create(ASource.Line, 0, ASource.Line + 1, 0), Text);
end;

{ /enum }

function ExecuteEnum(const AContext: TSlashContext; APrefixed: Boolean; out AEdits: TArray<TTextEdit>;
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

/// <summary>Werte der Aufzählung ATypeName in Deklarationsreihenfolge, aus der Datei oder dem Index; False, wenn
/// ATypeName keine bekannte Aufzählung ist.</summary>
function EnumMembers(ASource: TCommandSource; const AIndex: ISymbolIndex; const ATypeName: string;
  out AValues: TArray<string>): Boolean;

  function Collect(const AUnit: TUnitIndex; const AName: string): Boolean;
  var
    Symbol: TIndexSymbol;
  begin
    for Symbol in AUnit.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.EnumMember) and SameText(Symbol.Container, AName) then
        AValues := AValues + [Symbol.Name];
    Result := AValues <> nil;
  end;

var
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
  Owner: TUnitIndex;
  Name: string;
begin
  AValues := nil;
  // Unit.TTyp: gesucht wird der einfache Name.
  Name := ATypeName;
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Symbol in ASource.UnitIndex.Symbols do
    if SameText(Symbol.Name, Name) and (Symbol.Container = '') then
      Exit((Symbol.Kind = TIndexSymbolKind.EnumType) and Collect(ASource.UnitIndex, Symbol.Name));
  if AIndex <> nil then
    for Location in AIndex.FindSymbols(Name) do
      if (Location.Symbol.Kind = TIndexSymbolKind.EnumType) and (Location.Symbol.Container = '') and
        AIndex.FindFile(Location.FileName, Owner) and Collect(Owner, Location.Symbol.Name) then
        Exit(True);
  Result := False;
end;

/// <summary>Namenstabelle cNames; lange Listen umbrechen nach Kommas.</summary>
function NamesConstant(const ATypeName: string; const AValues: TArray<string>): TArray<string>;
const
  MaxWidth = 100;
var
  Line: string;
  Index: Integer;
begin
  Result := nil;
  Line := Format('  cNames: array[%s] of string = (', [ATypeName]);
  for Index := 0 to High(AValues) do
  begin
    if (Index > 0) and (Length(Line) + Length(AValues[Index]) + 4 > MaxWidth) then
    begin
      Result := Result + [Line];
      Line := '   ';
    end;
    Line := Line + QuotedStr(AValues[Index]);
    if Index < High(AValues) then
      Line := Line + ', '
    else
      Line := Line + ');';
  end;
  Result := Result + [TrimRight(Line)];
end;

/// <summary>Elementtyp von "ATypeName = set of TElement" im Baum; False ohne oder bei namenloser Aufzählung.</summary>
function SetElementIn(ATree: TSyntaxTree; const ATypeName: string; out AElement: string): Boolean;

  function Walk(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, ATypeName) then
    begin
      Body := ANode.FindChild(TSyntaxKind.SetType);
      if (Body <> nil) and (Body.ChildCount > 0) and (Body[0].Kind = TSyntaxKind.TypeReference) and
        (Body[0].Name <> '') then
      begin
        AElement := Body[0].Name;
        Exit(True);
      end;
      Exit(False);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      if Walk(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

begin
  AElement := '';
  Result := (ATree <> nil) and (ATree.Root <> nil) and Walk(ATree.Root);
end;

/// <summary>Elementtyp der Menge ATypeName: aus der Datei, sonst aus der Unit, die der Index nennt (#875).</summary>
function SetElement(ASource: TCommandSource; const AContext: TSlashContext; const ATypeName: string;
  out AElement: string): Boolean;
var
  Name, Text: string;
  Location: TSymbolLocation;
  Tree: TSyntaxTree;
begin
  Name := ATypeName;
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  if SetElementIn(ASource.Tree, Name, AElement) then
    Exit(True);
  if (AContext.Index <> nil) and (AContext.Host <> nil) then
    for Location in AContext.Index.FindSymbols(Name) do
      if (Location.Symbol.Kind = TIndexSymbolKind.TypeAlias) and (Location.Symbol.Container = '') and
        AContext.Host.ReadFile(Location.FileName, Text) then
      begin
        Tree := TPascalParser.Parse(Text);
        try
          if SetElementIn(Tree, Name, AElement) then
            Exit(True);
        finally
          Tree.Free;
        end;
      end;
  Result := False;
end;

/// <summary>Helper für eine Menge (#875): Contains, ToText, Toggle und All.</summary>
function SetHelper(ASource: TCommandSource; const AContext: TSlashContext; AInTypeSection: Boolean;
  const ATypeName, AHelperName, AElement: string): TArray<TTextEdit>;
var
  Values, Lines, ToText, Body: TArray<string>;
begin
  Lines := ['// Nur ein Helper je Typ ist wirksam: der zuletzt sichtbare.',
    Format('%s = record helper for %s', [AHelperName, ATypeName])];
  // Mit bekannten Werten eine Namenstabelle, sonst die Namen aus der RTTI.
  if EnumMembers(ASource, AContext.Index, AElement, Values) then
  begin
    Lines := Lines + ['private const'] + NamesConstant(AElement, Values);
    ToText := ['    Result := Result + cNames[Value];'];
  end
  else
    ToText := ['    Result := Result + GetEnumName(TypeInfo(' + AElement + '), Ord(Value));'];
  Lines := Lines + ['public', Format('  function Contains(AValue: %s): Boolean;', [AElement]),
    '  function ToText: string;', Format('  procedure Toggle(AValue: %s);', [AElement]),
    Format('  class function All: %s; static;', [ATypeName]), 'end;'];
  Body := [Format('function %s.Contains(AValue: %s): Boolean;', [AHelperName, AElement]), 'begin',
    '  Result := AValue in Self;', 'end;', '',
    Format('function %s.ToText: string;', [AHelperName]), 'var', Format('  Value: %s;', [AElement]), 'begin',
    '  Result := '''';', '  for Value in Self do', '  begin', '    if Result <> '''' then',
    '      Result := Result + '', '';'];
  Body := Body + ToText;
  Body := Body + ['  end;', '  Result := ''['' + Result + '']'';', 'end;', '',
    Format('procedure %s.Toggle(AValue: %s);', [AHelperName, AElement]), 'begin', '  if AValue in Self then',
    '    Exclude(Self, AValue)', '  else', '    Include(Self, AValue);', 'end;', '',
    Format('class function %s.All: %s;', [AHelperName, ATypeName]), 'begin',
    Format('  Result := [Low(%s)..High(%s)];', [AElement, AElement]), 'end;'];
  Result := [TypeDeclaration(ASource, AInTypeSection, Lines), ASource.AddBody(AHelperName, Join(ASource, Body))];
end;

function ExecuteHelper(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeName, Kind, HelperName, Element: string;
  InTypeSection: Boolean;
  Values, Lines: TArray<string>;
  UsesEdit: TTextEdit;
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
    HelperName := StringReplace(TypeName, '.', '', [rfReplaceAll]) + 'Helper';
    // #875: Mengen bekommen Contains, ToText, Toggle und All (abschaltbar).
    if (Kind = 'record') and
      ((AContext.Host = nil) or not SameText(AContext.Host.Setting(AContext.Uri, TSlashSettings.SetHelper),
      'false')) and SetElement(Source, AContext, TypeName, Element) then
    begin
      AEdits := SetHelper(Source, AContext, InTypeSection, TypeName, HelperName, Element);
      if not EnumMembers(Source, AContext.Index, Element, Values) and
        not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Source.Tree.Tokens), 'System.TypInfo',
        AContext.Namespaces) and TUsesClauses.AddUnit(Source.Tree.Tokens, Source.Offset(Source.Line),
        'System.TypInfo', Source.LineBreak, UsesEdit) then
        AEdits := AEdits + [UsesEdit];
      Exit(True);
    end;
    // #875: Aufzählungen bekommen Namen, ToString und FromString (abschaltbar).
    if (Kind = 'record') and
      ((AContext.Host = nil) or not SameText(AContext.Host.Setting(AContext.Uri, TSlashSettings.EnumHelper),
      'false')) and EnumMembers(Source, AContext.Index, TypeName, Values) then
    begin
      Lines := ['// Nur ein Helper je Typ ist wirksam: der zuletzt sichtbare.',
        Format('%s = record helper for %s', [HelperName, TypeName]), 'private const'];
      Lines := Lines + NamesConstant(TypeName, Values);
      Lines := Lines + ['public', '  function ToString: string;',
        Format('  class function FromString(const AValue: string): %s; static;', [TypeName]), 'end;'];
      AEdits := [TypeDeclaration(Source, InTypeSection, Lines),
        Source.AddBody(HelperName, Join(Source, [
        Format('function %s.ToString: string;', [HelperName]), 'begin', '  Result := cNames[Self];', 'end;', '',
        Format('class function %s.FromString(const AValue: string): %s;', [HelperName, TypeName]), 'var',
        Format('  Value: %s;', [TypeName]), 'begin', Format('  for Value := Low(%s) to High(%s) do', [TypeName,
        TypeName]), '    if SameText(cNames[Value], AValue) then', '      Exit(Value);',
        Format('  raise EArgumentException.CreateFmt(''Unbekannter Wert "%%s" für %s'', [AValue]);', [TypeName]),
        'end;']))];
      if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Source.Tree.Tokens), 'System.SysUtils',
        AContext.Namespaces) and TUsesClauses.AddUnit(Source.Tree.Tokens, Source.Offset(Source.Line),
        'System.SysUtils', Source.LineBreak, UsesEdit) then
        AEdits := AEdits + [UsesEdit];
      Exit(True);
    end;
    AEdits := [TypeDeclaration(Source, InTypeSection, [
      '// Nur ein Helper je Typ ist wirksam: der zuletzt sichtbare.',
      Format('%s = %s helper for %s', [HelperName, Kind, TypeName]),
      'public', 'end;'])];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ Klassenbefehle }

/// <summary>Deklarationen vor "end" der Klasse, Rümpfe hinter ihre letzte Methode.</summary>
function AddToClass(ASource: TCommandSource; const AClass: TIndexSymbol; const ADeclarations: array of string;
  const ABodies: string): TArray<TTextEdit>;
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

/// <summary>Hinweis nach /singleton, wenn die Klasse schon Konstruktoren hat (#298); '' ohne.</summary>
function SingletonConstructorNote(ASource: TCommandSource; const AClassName: string): string;
var
  Symbol: TIndexSymbol;
  Names: TArray<string>;
begin
  Names := nil;
  for Symbol in ASource.UnitIndex.Symbols do
    if (Symbol.Kind = TIndexSymbolKind.Constructor_) and SameText(Symbol.Container, AClassName) and
      not MatchText(Symbol.Name, Names) then
      Names := Names + [Symbol.Name];
  Result := '';
  if Names <> nil then
    Result := Format('/singleton: Konstruktor %s bleibt unverändert und öffentlich; Instance ruft Create ohne ' +
      'Parameter', [string.Join(', ', Names)]);
end;

function ExecuteSingleton(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol: TIndexSymbol;
  Name, Note, Uri: string;
  Host: ISlashHost;
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
    // Ein vorhandener Konstruktor bleibt, wie er ist; der Hinweis nennt ihn.
    Note := SingletonConstructorNote(Source, Name);
    Host := AContext.Host;
    Uri := AContext.Uri;
    if (Host <> nil) and (Note <> '') then
      AContext.Defer(
        procedure
        begin
          Host.Notify(Uri, Note);
        end);
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /encapsulate }

/// <summary>Ein Feldname mit F-Präfix: FName, nicht Farbe.</summary>
function HasFieldPrefix(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and CharInSet(AName[1], ['F', 'f']) and CharInSet(AName[2], ['A'..'Z']);
end;

/// <summary>Benennt in den Methodenrümpfen von AClassName das Feld AOld in ANew um: der Name allein
/// oder hinter "Self.", nicht hinter einem anderen Ausdruck mit Punkt.</summary>
function RenameInMethods(ASource: TCommandSource; const AClassName, AOld, ANew: string): TArray<TTextEdit>;
var
  Tokens: TArray<TPascalToken>;
  Ranges: TArray<TTextRange>;
  Node: TSyntaxNode;
  Index, Before: Integer;
  Range: TTextRange;
  Inside: Boolean;

  procedure Collect(ANode: TSyntaxNode);
  var
    Child: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.RoutineDecl) and StartsText(AClassName + '.', ANode.Name) then
    begin
      Ranges := Ranges + [TTextRange.Create(ANode.StartPos, ANode.EndPos)];
      Exit;
    end;
    for Child := 0 to ANode.ChildCount - 1 do
      Collect(ANode[Child]);
  end;

begin
  Result := nil;
  Ranges := nil;
  Node := ASource.Tree.Root;
  Collect(Node);
  Tokens := TPascalLexer.Tokenize(ASource.Text);
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(Tokens[Index].Text, AOld) then
      Continue;
    Inside := False;
    for Range in Ranges do
      if (Tokens[Index].StartPos.Line > Range.StartPos.Line) and (Tokens[Index].StartPos.Line <= Range.EndPos.Line) then
        Inside := True;
    if not Inside then
      Continue;
    Before := Index - 1;
    while (Before >= 0) and (Tokens[Before].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Before);
    if (Before >= 0) and Tokens[Before].IsSymbol('.') then
    begin
      Dec(Before);
      while (Before >= 0) and (Tokens[Before].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
        Dec(Before);
      if (Before < 0) or not SameText(Tokens[Before].Text, 'Self') then
        Continue;
    end;
    Result := Result + [TTextEdit.Create(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos), ANew)];
  end;
end;

function ExecuteEncapsulate(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  ClassSymbol, Field, Symbol: TIndexSymbol;
  Name, FieldName, OldName: string;
  Found, Rename: Boolean;
begin
  AEdits := nil;
  OldName := Trim(AContext.Arguments);
  if not IsValidIdent(OldName) then
    Exit(Fail('Erwartet wird /encapsulate FName', AReason));
  // Ohne F-Präfix (#298): das Feld heißt danach FName, die Property trägt den alten Namen, damit
  // Verwendungen außerhalb der Klasse gültig bleiben; in den eigenen Methoden wird es umbenannt.
  Rename := not HasFieldPrefix(OldName);
  if Rename then
  begin
    Name := OldName;
    FieldName := 'F' + UpperCase(Copy(OldName, 1, 1)) + Copy(OldName, 2, MaxInt);
  end
  else
  begin
    Name := Copy(OldName, 2, MaxInt);
    FieldName := OldName;
  end;
  Source := TCommandSource.Create(AContext);
  try
    if not Source.ClassAt(ClassSymbol) then
      Exit(Fail('/encapsulate gilt nur in einer Klasse oder einer ihrer Methoden', AReason));
    Found := False;
    for Symbol in FieldsOf(Source, ClassSymbol) do
    begin
      if SameText(Symbol.Name, OldName) then
      begin
        Field := Symbol;
        Found := True;
      end;
      if Rename and SameText(Symbol.Name, FieldName) then
        Exit(Fail(Format('%s gibt es schon in %s', [FieldName, ClassSymbol.Name]), AReason));
    end;
    if not Found then
      Exit(Fail('Kein Feld ' + OldName + ' in ' + ClassSymbol.Name, AReason));
    if Field.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate] then
      Exit(Fail(OldName + ' ist schon private', AReason));
    // Nur Felder, die allein in ihrer Zeile stehen ("FName: string;").
    if (Field.Range.StartPos.Line <> Field.Range.EndPos.Line) or
      not StartsText(OldName + ':', StringReplace(Trim(Source.Lines[Field.Range.StartPos.Line]), ' :', ':', [])) or
      (Pos(',', Source.Lines[Field.Range.StartPos.Line]) > 0) then
      Exit(Fail(OldName + ' muss allein in seiner Zeile deklariert sein', AReason));
    AEdits := AddToClass(Source, ClassSymbol, ['private', Format('%s: %s;', [FieldName, Field.TypeName]),
      Format('procedure Set%s(const Value: %s);', [Name, Field.TypeName]), 'public',
      Format('property %s: %s read %s write Set%s;', [Name, Field.TypeName, FieldName, Name])],
      Join(Source, [Format('procedure %s.Set%s(const Value: %s);', [ClassSymbol.Name, Name, Field.TypeName]),
      TSetterGenerator.Body(FieldName, 'Value', TSetterGenerator.NotifyCall(Source, AContext.Index, ClassSymbol),
      Source.LineBreak)]));
    // Alte Deklaration entfernen.
    AEdits := AEdits + [TTextEdit.Create(TTextRange.Create(Field.Range.StartPos.Line, 0,
      Field.Range.StartPos.Line + 1, 0), ''), Source.RemoveCommand];
    if Rename then
      AEdits := AEdits + RenameInMethods(Source, ClassSymbol.Name, OldName, FieldName);
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

function ExecuteAssign(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
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

function ExecuteJson(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeSymbol, Field: TIndexSymbol;
  Name, Key, ToJson, FromJson, Text: string;
  IsClass: Boolean;
  UsesEdit: TTextEdit;
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
      TUsesClauses.AddUnit(Source.Tree.Tokens, Source.Offset(TypeSymbol.Range.StartPos.Line), 'System.JSON',
      Source.LineBreak, UsesEdit) then
      AEdits := AEdits + [UsesEdit];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /exception }

function ExecuteException(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>;
  out AReason: string): Boolean;
var
  Source: TCommandSource;
  Name, Ancestor: string;
  InTypeSection: Boolean;
begin
  AEdits := nil;
  if Pos(':', AContext.Arguments) > 0 then
  begin
    Name := Trim(Copy(AContext.Arguments, 1, Pos(':', AContext.Arguments) - 1));
    Ancestor := Trim(Copy(AContext.Arguments, Pos(':', AContext.Arguments) + 1, MaxInt));
  end
  else
  begin
    Name := Trim(AContext.Arguments);
    Ancestor := 'Exception';
  end;
  if not IsValidIdent(Name) or not IsValidIdent(Ancestor, True) then
    Exit(Fail('Erwartet wird /exception EName [: EBasis]', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, 'exception', InTypeSection, AReason) then
      Exit(False);
    AEdits := [TypeDeclaration(Source, InTypeSection, [Format('%s = class(%s);', [Name, Ancestor])])];
    Result := True;
  finally
    Source.Free;
  end;
end;

{ /thread }

function ExecuteThread(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean;
var
  Source: TCommandSource;
  TypeName: string;
  InTypeSection: Boolean;
  UsesEdit: TTextEdit;
begin
  AEdits := nil;
  TypeName := Trim(AContext.Arguments);
  if not IsValidIdent(TypeName) then
    Exit(Fail('Erwartet wird /thread TName', AReason));
  Source := TCommandSource.Create(AContext);
  try
    if not TypePlace(Source, 'thread', InTypeSection, AReason) then
      Exit(False);
    AEdits := [TypeDeclaration(Source, InTypeSection, [Format('%s = class(TThread)', [TypeName]), 'protected',
      '  procedure Execute; override;', 'end;']), Source.AddBody(TypeName, Join(Source, [
      Format('procedure %s.Execute;', [TypeName]), 'begin',
      '  // Wartet niemand auf den Thread, im Konstruktor FreeOnTerminate := True setzen.',
      '  while not Terminated do', '  begin',
      '    // Ergebnisse im Hauptthread zeigen: TThread.Queue(nil, procedure begin … end);', '  end;', 'end;']))];
    if not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(Source.Tree.Tokens), 'System.Classes', AContext.Namespaces) and
      TUsesClauses.AddUnit(Source.Tree.Tokens, Source.Offset(Source.Line), 'System.Classes', Source.LineBreak,
      UsesEdit) then
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
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, True, AEdits, AReason);
    end));
  ARegistry.Register(Command('enum!', 'Aufzählungstyp ohne Präfix anlegen', '/enum! TFarbe rot, gruen',
    function(const AContext: TSlashContext; out AEdits: TArray<TTextEdit>; out AReason: string): Boolean
    begin
      Result := ExecuteEnum(AContext, False, AEdits, AReason);
    end));
  ARegistry.Register(Command('helper', 'Record- bzw. Class-Helper anlegen', '/helper TFarbe', ExecuteHelper));
  ARegistry.Register(Command('singleton', 'Klasse zum Singleton machen', '/singleton', ExecuteSingleton));
  ARegistry.Register(Command('encapsulate', 'Feld in Property mit Setter umwandeln', '/encapsulate FName',
    ExecuteEncapsulate));
  ARegistry.Register(Command('assign', 'Assign für alle Felder anlegen', '/assign', ExecuteAssign));
  ARegistry.Register(Command('json', 'ToJson und FromJson anlegen', '/json', ExecuteJson));
  ARegistry.Register(Command('exception', 'Ausnahmeklasse anlegen', '/exception EImportFehler', ExecuteException));
  ARegistry.Register(Command('thread', 'TThread-Nachfahre mit Execute anlegen', '/thread TWorker', ExecuteThread));
end;

end.
